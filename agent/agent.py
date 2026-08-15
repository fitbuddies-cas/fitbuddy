"""FitBuddy analysis agent — a Python spike of US-3 (AI analysis on demand).

Same shape as the course example (`fitbuddy_agent.py`): custom tools in an
in-process MCP server, wired into the agent loop via ClaudeAgentOptions.

The split that matters:
  * tools  -> arithmetic over the user's own Hevy data (deterministic)
  * model  -> judgement, wording, which recommendation to give

The system prompt below and the tool contracts are the artifacts to port
into the Swift `InferenceService` once they hold up against US-3's
acceptance criteria.

Run:
    export HEVY_API_KEY='...'
    export ANTHROPIC_API_KEY='...'
    python agent.py                       # default: "analyse my last 90 days"
    python agent.py "Can I add weight to my squat this week?"
"""

from __future__ import annotations

import asyncio
import json
import sys

from claude_agent_sdk import (
    AssistantMessage,
    ClaudeAgentOptions,
    ResultMessage,
    TextBlock,
    ToolUseBlock,
    create_sdk_mcp_server,
    query,
    tool,
)

import metrics
from hevy import HevyClient, HevyError, Workout, api_key_from_env

DEFAULT_WINDOW_DAYS = 90
MODEL = "claude-opus-5"


# ── Data access: fetch once per window, reuse across tool calls ───────────
# Five tools over the same 90 days should not mean five trips to Hevy.

_client: HevyClient | None = None
_workout_cache: dict[int, list[Workout]] = {}
_muscle_group_map: dict[str, str] | None = None
_lock = asyncio.Lock()


def _get_client() -> HevyClient:
    global _client
    if _client is None:
        _client = HevyClient(api_key_from_env())
    return _client


async def _workouts(days: int) -> list[Workout]:
    async with _lock:
        if days not in _workout_cache:
            _workout_cache[days] = await _get_client().fetch_workouts(days)
        return _workout_cache[days]


async def _muscle_groups() -> dict[str, str]:
    global _muscle_group_map
    async with _lock:
        if _muscle_group_map is None:
            _muscle_group_map = await _get_client().fetch_muscle_group_map()
        return _muscle_group_map


def _ok(payload: dict) -> dict:
    return {"content": [{"type": "text", "text": json.dumps(payload, ensure_ascii=False)}]}


def _fail(message: str) -> dict:
    return {"content": [{"type": "text", "text": f"ERROR: {message}"}], "is_error": True}


def _window(args: dict) -> int:
    try:
        days = int(args.get("days") or DEFAULT_WINDOW_DAYS)
    except (TypeError, ValueError):
        return DEFAULT_WINDOW_DAYS
    return max(1, min(days, 365))


# ── Tools ────────────────────────────────────────────────────────────────

@tool(
    "fetch_workouts",
    "Fetch the user's logged Hevy workouts for the last N days. Returns one "
    "entry per session with date, title, exercises and set counts. Call this "
    "first when you need to know what the user actually trained; use the "
    "aggregate tools below for numbers.",
    {"days": int},
)
async def fetch_workouts(args):
    days = _window(args)
    try:
        workouts = await _workouts(days)
    except HevyError as error:
        return _fail(str(error))

    return _ok(
        {
            "window_days": days,
            "sessions": [
                {
                    "date": workout.start_time.date().isoformat(),
                    "title": workout.title,
                    "exercises": [
                        {"name": exercise.title, "sets": len(exercise.sets)}
                        for exercise in workout.exercises
                    ],
                }
                for workout in workouts
            ],
        }
    )


@tool(
    "training_volume",
    "Total training volume in kg (weight x reps over working sets), session "
    "count, training days and average training days per week for the last N "
    "days, plus a per-calendar-week breakdown. Use this to judge whether "
    "load is rising, flat or falling.",
    {"days": int},
)
async def training_volume(args):
    days = _window(args)
    try:
        workouts = await _workouts(days)
    except HevyError as error:
        return _fail(str(error))
    return _ok(metrics.training_volume(workouts, days))


@tool(
    "muscle_group_balance",
    "Training days and volume per muscle group over the last N days, plus "
    "which group is trained most and least. Use this to spot imbalances "
    "between muscle groups before recommending more of anything.",
    {"days": int},
)
async def muscle_group_balance(args):
    days = _window(args)
    try:
        workouts = await _workouts(days)
        groups = await _muscle_groups()
    except HevyError as error:
        return _fail(str(error))
    return _ok(metrics.muscle_group_balance(workouts, groups, days))


