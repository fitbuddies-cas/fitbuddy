"""Deterministic training metrics.

Everything here is pure: workouts in, numbers out. No network, no LLM.
That split is the point of the spike — the model does judgement, these
functions do arithmetic, so US-3 AC3 ("only the logged-in user's data")
holds by construction: no tool here can return anyone else's numbers.

These are the functions to port to Swift once the prompt stabilizes.
"""

from __future__ import annotations

from collections import defaultdict
from datetime import date, datetime, timedelta, timezone

from hevy import Exercise, Workout, resolve_muscle_group

# Warmup sets are excluded from volume. This is a product decision, not a
# Hevy one — flagged in the README for the team to confirm.
EXCLUDE_WARMUPS = True


def _sets_for_volume(exercise: Exercise):
    if EXCLUDE_WARMUPS:
        return [s for s in exercise.sets if s.is_working_set]
    return list(exercise.sets)


def _round(value: float, digits: int = 1) -> float:
    return round(value, digits)


def _training_days(workouts: list[Workout]) -> set[date]:
    return {w.day for w in workouts}


def training_volume(workouts: list[Workout], days: int) -> dict:
    """Total tonnage, session count and weekly cadence over the window.

    Volume is sum(weight_kg * reps) across working sets. REQUIREMENTS.md
    US-2 AC1 phrases this as "Gewicht x Reps x Sets"; because Hevy stores
    one row per set, summing per set already accounts for the set count —
    multiplying by sets again would double-count.
    """
    total = 0.0
    per_week: dict[str, float] = defaultdict(float)

    for workout in workouts:
        week = workout.start_time.isocalendar()
        week_key = f"{week.year}-W{week.week:02d}"
        for exercise in workout.exercises:
            for workout_set in _sets_for_volume(exercise):
                total += workout_set.volume_kg
                per_week[week_key] += workout_set.volume_kg

    weeks = max(days / 7, 1e-9)
    day_count = len(_training_days(workouts))

    return {
        "window_days": days,
        "sessions": len(workouts),
        "training_days": day_count,
        "total_volume_kg": _round(total),
        "avg_training_days_per_week": _round(day_count / weeks, 2),
        "volume_by_week": {key: _round(value) for key, value in sorted(per_week.items())},
        "warmups_excluded": EXCLUDE_WARMUPS,
    }


def muscle_group_balance(
    workouts: list[Workout], muscle_group_map: dict[str, str], days: int
) -> dict:
    """Sessions and volume per muscle group — the input for US-3 AC8."""
    sessions_per_group: dict[str, set[date]] = defaultdict(set)
    volume_per_group: dict[str, float] = defaultdict(float)

    for workout in workouts:
        for exercise in workout.exercises:
            group = resolve_muscle_group(exercise, muscle_group_map)
            sessions_per_group[group].add(workout.day)
            for workout_set in _sets_for_volume(exercise):
                volume_per_group[group] += workout_set.volume_kg

    weeks = max(days / 7, 1e-9)
    groups = {
        group: {
            "training_days": len(day_set),
            "days_per_week": _round(len(day_set) / weeks, 2),
            "volume_kg": _round(volume_per_group[group]),
        }
        for group, day_set in sorted(
            sessions_per_group.items(), key=lambda item: -len(item[1])
        )
    }

    trained = [g for g in groups if g not in ("unknown", "cardio")]
    most = max(trained, key=lambda g: groups[g]["training_days"], default=None)
    least = min(trained, key=lambda g: groups[g]["training_days"], default=None)

    return {
        "window_days": days,
        "groups": groups,
        "most_trained": most,
        "least_trained": least,
        "unresolved_exercises": groups.get("unknown", {}).get("training_days", 0),
    }


def recovery_signal(workouts: list[Workout], days: int = 7, now: datetime | None = None) -> dict:
    """Training density in the recent window — the input for US-3 AC6.

    Returns the raw counts plus a `high_frequency` flag at the AC6 threshold
    (>= 6 training days in the last 7). The flag is a fact, not advice; what
    to do about it is the model's call.
    """
    now = now or datetime.now(timezone.utc)
    cutoff = now - timedelta(days=days)
    recent = [w for w in workouts if w.start_time >= cutoff]
    training_days = sorted(_training_days(recent))

    longest_streak = 0
    current_streak = 0
    previous: date | None = None
    for day in training_days:
        current_streak = current_streak + 1 if previous and (day - previous).days == 1 else 1
        longest_streak = max(longest_streak, current_streak)
        previous = day

    last_session = max((w.start_time for w in workouts), default=None)

    return {
        "window_days": days,
        "training_days": len(training_days),
        "sessions": len(recent),
        "longest_consecutive_days": longest_streak,
        "days_since_last_session": (
            (now - last_session).days if last_session else None
        ),
        "high_frequency": len(training_days) >= 6,
    }


def _best_working_set(exercise: Exercise):
    candidates = [
        s for s in _sets_for_volume(exercise) if s.weight_kg is not None and s.reps
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda s: (s.weight_kg or 0, s.reps or 0))


def exercise_progression(workouts: list[Workout], query: str) -> dict:
    """Heaviest working set per session for one exercise — US-3 AC7.

    Matching is a case-insensitive substring on the exercise title. When the
    query matches several distinct titles they are all reported back so the
    model can ask which one, rather than silently picking one.
    """
    needle = query.strip().lower()
    if not needle:
        return {"error": "Empty exercise query."}

    matched_titles: set[str] = set()
    points: list[dict] = []

    for workout in workouts:
        for exercise in workout.exercises:
            if needle not in exercise.title.lower():
                continue
            matched_titles.add(exercise.title)
            best = _best_working_set(exercise)
            if best is None:
                continue
            weight = best.weight_kg or 0.0
            reps = best.reps or 0
            points.append(
                {
                    "date": workout.start_time.date().isoformat(),
                    "top_set_weight_kg": _round(weight),
                    "top_set_reps": reps,
                    # Epley. An estimate, labelled as one so the model does
                    # not quote it back as a measured number.
                    "estimated_1rm_kg": _round(weight * (1 + reps / 30)),
                }
            )

    if not points:
        return {
            "query": query,
            "matches": sorted(matched_titles),
            "sessions": [],
            "note": "No logged working sets matched this exercise in the window.",
        }

    points.sort(key=lambda point: point["date"])
    first, last = points[0], points[-1]

    return {
        "query": query,
        "matches": sorted(matched_titles),
        "ambiguous": len(matched_titles) > 1,
        "sessions": points,
        "heaviest_set_kg": max(p["top_set_weight_kg"] for p in points),
        "weight_change_kg": _round(
            last["top_set_weight_kg"] - first["top_set_weight_kg"]
        ),
    }
