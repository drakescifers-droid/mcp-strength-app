"""SQLite store for the Phase 0 spike.

Throwaway. Mirrors the shape of docs/01-data-model.md closely enough to test the
content -> template flow, and no further. No workouts, no measurements, no sync.
"""

from __future__ import annotations

import os
import sqlite3
import uuid
from datetime import datetime, timezone

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "spike.db")

BODY_PARTS = [
    "Arms", "Back", "Cardio", "Chest", "Core",
    "Full Body", "Legs", "Olympic", "Other", "Shoulders",
]

# Category determines which set fields are meaningful — see docs/01-data-model.md
CATEGORIES = [
    "barbell", "dumbbell", "machine_other", "weighted_bodyweight",
    "assisted_bodyweight", "reps_only", "cardio", "duration",
]

SET_TYPES = ["normal", "warmup", "drop", "failure"]

SCHEMA = """
CREATE TABLE IF NOT EXISTS exercises (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    body_part   TEXT NOT NULL,
    category    TEXT NOT NULL,
    is_custom   INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS template_folders (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    sort_order  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS templates (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    folder_id   TEXT REFERENCES template_folders(id),
    note        TEXT,
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS template_exercises (
    id                   TEXT PRIMARY KEY,
    template_id          TEXT NOT NULL REFERENCES templates(id) ON DELETE CASCADE,
    exercise_id          TEXT NOT NULL REFERENCES exercises(id),
    sort_order           INTEGER NOT NULL,
    superset_group       TEXT,
    note                 TEXT,
    default_rest_seconds INTEGER NOT NULL DEFAULT 90
);

CREATE TABLE IF NOT EXISTS template_sets (
    id                   TEXT PRIMARY KEY,
    template_exercise_id TEXT NOT NULL REFERENCES template_exercises(id) ON DELETE CASCADE,
    sort_order           INTEGER NOT NULL,
    set_type             TEXT NOT NULL DEFAULT 'normal',
    weight               REAL,
    reps                 INTEGER,
    distance             REAL,
    duration             INTEGER,
    rest_seconds         INTEGER
);
"""