@tool(
    "recovery_signal",
    "Training density over the last N days (default 7): training days, "
    "sessions, longest run of consecutive training days, days since the last "
    "session, and a high_frequency flag set when the user trained on 6 or "
    "more days in the window. Always check this before recommending any "
    "increase in load.",
    {"days": int},
)
async def recovery_signal(args):
    try:
        days = int(args.get("days") or 7)
    except (TypeError, ValueError):
        days = 7
    days = max(1, min(days, 90))
    try:
        # Recovery looks at a short window but reads from the wider fetch, so
        # "days since last session" stays correct even after a long layoff.
        workouts = await _workouts(DEFAULT_WINDOW_DAYS)
    except HevyError as error:
        return _fail(str(error))
    return _ok(metrics.recovery_signal(workouts, days))


@tool(
    "exercise_progression",
    "Heaviest working set per session for one exercise over the last N days, "
    "with reps and an estimated 1RM. Matches the exercise name as a "
    "case-insensitive substring. Use this to ground any concrete weight "
    "recommendation in the numbers the user actually lifted.",
    {"exercise": str, "days": int},
)
async def exercise_progression(args):
    days = _window(args)
    exercise = str(args.get("exercise") or "")
    try:
        workouts = await _workouts(days)
    except HevyError as error:
        return _fail(str(error))
    return _ok(metrics.exercise_progression(workouts, exercise))


fitbuddy_tools = create_sdk_mcp_server(
    name="fitbuddy",
    version="0.1.0",
    tools=[
        fetch_workouts,
        training_volume,
        muscle_group_balance,
        recovery_signal,
        exercise_progression,
    ],
)


# ── System prompt: the artifact that ports to Swift ───────────────────────
# Each paragraph maps to an acceptance criterion in docs/REQUIREMENTS.md
# US-3. Keep the mapping when editing — it is what makes the prompt testable.

SYSTEM_PROMPT = """\
You are FitBuddy, a training assistant. You analyse one person's own \
strength-training history and tell them what to do next.

Ground every claim in the tools. You have no benchmarks, norms, or data from \
other athletes, and you must not invent any — if a number is not in a tool \
result, you do not have it.

Check recovery before you recommend more work. If the recovery tool reports \
high_frequency, say so explicitly and do not recommend any increase in load \
without addressing rest first.

Be concrete. Name an exercise and a number: "increase your bench press from \
60 kg to 62.5 kg", not "try going heavier". Base the number on the top sets \
the progression tool returns. Estimated 1RM is an estimate — reason with it, \
but never quote it as something the user lifted.

Distinguish volume from intensity. If volume is high while working weights \
stay flat, recommend raising intensity rather than adding more sets.

Look at the whole week, not one lift. If one muscle group is trained far more \
often than another, say so.

State your data basis in one line at the end: how many sessions, over what \
period. If fewer than 5 sessions were logged in the window, say plainly that \
the basis is thin and keep the recommendation cautious.

You are not a medical device. Do not diagnose injuries or give medical advice.

Answer in English, in prose. No headers, no bullet lists — a few short \
paragraphs a person can read on a phone."""


DEFAULT_PROMPT = (
    f"Analyse my training over the last {DEFAULT_WINDOW_DAYS} days and tell me "
    "what to change this week."
)

options = ClaudeAgentOptions(
    model=MODEL,
    system_prompt=SYSTEM_PROMPT,
    mcp_servers={"fitbuddy": fitbuddy_tools},
    allowed_tools=[
        "mcp__fitbuddy__fetch_workouts",
        "mcp__fitbuddy__training_volume",
        "mcp__fitbuddy__muscle_group_balance",
        "mcp__fitbuddy__recovery_signal",
        "mcp__fitbuddy__exercise_progression",
    ],
    max_turns=12,
    max_budget_usd=0.50,
)


async def main() -> int:
    prompt = " ".join(sys.argv[1:]).strip() or DEFAULT_PROMPT

    try:
        api_key_from_env()  # fail fast, before spending a single token
    except HevyError as error:
        print(error, file=sys.stderr)
        return 1

    async for message in query(prompt=prompt, options=options):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, ToolUseBlock):
                    print(f">>> TOOL {block.name}  {block.input}", file=sys.stderr)
                elif isinstance(block, TextBlock):
                    print(block.text)
        elif isinstance(message, ResultMessage):
            cost = message.total_cost_usd or 0.0
            print(f"\n--- turns: {message.num_turns} | cost: ${cost:.4f} ---", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
