#!/usr/bin/env python3
"""Generate the global-library seed migration from the app's seed JSON.

The seeded exercise and measurement libraries are the SAME data on the device
and on the server, and they must carry the SAME uuids. Hand-transcribing them
into SQL would work exactly once and then drift, so the SQL is generated from
the one source of truth the app already ships:

    MCPStrength/MCPStrength/Resources/exercise-seed.json
    MCPStrength/MCPStrength/Resources/measurement-seed.json

Regenerate after editing either file:

    python3 supabase/scripts/generate_library_seed.py

and commit the resulting migration alongside the JSON change. The generated
statements are idempotent upserts keyed on id, so re-running the migration
after adding rows to the JSON adds only the new rows.
"""

from __future__ import annotations

import json
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
RESOURCES = REPO / "MCPStrength" / "MCPStrength" / "Resources"
OUT = REPO / "supabase" / "migrations" / "20260815120300_library_seed.sql"

BODY_PARTS = {
    "arms", "back", "cardio", "chest", "core",
    "fullBody", "legs", "olympic", "other", "shoulders",
}
CATEGORIES = {
    "barbell", "dumbbell", "machineOther", "weightedBodyweight",
    "assistedBodyweight", "repsOnly", "cardio", "duration",
}
GROUPS = {"core", "bodyPart"}


def quote(text: str) -> str:
    """Single-quoted SQL string literal."""
    return "'" + text.replace("'", "''") + "'"


def uuid_literal(value: str) -> str:
    # Fail loudly on a malformed id rather than emit SQL that fails at apply
    # time with a less useful message. Seeded ids are a permanent contract; a
    # typo here detaches history from an exercise forever.
    import uuid

    return quote(str(uuid.UUID(value)))


def array_literal(values: list[str]) -> str:
    if not values:
        return "'{}'"
    return "array[" + ", ".join(quote(v) for v in values) + "]::text[]"


def load(name: str):
    path = RESOURCES / name
    if not path.exists():
        sys.exit(f"missing seed file: {path}")
    return json.loads(path.read_text())


def check(condition: bool, message: str) -> None:
    if not condition:
        sys.exit(f"seed validation failed: {message}")


def main() -> None:
    exercises = load("exercise-seed.json")
    measurements = load("measurement-seed.json")

    seen: set[str] = set()
    for row in exercises:
        check(row["id"] not in seen, f"duplicate exercise id {row['id']}")
        seen.add(row["id"])
        check(row["bodyPart"] in BODY_PARTS, f"unknown bodyPart {row['bodyPart']!r}")
        check(row["category"] in CATEGORIES, f"unknown category {row['category']!r}")

    seen = set()
    for row in measurements:
        check(row["id"] not in seen, f"duplicate measurement id {row['id']}")
        seen.add(row["id"])
        check(row["group"] in GROUPS, f"unknown group {row['group']!r}")

    lines: list[str] = []
    add = lines.append

    add("-- ============================================================================")
    add("-- 0004 — The seeded library (global rows, user_id IS NULL)")
    add("--")
    add("-- GENERATED FILE — do not edit by hand.")
    add("--   source: MCPStrength/MCPStrength/Resources/{exercise,measurement}-seed.json")
    add("--   regenerate: python3 supabase/scripts/generate_library_seed.py")
    add("--")
    add("-- These rows are the integrity constraint for the whole product. Without a")
    add("-- shared library with stable ids, every AI-generated plan invents its own")
    add("-- exercise names and a user's history for one movement fragments across")
    add('-- "Lateral Raise (Machine)" / "Machine Lateral Raise" / "Lat Raise" — and')
    add("-- progress tracking, the entire point, silently breaks.")
    add("--")
    add("-- THE UUIDS ARE A PERMANENT CONTRACT. They are baked into the seed JSON and")
    add("-- copied here verbatim; they are never generated at apply time. Every workout")
    add("-- ever logged points at an exercise by id, so a re-seed that hands an existing")
    add("-- exercise a NEW uuid detaches every user's history for that movement. There")
    add("-- is no good fix afterwards.")
    add("--")
    add("-- The upserts refresh only the LIBRARY-DEFINED fields (name, body_part,")
    add("-- category, aliases), matching ExerciseSeedImporter on the device. Per-user")
    add("-- settings live in exercise_preferences and are never touched by a re-seed.")
    add("-- ============================================================================")
    add("")
    add(f"-- {len(exercises)} exercises")
    add("insert into public.exercises")
    add("  (id, user_id, name, aliases, body_part, category, is_custom)")
    add("values")

    rows = []
    for row in exercises:
        rows.append(
            "  ({id}, null, {name}, {aliases}, {body}::public.body_part, "
            "{cat}::public.exercise_category, false)".format(
                id=uuid_literal(row["id"]),
                name=quote(row["name"]),
                aliases=array_literal(row.get("aliases") or []),
                body=quote(row["bodyPart"]),
                cat=quote(row["category"]),
            )
        )
    add(",\n".join(rows))
    add("on conflict (id) do update set")
    add("  name      = excluded.name,")
    add("  body_part = excluded.body_part,")
    add("  category  = excluded.category,")
    add("  aliases   = excluded.aliases;")
    add("")
    add("")
    add(f"-- {len(measurements)} measurement types")
    add("--")
    add("-- The seed JSON also carries a `unit` per type. There is no column for it:")
    add("-- MeasurementType has no unit in the SwiftData model either — the unit is")
    add("-- recorded per ENTRY, because a user can switch units and the entries already")
    add("-- written keep the unit they were taken in. The JSON field seeds the default")
    add("-- offered in the UI, which is a client concern.")
    add("insert into public.measurement_types")
    add("  (id, user_id, name, group_kind, sort_order)")
    add("values")

    rows = []
    for row in measurements:
        rows.append(
            "  ({id}, null, {name}, {group}::public.measurement_group, {order})".format(
                id=uuid_literal(row["id"]),
                name=quote(row["name"]),
                group=quote(row["group"]),
                order=int(row["sortOrder"]),
            )
        )
    add(",\n".join(rows))
    add("on conflict (id) do update set")
    add("  name       = excluded.name,")
    add("  group_kind = excluded.group_kind,")
    add("  sort_order = excluded.sort_order;")
    add("")

    OUT.write_text("\n".join(lines))
    print(f"wrote {OUT.relative_to(REPO)}")
    print(f"  {len(exercises)} exercises, {len(measurements)} measurement types")


if __name__ == "__main__":
    main()
