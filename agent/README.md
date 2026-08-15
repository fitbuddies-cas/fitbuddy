# FitBuddy Analysis Agent (Python spike)

A throwaway-by-design prototype of **US-3 — AI-Analyse auf Knopfdruck**. It runs
the same analysis the iOS app will run, but in Python, so the prompt and the
tool contracts can be iterated in seconds instead of through an Xcode build.

Nothing here ships. Two things are meant to survive and move into Swift:

| Artifact | Ports to |
|---|---|
| `SYSTEM_PROMPT` in `agent.py` | `Features/Analysis/` — the `InferenceService` prompt |
| The functions in `metrics.py` | `Core/Connector/domain/` — deterministic, no LLM involved |

## Design rule

Tools do arithmetic, the model does judgement.

Every number the model sees comes from a pure function over *this user's* Hevy
data, so US-3 AC3 ("prompt contains only the logged-in user's data — no
benchmarks or norms from other users") holds by construction: no tool in this
server is capable of returning anyone else's numbers.

## Layout

```
hevy.py       Hevy API client + normalization into plain dataclasses
metrics.py    Pure metric functions — the port candidates
agent.py      @tool wrappers, the in-process MCP server, the system prompt
```

## Run

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

export HEVY_API_KEY='...'        # your own key, Hevy web app -> Settings -> Developer
export ANTHROPIC_API_KEY='...'   # your own key

python agent.py
python agent.py "Can I add weight to my squat this week?"
```

Tool calls and the cost summary go to stderr, the answer to stdout — so
`python agent.py > answer.txt` gives you just the recommendation.

Keys are read from the environment and never written to disk, matching the
BYO-key rule in ADR-003 / ADR-004. Do not add a `.env` file with real keys.

## Tools

| Tool | Returns | Serves |
|---|---|---|
| `fetch_workouts` | Sessions with date, title, exercises | US-2 AC1 |
| `training_volume` | Total kg, sessions, Ø training days/week, per-week split | US-2 AC1, US-3 AC5 |
| `muscle_group_balance` | Training days + volume per muscle group, most/least trained | US-3 AC4, AC8 |
| `recovery_signal` | Training days in window, streak, `high_frequency` flag | US-3 AC6 |
| `exercise_progression` | Heaviest working set per session, estimated 1RM | US-3 AC7 |

## Open decisions for the team

Three judgement calls are baked in as defaults. Each is a real product
decision, not a technical detail — worth confirming before the Swift port:

1. **Warmup sets are excluded from volume** (`metrics.EXCLUDE_WARMUPS`).
   Counting them inflates tonnage for anyone who logs warmups diligently.
2. **Volume is `sum(weight_kg × reps)` over sets.** `docs/REQUIREMENTS.md`
   US-2 AC1 phrases it as "Gewicht × Reps × Sets"; since Hevy stores one row
   per set, summing per set already accounts for the set count. Multiplying by
   sets again would double-count. The requirement wording may want a tweak.
3. **Estimated 1RM uses Epley** (`weight × (1 + reps/30)`) and is labelled as
   an estimate in the tool output so the model does not quote it as a lift the
   user actually performed.

## Known assumptions to verify against live data

This has not yet been run against a real Hevy account — the following are
assumptions from the API docs, and are the first things to check on the first
live run:

- **Page-size caps**: `/workouts` at 10, `/exercise_templates` at 100
  (`hevy.py`). A `400` on the first call points here.
- **Ordering**: `fetch_workouts` assumes Hevy returns workouts newest-first and
  stops paging once a whole page falls before the cutoff. If the ordering is
  different, it will silently under-fetch — check the session count against the
  Hevy app for the same window.
- **Response keys**: `workouts` / `exercise_templates` for the item lists,
  `page_count` for paging. `_extract_list` raises with the actual keys if the
  shape differs, rather than returning an empty result.
- **Muscle groups** come from `exercise_templates.primary_muscle_group`. Custom
  exercises with no template fall back to a keyword match on the title, and
  anything unmatched lands in `unknown` — `muscle_group_balance` reports that
  count so a bad mapping is visible rather than silent.

## Next step

Turn US-3's nine acceptance criteria into assertions over the agent's output
(AC6: a high-frequency week must produce a recovery caveat; AC7: the answer must
contain an exercise name and a number). That gives the prompt a regression test
before it moves into Swift.
