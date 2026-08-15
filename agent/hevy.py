"""Hevy API client + normalization for the FitBuddy analysis spike.

Keeps everything that touches the network in one place. The rest of the
spike works on the plain dataclasses defined here, so `metrics.py` stays
pure and portable to Swift.

The API key is read from the environment and never written to disk —
mirroring the app's BYO-key rule (ADR-004, ADR-003).
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Iterable

import httpx

BASE_URL = "https://api.hevyapp.com/v1"

# Page-size caps per Hevy's public API docs. If a request 400s, this is the
# first thing to check — the caps are not the same for both endpoints.
WORKOUT_PAGE_SIZE = 10
TEMPLATE_PAGE_SIZE = 100

# Safety net: stop paging even if the "older than cutoff" check never trips.
MAX_PAGES = 60


class HevyError(RuntimeError):
    """Any failure talking to Hevy."""


class HevyAuthError(HevyError):
    """HTTP 401 — the key was rejected. Same signal HevyKeyValidator uses."""


@dataclass(frozen=True)
class WorkoutSet:
    weight_kg: float | None
    reps: int | None
    set_type: str

    @property
    def is_working_set(self) -> bool:
        """Warmups are excluded from volume by default — see metrics.py."""
        return self.set_type.lower() != "warmup"

    @property
    def volume_kg(self) -> float:
        if self.weight_kg is None or self.reps is None:
            return 0.0
        return self.weight_kg * self.reps


@dataclass(frozen=True)
class Exercise:
    title: str
    template_id: str | None
    sets: list[WorkoutSet]


@dataclass(frozen=True)
class Workout:
    id: str
    title: str
    start_time: datetime
    exercises: list[Exercise]

    @property
    def day(self):
        return self.start_time.date()


def api_key_from_env() -> str:
    key = os.environ.get("HEVY_API_KEY", "").strip()
    if not key:
        raise HevyError(
            "HEVY_API_KEY is not set. Export your own Hevy key first:\n"
            "  export HEVY_API_KEY='...'\n"
            "Get it from the Hevy web app under Settings -> Developer."
        )
    return key


def _parse_time(raw: str) -> datetime:
    """Hevy sends ISO-8601. Normalize to aware UTC so date math is safe."""
    text = raw.replace("Z", "+00:00")
    parsed = datetime.fromisoformat(text)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _extract_list(payload: Any, *candidate_keys: str) -> list[dict]:
    """Pull the item list out of a paged response.

    Defensive on purpose: the exact key is the one part of the contract most
    likely to differ from what we assumed, and a clear error beats a silent
    empty result.
    """
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        for key in candidate_keys:
            value = payload.get(key)
            if isinstance(value, list):
                return value
        raise HevyError(
            f"Unexpected response shape: expected one of {candidate_keys}, "
            f"got keys {sorted(payload)}"
        )
    raise HevyError(f"Unexpected response type: {type(payload).__name__}")


def _page_count(payload: Any) -> int:
    if isinstance(payload, dict):
        for key in ("page_count", "pageCount"):
            value = payload.get(key)
            if isinstance(value, int) and value > 0:
                return value
    return 1


def _normalize_workout(raw: dict) -> Workout:
    exercises = []
    for raw_exercise in raw.get("exercises") or []:
        sets = [
            WorkoutSet(
                weight_kg=raw_set.get("weight_kg"),
                reps=raw_set.get("reps"),
                set_type=str(raw_set.get("type") or "normal"),
            )
            for raw_set in (raw_exercise.get("sets") or [])
        ]
        exercises.append(
            Exercise(
                title=str(raw_exercise.get("title") or "Unknown exercise"),
                template_id=raw_exercise.get("exercise_template_id"),
                sets=sets,
            )
        )
    return Workout(
        id=str(raw.get("id") or ""),
        title=str(raw.get("title") or "Workout"),
        start_time=_parse_time(str(raw["start_time"])),
        exercises=exercises,
    )


class HevyClient:
    def __init__(self, api_key: str, timeout: float = 20.0) -> None:
        self._headers = {"api-key": api_key, "accept": "application/json"}
        self._timeout = timeout

    async def _get(self, client: httpx.AsyncClient, path: str, page: int, page_size: int) -> Any:
        try:
            response = await client.get(
                f"{BASE_URL}/{path}",
                params={"page": page, "pageSize": page_size},
                headers=self._headers,
                timeout=self._timeout,
            )
        except httpx.HTTPError as error:
            raise HevyError(f"Could not reach Hevy: {error}") from error

        if response.status_code == 401:
            raise HevyAuthError("Hevy rejected the API key (HTTP 401).")
        if response.status_code >= 400:
            raise HevyError(f"Hevy returned HTTP {response.status_code} for /{path}.")
        return response.json()

    async def fetch_workouts(self, days: int, now: datetime | None = None) -> list[Workout]:
        """Workouts started within the last `days` days, newest first.

        Assumes Hevy returns workouts newest-first and stops paging once a
        whole page falls before the cutoff. If that ordering assumption ever
        breaks, this silently under-fetches — so it is asserted loudly in the
        README rather than buried here.
        """
        now = now or datetime.now(timezone.utc)
        cutoff = now - timedelta(days=days)
        collected: list[Workout] = []

        async with httpx.AsyncClient() as client:
            for page in range(1, MAX_PAGES + 1):
                payload = await self._get(client, "workouts", page, WORKOUT_PAGE_SIZE)
                raw_items = _extract_list(payload, "workouts", "data", "items")
                if not raw_items:
                    break

                workouts = [_normalize_workout(item) for item in raw_items]
                collected.extend(w for w in workouts if w.start_time >= cutoff)

                if all(w.start_time < cutoff for w in workouts):
                    break
                if page >= _page_count(payload):
                    break

        collected.sort(key=lambda w: w.start_time, reverse=True)
        return collected

    async def fetch_muscle_group_map(self) -> dict[str, str]:
        """`exercise_template_id` -> primary muscle group."""
        mapping: dict[str, str] = {}
        async with httpx.AsyncClient() as client:
            for page in range(1, MAX_PAGES + 1):
                payload = await self._get(
                    client, "exercise_templates", page, TEMPLATE_PAGE_SIZE
                )
                raw_items = _extract_list(payload, "exercise_templates", "data", "items")
                if not raw_items:
                    break
                for item in raw_items:
                    template_id = item.get("id")
                    group = item.get("primary_muscle_group")
                    if template_id and group:
                        mapping[str(template_id)] = str(group)
                if page >= _page_count(payload):
                    break
        return mapping


# Fallback for exercises whose template is missing from the catalogue
# (custom exercises, mostly). Keyword match on the exercise title.
_TITLE_FALLBACK: tuple[tuple[tuple[str, ...], str], ...] = (
    (("squat", "leg press", "lunge", "leg extension"), "quadriceps"),
    (("deadlift", "romanian", "leg curl", "hamstring"), "hamstrings"),
    (("bench", "chest", "pec", "push up", "push-up"), "chest"),
    (("row", "pulldown", "pull up", "pull-up", "chin up", "lat"), "lats"),
    (("curl",), "biceps"),
    (("tricep", "pushdown", "skullcrusher", "dip"), "triceps"),
    (("shoulder", "overhead press", "lateral raise", "ohp"), "shoulders"),
    (("calf",), "calves"),
    (("crunch", "plank", "ab ", "core"), "abdominals"),
    (("run", "bike", "cycl", "row erg", "treadmill", "elliptical"), "cardio"),
)


def resolve_muscle_group(exercise: Exercise, mapping: dict[str, str]) -> str:
    if exercise.template_id and exercise.template_id in mapping:
        return mapping[exercise.template_id]
    title = exercise.title.lower()
    for keywords, group in _TITLE_FALLBACK:
        if any(keyword in title for keyword in keywords):
            return group
    return "unknown"


def flatten_exercises(workouts: Iterable[Workout]) -> list[tuple[Workout, Exercise]]:
    return [(workout, exercise) for workout in workouts for exercise in workout.exercises]
