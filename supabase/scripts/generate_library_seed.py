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

# **BUMP THIS FILENAME EVERY TIME THE LIBRARY DATA CHANGES.**
#
# A migration that has already been applied cannot be edited into effect:
# `supabase db push` tracks versions, so regenerating over an applied file
# changes what a FRESH database gets and does nothing at all to the live
# project — while leaving the repo looking as though it did. Every library
# change therefore gets its OWN migration and the previous ones stay frozen as
# history. The statements are idempotent upserts keyed on id, so a fresh
# database replaying all of them in order lands in exactly the same place the
# live project did.
#
# Regenerating without bumping is safe but USELESS, which is the dangerous
# combination — it produces a clean diff that will never reach the server.
# `supabase migration list` is the check: the newest local version must also be
# the newest remote one.
OUT = REPO / "supabase" / "migrations" / "20260820130000_lat_prayer_grips.sql"

# Ids retired by the 2026-08-20 rebuild: exercises whose NAME did not survive
# Drake's review, almost all of them generic names ("Lat Pulldown", "Dip") that
# the review replaced with equipment-specific ones. TOMBSTONED, never deleted —
# a hard delete cannot reach a device that was offline when it happened, so the
# row would come back on the next pull (AGENTS.md rule 1). Their common names
# live on as aliases on the successor exercise, except where two or more kept
# exercises were equally plausible successors and an alias would have silently
# picked a winner.
RETIRED_EXERCISE_IDS = [
    ("5b3e00a2-b1bf-470e-9782-408984ab130e", "Barbell Row -> Bent Over Row (Barbell)"),
    ("94bdcb4a-9469-448d-af17-b62e68f1abb5", "Dumbbell Row -> Bent Over Row (Dumbbell)"),
    ("07fc8389-e0d3-45d3-af79-4dd97d777bd2", "Lat Pulldown -> Cable / Machine, no alias (two successors)"),
    ("a7d8825a-ed41-49c8-9c49-406db9ea9a36", "Seated Cable Row -> Seated Row (Cable)"),
    ("32b233a3-6633-4d88-94b7-15869ad6fc82", "Leg Extension -> Leg Extension (Machine)"),
    ("7c4b861c-40ef-4b09-a6f8-25335ad18495", "Leg Curl (Machine) -> Lying / Seated, no alias (two successors)"),
    ("0f13df5a-edf6-4935-a7dc-a3f08ac6298c", "Triceps Pushdown (Cable) -> Straight Bar / Rope, no alias (two successors)"),
    ("f32d2257-6616-4b8e-9dbc-2765293a6e50", "Dip -> Triceps Dip"),
    ("23ba51e7-0b8d-44ba-9a95-f55a6389af0c", "Assisted Pull Up -> Pull Up (Assisted)"),
    ("e3e0ddfb-5f39-4a21-ad26-c8f146c5f355", "Assisted Dip -> Triceps Dip (Assisted)"),
]

BODY_PARTS = {
    "arms", "back", "cardio", "chest", "core",
    "fullBody", "legs", "olympic", "other", "shoulders",
}
CATEGORIES = {
    "barbell", "dumbbell", "machineOther", "weightedBodyweight",
    "assistedBodyweight", "repsOnly", "cardio", "duration", "hammerStrength",
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
    add("-- The seeded library, in full (global rows, user_id IS NULL)")
    add("--")
    add("-- THE WHOLE LIBRARY, not a delta — every row, upserted by id. One of these is")
    add("-- emitted per library change (see OUT in the generator); earlier ones stay")
    add("-- frozen as history because an applied migration cannot be edited into effect.")
    add("-- Replaying them all in order lands where the live project is, since every")
    add("-- statement is an idempotent upsert.")
    add("--")
    add("-- The 2026-08-20 rebuild (20260820120000) is the one that took the library from")
    add("-- 25 exercises to 301: generic names dropped in favour of equipment-specific")
    add("-- ones (\"Lat Pulldown\" -> Cable / Machine), duplicates merged, Hammer Strength")
    add("-- named like every other variant. Safe wholesale only because NO workout")
    add("-- history existed — verified by dumping the project's data, not assumed.")
    add("-- docs/01-data-model.md § The seeded library carries the naming rules.")
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
    add("-- secondary_body_parts, category, aliases), matching ExerciseSeedImporter on")
    add("-- the device. Per-user settings live in exercise_preferences and are never")
    add("-- touched by a re-seed.")
    add("-- ============================================================================")
    add("")
    add(f"-- {len(exercises)} exercises")
    add("insert into public.exercises")
    add("  (id, user_id, name, aliases, body_part, secondary_body_parts, category, is_custom)")
    add("values")

    rows = []
    for row in exercises:
        secondary = row.get("secondaryBodyParts") or []
        secondary_sql = (
            "'{}'::public.body_part[]"
            if not secondary
            else "array[" + ", ".join(quote(v) for v in secondary) + "]::public.body_part[]"
        )
        rows.append(
            "  ({id}, null, {name}, {aliases}, {body}::public.body_part, {sec}, "
            "{cat}::public.exercise_category, false)".format(
                id=uuid_literal(row["id"]),
                name=quote(row["name"]),
                aliases=array_literal(row.get("aliases") or []),
                body=quote(row["bodyPart"]),
                sec=secondary_sql,
                cat=quote(row["category"]),
            )
        )
    add(",\n".join(rows))
    add("on conflict (id) do update set")
    add("  name                 = excluded.name,")
    add("  body_part            = excluded.body_part,")
    add("  secondary_body_parts = excluded.secondary_body_parts,")
    add("  category             = excluded.category,")
    add("  aliases              = excluded.aliases,")
    # Un-tombstone on the upsert path: an id that comes BACK into the library
    # must return, not stay invisible because a previous rebuild retired it.
    add("  deleted_at           = null;")
    add("")
    add("")
    add(f"-- {len(RETIRED_EXERCISE_IDS)} retired exercises — TOMBSTONED, not deleted")
    add("--")
    add("-- A hard delete cannot reach a device that was offline when it happened, so")
    add("-- the row returns on that device's next pull. Setting deleted_at travels like")
    add("-- any other edit and every @Query in the app already filters it out.")
    add("-- AGENTS.md rule 1.")
    add("--")
    add("-- `updated_at` is bumped so last-write-wins actually prefers the tombstone")
    add("-- over whatever timestamp the row is carrying locally.")
    for eid, why in RETIRED_EXERCISE_IDS:
        add(f"-- {why}")
    add("update public.exercises")
    add("set deleted_at = now(), updated_at = now()")
    add("where user_id is null")
    add("  and deleted_at is null")
    add("  and id in (")
    add(",\n".join(f"    {uuid_literal(eid)}" for eid, _ in RETIRED_EXERCISE_IDS))
    add("  );")
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
