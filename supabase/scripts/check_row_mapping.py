#!/usr/bin/env python3
"""Diff the app's wire format against the actual Postgres schema.

    python3 supabase/scripts/check_row_mapping.py

Reads the columns out of the schema migration and the `CodingKeys` out of
`Sync/SyncRows.swift`, and reports any disagreement.

## Why this is a script and not a Swift test

The failure it catches is a MISSPELLED COLUMN NAME, and nothing inside the app
can see it. The Swift side compiles perfectly with `case sortOrder =
"sort_ordre"`; the test suite passes; the app runs. It fails only when a row
reaches PostgREST, which either rejects every sync from then on or — worse —
accepts the row and silently never writes that column. A Swift test cannot
check it because the schema is not in the test bundle, so the truth lives here,
next to the migration it reads.

Four columns do not match their Swift property name, all forced by Postgres
reserved words (docs/05-database.md § Naming), and they are exactly where a
typo hides:

    order -> sort_order    cursor -> program_cursor
    group -> group_kind    duration -> duration_seconds

Exit code is non-zero on any mismatch, so this can gate a commit.
"""

from __future__ import annotations

import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
MIGRATION = REPO / "supabase/migrations/20260815120000_schema.sql"
ROWS = REPO / "MCPStrength/MCPStrength/Sync/SyncRows.swift"

# Swift struct -> Postgres table. Stated explicitly rather than derived from the
# name: the mapping is a decision, and a struct renamed without its table is
# precisely the kind of drift this script exists to catch.
STRUCT_TO_TABLE = {
    "SyncExerciseRow": "exercises",
    "SyncTemplateFolderRow": "template_folders",
    "SyncTemplateRow": "templates",
    "SyncTemplateExerciseRow": "template_exercises",
    "SyncTemplateSetRow": "template_sets",
    "SyncProgramDayRow": "program_days",
    "SyncWorkoutRow": "workouts",
    "SyncWorkoutExerciseRow": "workout_exercises",
    "SyncWorkoutSetRow": "workout_sets",
    "SyncMeasurementTypeRow": "measurement_types",
    "SyncMeasurementEntryRow": "measurement_entries",
}

# Server-owned. The trigger sets both on every write regardless of what the
# client sends, so their absence from a row struct is correct, not an omission.
SERVER_OWNED = {"created_at"}

# Tables with no row struct, and the reason. An entry here is a deliberate
# exclusion; anything else missing is a bug.
NO_ROW_STRUCT = {
    "exercise_preferences": "no SwiftData model yet — nothing produces or consumes it",
}


def schema_columns() -> dict[str, set[str]]:
    sql = MIGRATION.read_text()
    tables: dict[str, set[str]] = {}
    for match in re.finditer(r"create table public\.(\w+) \((.*?)\n\);", sql, re.S):
        table, body = match.group(1), match.group(2)
        cols: set[str] = set()
        for line in body.splitlines():
            line = line.strip()
            if not line or line.startswith(("--", "constraint", "primary key")):
                continue
            found = re.match(r"([a-z_]+)\s+", line)
            if found and found.group(1) not in {"check", "constraint"}:
                cols.add(found.group(1))
        tables[table] = cols
    return tables


def coding_keys() -> dict[str, set[str]]:
    swift = ROWS.read_text()
    structs: dict[str, set[str]] = {}
    for match in re.finditer(
        r"struct (\w+): Codable.*?enum CodingKeys: String, CodingKey \{(.*?)\n    \}",
        swift,
        re.S,
    ):
        name, body = match.group(1), match.group(2)
        keys: set[str] = set()
        for line in body.splitlines():
            line = line.strip()
            if not line.startswith("case "):
                continue
            # `case id, name, note`  and  `case userID = "user_id"`
            for part in line[len("case "):].split(","):
                part = part.strip()
                if "=" in part:
                    keys.add(part.split("=", 1)[1].strip().strip('"'))
                elif part:
                    keys.add(part)
        structs[name] = keys
    return structs


def main() -> None:
    tables = schema_columns()
    structs = coding_keys()
    problems: list[str] = []

    for table, reason in NO_ROW_STRUCT.items():
        if table in tables:
            print(f"  skipping {table}: {reason}")

    covered = set(NO_ROW_STRUCT)
    for struct, table in STRUCT_TO_TABLE.items():
        covered.add(table)
        if struct not in structs:
            problems.append(f"{struct}: no CodingKeys found in SyncRows.swift")
            continue
        if table not in tables:
            problems.append(f"{struct}: table `{table}` is not in the migration")
            continue

        keys = structs[struct]
        cols = tables[table] - SERVER_OWNED

        unknown = keys - tables[table]
        missing = cols - keys

        if unknown:
            problems.append(
                f"{struct} -> {table}: key(s) with no such column: {sorted(unknown)}"
            )
        if missing:
            problems.append(
                f"{struct} -> {table}: column(s) never sent: {sorted(missing)}"
            )
        if not unknown and not missing:
            print(f"  ok  {struct:24} -> {table}")

    uncovered = set(tables) - covered
    if uncovered:
        problems.append(f"table(s) with no row struct and no stated reason: {sorted(uncovered)}")

    print()
    if problems:
        print("MISMATCHES:")
        for p in problems:
            print(f"  ✗ {p}")
        sys.exit(1)
    print(f"all {len(STRUCT_TO_TABLE)} row structs match the schema")


if __name__ == "__main__":
    main()