# (name, body_part, category) — drawn from the reference screenshots plus common lifts,
# so AI-generated plans have real names to match against.
SEED_EXERCISES = [
    # Chest
    ("Bench Press (Barbell)", "Chest", "barbell"),
    ("Incline Bench Press (Barbell)", "Chest", "barbell"),
    ("Bench Press (Dumbbell)", "Chest", "dumbbell"),
    ("Incline Bench Press (Dumbbell)", "Chest", "dumbbell"),
    ("HS Incline Bench Press", "Chest", "machine_other"),
    ("Chest Dip", "Chest", "weighted_bodyweight"),
    ("Chest Fly (Machine)", "Chest", "machine_other"),
    ("Cable Crossover", "Chest", "machine_other"),
    ("Push Up", "Chest", "reps_only"),
    # Back
    ("Deadlift (Barbell)", "Back", "barbell"),
    ("Bent Over Row (Barbell)", "Back", "barbell"),
    ("Pull Up", "Back", "weighted_bodyweight"),
    ("Chin Up", "Back", "weighted_bodyweight"),
    ("Lat Pulldown (Cable)", "Back", "machine_other"),
    ("HS ISO Lat Pull Down", "Back", "machine_other"),
    ("HS Seated Low Row", "Back", "machine_other"),
    ("Seated Row (Cable)", "Back", "machine_other"),
    ("Massbuilder Back", "Back", "machine_other"),
    ("Y Up DB", "Back", "dumbbell"),
    ("Shrug (Machine)", "Back", "machine_other"),
    ("Kelso Shrug", "Back", "machine_other"),
    ("Shrug (Dumbbell)", "Back", "dumbbell"),
    # Shoulders
    ("Overhead Press (Barbell)", "Shoulders", "barbell"),
    ("Shoulder Press (Dumbbell)", "Shoulders", "dumbbell"),
    ("HS Shoulder Press", "Shoulders", "machine_other"),
    ("Lateral Raise (Dumbbell)", "Shoulders", "dumbbell"),
    ("Lateral Raise (Machine)", "Shoulders", "machine_other"),
    ("Reverse Fly (Machine)", "Shoulders", "machine_other"),
    ("Reverse Fly (Dumbbell)", "Shoulders", "dumbbell"),
    ("Face Pull (Cable)", "Shoulders", "machine_other"),
    # Arms
    ("Bicep Curl (Barbell)", "Arms", "barbell"),
    ("Bicep Curl (Dumbbell)", "Arms", "dumbbell"),
    ("Hammer Curl (Dumbbell)", "Arms", "dumbbell"),
    ("Preacher Curl (Machine)", "Arms", "machine_other"),
    ("Triceps Extension (Cable)", "Arms", "machine_other"),
    ("Triceps Pushdown (Cable)", "Arms", "machine_other"),
    ("Skullcrusher (Barbell)", "Arms", "barbell"),
    ("Triceps Dip", "Arms", "weighted_bodyweight"),
    # Legs
    ("Squat (Barbell)", "Legs", "barbell"),
    ("Front Squat (Barbell)", "Legs", "barbell"),
    ("Romanian Deadlift (Barbell)", "Legs", "barbell"),
    ("Leg Press", "Legs", "machine_other"),
    ("Leg Extension (Machine)", "Legs", "machine_other"),
    ("Seated Leg Curl (Machine)", "Legs", "machine_other"),
    ("Lying Leg Curl (Machine)", "Legs", "machine_other"),
    ("Bulgarian Split Squat (Dumbbell)", "Legs", "dumbbell"),
    ("Walking Lunge (Dumbbell)", "Legs", "dumbbell"),
    ("Standing Calf Raise", "Legs", "machine_other"),
    ("Seated Calf Raise", "Legs", "machine_other"),
    ("Hip Thrust (Barbell)", "Legs", "barbell"),
    # Core
    ("Plank", "Core", "duration"),
    ("Hanging Leg Raise", "Core", "reps_only"),
    ("Cable Crunch", "Core", "machine_other"),
    ("Ab Wheel Rollout", "Core", "reps_only"),
    ("Russian Twist (Dumbbell)", "Core", "dumbbell"),
    # Olympic
    ("Clean and Jerk", "Olympic", "barbell"),
    ("Snatch", "Olympic", "barbell"),
    ("Power Clean", "Olympic", "barbell"),
    # Cardio
    ("Running (Treadmill)", "Cardio", "cardio"),
    ("Cycling (Stationary)", "Cardio", "cardio"),
    ("Rowing (Machine)", "Cardio", "cardio"),
    ("Incline Walk (Treadmill)", "Cardio", "cardio"),
]


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def new_id() -> str:
    return str(uuid.uuid4())


def connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db(reset: bool = False) -> None:
    """Create the schema and seed the exercise library."""
    if reset and os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    conn = connect()
    try:
        conn.executescript(SCHEMA)
        existing = conn.execute("SELECT COUNT(*) AS c FROM exercises").fetchone()["c"]
        if existing == 0:
            conn.executemany(
                "INSERT INTO exercises (id, name, body_part, category, is_custom) "
                "VALUES (?, ?, ?, ?, 0)",
                [(new_id(), n, bp, cat) for (n, bp, cat) in SEED_EXERCISES],
            )
        conn.commit()
    finally:
        conn.close()


if __name__ == "__main__":
    import sys

    reset = "--reset" in sys.argv
    init_db(reset=reset)
    conn = connect()
    n = conn.execute("SELECT COUNT(*) AS c FROM exercises").fetchone()["c"]
    conn.close()
    print(f"{'Reset and initialized' if reset else 'Initialized'} {DB_PATH}")
    print(f"{n} exercises in library")
