"""Phase 0 spike: MCP server over the local SQLite store.

Purpose is narrow — prove that "here's a workout, put it in my app" feels good.
No auth, no sync, no multi-user. Everything here is throwaway.

Run:  .venv/bin/python server.py
"""

from __future__ import annotations

import re
import sqlite3
from difflib import SequenceMatcher
from typing import Any

from mcp.server.mcpserver import MCPServer
from pydantic import BaseModel, Field

from db import BODY_PARTS, CATEGORIES, SET_TYPES, connect, init_db, new_id, now_iso

# Above this, we treat two names as the same exercise and reuse the existing row.
AUTO_MATCH = 0.87
# Between this and AUTO_MATCH, we surface the candidates rather than guessing.
SUGGEST = 0.60

mcp = MCPServer(
    name="workout-spike",
    instructions=(
        "Local workout template store (Phase 0 spike). "
        "Always call search_exercises before inventing an exercise name — the library "
        "is the source of truth and duplicate names silently break progress tracking."
    ),
)


# ---------------------------------------------------------------- name matching


def _stem(token: str) -> str:
    """Crude plural stripping so 'squats' and 'squat' are the same token."""
    if len(token) > 3 and token.endswith("s") and not token.endswith("ss"):
        return token[:-1]
    return token


def _tokens(name: str) -> list[str]:
    cleaned = re.sub(r"\s+", " ", re.sub(r"[^\w\s]", " ", name.lower())).strip()
    return [_stem(t) for t in cleaned.split() if t]


def _normalize(name: str) -> str:
    return " ".join(_tokens(name))


def _token_sorted(name: str) -> str:
    return " ".join(sorted(_tokens(name)))


def _similarity(a: str, b: str) -> float:
    """Best of direct and token-order-insensitive comparison.

    The token-sorted pass is what makes "Machine Lateral Raise" match
    "Lateral Raise (Machine)" — word order varies constantly in generated plans.
    """
    direct = SequenceMatcher(None, _normalize(a), _normalize(b)).ratio()
    tokens = SequenceMatcher(None, _token_sorted(a), _token_sorted(b)).ratio()
    return max(direct, tokens)


def _is_subset(query: str, candidate: str) -> bool:
    """Is every word of the query present in the candidate name?

    Catches the common shorthand case: plain 'Squat' against 'Squat (Barbell)'.
    Raw similarity scores these poorly because the length difference dominates.
    """
    q, c = set(_tokens(query)), set(_tokens(candidate))
    return bool(q) and q.issubset(c)


def _rank_matches(conn: sqlite3.Connection, name: str) -> list[tuple[float, sqlite3.Row]]:
    rows = conn.execute("SELECT * FROM exercises").fetchall()
    scored = [(_similarity(name, r["name"]), r) for r in rows]
    scored.sort(key=lambda t: t[0], reverse=True)
    return scored


def _resolve_exercise(conn: sqlite3.Connection, name: str) -> tuple[sqlite3.Row | None, list[str]]:
    """Return (matched_row_or_None, suggestions)."""
    ranked = _rank_matches(conn, name)
    if not ranked:
        return None, []

    top_score, top_row = ranked[0]
    if top_score >= AUTO_MATCH:
        return top_row, []

    # Shorthand rule: if the query's words appear in exactly one library entry,
    # that entry is unambiguous ('Bulgarian Split Squat' -> the only variant).
    # If several match, the shorthand is genuinely ambiguous ('Squat' -> barbell?
    # front? split?) and we must ask rather than guess.
    subset = [r for _, r in ranked if _is_subset(name, r["name"])]
    if len(subset) == 1:
        return subset[0], []
    if len(subset) > 1:
        return None, [r["name"] for r in subset[:5]]

    return None, [r["name"] for s, r in ranked[:5] if s >= SUGGEST]


# ------------------------------------------------------------------- tool input


class SetSpec(BaseModel):
    reps: int | None = Field(None, description="Reps. Omit for cardio/duration exercises.")
    weight: float | None = Field(None, description="Weight in lbs. Omit for bodyweight/reps-only.")
    set_type: str = Field("normal", description="One of: normal, warmup, drop, failure.")
    rest_seconds: int | None = Field(None, description="Rest after this set. Defaults to 90.")
    duration: int | None = Field(None, description="Seconds. For duration/cardio exercises.")
    distance: float | None = Field(None, description="Miles. For cardio exercises.")


class ExerciseSpec(BaseModel):
    exercise_name: str = Field(
        ..., description="Must match an exercise in the library. Call search_exercises first."
    )
    sets: list[SetSpec] = Field(..., description="Ordered sets, warmups first.")
    note: str | None = None
    superset_group: str | None = Field(
        None, description="Exercises sharing a label are performed as a superset."
    )


# ------------------------------------------------------------------------ tools


@mcp.tool(description="Search the exercise library. Call this before creating any template.")
def search_exercises(
    query: str | None = None,
    body_part: str | None = None,
    limit: int = 40,
) -> dict[str, Any]:
    conn = connect()
    try:
        if query:
            ranked = _rank_matches(conn, query)
            rows = [r for s, r in ranked if s >= SUGGEST]
            if not rows:  # fall back to substring so bare words still find things
                rows = [r for s, r in ranked if query.lower() in r["name"].lower()]
        else:
            rows = conn.execute("SELECT * FROM exercises ORDER BY name").fetchall()

        if body_part:
            rows = [r for r in rows if r["body_part"].lower() == body_part.lower()]

        return {
            "count": len(rows[:limit]),
            "exercises": [
                {"name": r["name"], "body_part": r["body_part"], "category": r["category"]}
                for r in rows[:limit]
            ],
        }
    finally:
        conn.close()


@mcp.tool(
    description=(
        "Add an exercise to the library. Fuzzy-matches existing entries first and returns "
        "the existing one rather than creating a near-duplicate."
    )
)
def create_exercise(name: str, body_part: str, category: str) -> dict[str, Any]:
    if body_part not in BODY_PARTS:
        return {"error": f"body_part must be one of: {', '.join(BODY_PARTS)}"}
    if category not in CATEGORIES:
        return {"error": f"category must be one of: {', '.join(CATEGORIES)}"}

    conn = connect()
    try:
        match, suggestions = _resolve_exercise(conn, name)
        if match:
            return {
                "created": False,
                "reason": "An equivalent exercise already exists — reusing it.",
                "exercise": {
                    "name": match["name"],
                    "body_part": match["body_part"],
                    "category": match["category"],
                },
            }
        if suggestions:
            return {
                "created": False,
                "reason": "Close matches exist. Reuse one, or call again with a clearly distinct name.",
                "suggestions": suggestions,
            }

        conn.execute(
            "INSERT INTO exercises (id, name, body_part, category, is_custom) VALUES (?, ?, ?, ?, 1)",
            (new_id(), name, body_part, category),
        )
        conn.commit()
        return {"created": True, "exercise": {"name": name, "body_part": body_part, "category": category}}
    finally:
        conn.close()


@mcp.tool(
    description=(
        "Create a workout template. Every exercise_name must resolve to the library; "
        "if any does not, nothing is written and suggestions are returned."
    )
)
def create_template(
    name: str,
    exercises: list[ExerciseSpec],
    folder: str | None = None,
    note: str | None = None,
) -> dict[str, Any]:
    if not exercises:
        return {"error": "A template needs at least one exercise."}

    conn = connect()
    try:
        # Resolve every name up front — a partially-created template is worse than none.
        resolved: list[tuple[ExerciseSpec, sqlite3.Row]] = []
        unresolved: list[dict[str, Any]] = []
        for spec in exercises:
            match, suggestions = _resolve_exercise(conn, spec.exercise_name)
            if match:
                resolved.append((spec, match))
            else:
                unresolved.append({"requested": spec.exercise_name, "suggestions": suggestions})

        if unresolved:
            return {
                "created": False,
                "error": "Some exercises are not in the library. Nothing was written.",
                "unresolved": unresolved,
                "hint": "Use a suggested name, or call create_exercise for genuinely new movements.",
            }

        folder_id = None
        if folder:
            row = conn.execute(
                "SELECT id FROM template_folders WHERE name = ?", (folder,)
            ).fetchone()
            if row:
                folder_id = row["id"]
            else:
                folder_id = new_id()
                conn.execute(
                    "INSERT INTO template_folders (id, name, sort_order) VALUES (?, ?, 0)",
                    (folder_id, folder),
                )

        ts = now_iso()
        template_id = new_id()
        conn.execute(
            "INSERT INTO templates (id, name, folder_id, note, created_at, updated_at) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (template_id, name, folder_id, note, ts, ts),
        )

        renamed: list[str] = []
        for idx, (spec, ex_row) in enumerate(resolved):
            if _normalize(spec.exercise_name) != _normalize(ex_row["name"]):
                renamed.append(f"{spec.exercise_name} -> {ex_row['name']}")

            te_id = new_id()
            default_rest = next((s.rest_seconds for s in spec.sets if s.rest_seconds), 90)
            conn.execute(
                "INSERT INTO template_exercises "
                "(id, template_id, exercise_id, sort_order, superset_group, note, default_rest_seconds) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (te_id, template_id, ex_row["id"], idx, spec.superset_group, spec.note, default_rest),
            )
            for s_idx, s in enumerate(spec.sets):
                st = s.set_type if s.set_type in SET_TYPES else "normal"
                conn.execute(
                    "INSERT INTO template_sets "
                    "(id, template_exercise_id, sort_order, set_type, weight, reps, distance, duration, rest_seconds) "
                    "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (new_id(), te_id, s_idx, st, s.weight, s.reps, s.distance, s.duration, s.rest_seconds),
                )

        conn.commit()
        result: dict[str, Any] = {
            "created": True,
            "template": name,
            "folder": folder,
            "exercise_count": len(resolved),
            "set_count": sum(len(s.sets) for s, _ in resolved),
        }
        if renamed:
            # Surfacing this is the point — silent renaming is how libraries rot.
            result["matched_to_existing"] = renamed
        return result
    finally:
        conn.close()


@mcp.tool(description="List all saved templates, grouped by folder.")
def list_templates() -> dict[str, Any]:
    conn = connect()
    try:
        rows = conn.execute(
            "SELECT t.id, t.name, t.note, f.name AS folder, "
            "  (SELECT COUNT(*) FROM template_exercises te WHERE te.template_id = t.id) AS exercises "
            "FROM templates t LEFT JOIN template_folders f ON f.id = t.folder_id "
            "ORDER BY f.name NULLS LAST, t.name"
        ).fetchall()
        return {
            "count": len(rows),
            "templates": [
                {
                    "name": r["name"],
                    "folder": r["folder"],
                    "exercises": r["exercises"],
                    "note": r["note"],
                }
                for r in rows
            ],
        }
    finally:
        conn.close()


@mcp.tool(description="Read one template in full, including every set.")
def get_template(name: str) -> dict[str, Any]:
    conn = connect()
    try:
        t = conn.execute(
            "SELECT t.*, f.name AS folder FROM templates t "
            "LEFT JOIN template_folders f ON f.id = t.folder_id "
            "WHERE lower(t.name) = lower(?)",
            (name,),
        ).fetchone()
        if not t:
            available = [r["name"] for r in conn.execute("SELECT name FROM templates").fetchall()]
            return {"error": f"No template named '{name}'.", "available": available}

        out_exercises = []
        te_rows = conn.execute(
            "SELECT te.*, e.name AS exercise_name, e.category "
            "FROM template_exercises te JOIN exercises e ON e.id = te.exercise_id "
            "WHERE te.template_id = ? ORDER BY te.sort_order",
            (t["id"],),
        ).fetchall()

        for te in te_rows:
            sets = conn.execute(
                "SELECT * FROM template_sets WHERE template_exercise_id = ? ORDER BY sort_order",
                (te["id"],),
            ).fetchall()
            out_exercises.append(
                {
                    "exercise": te["exercise_name"],
                    "category": te["category"],
                    "superset_group": te["superset_group"],
                    "note": te["note"],
                    "sets": [
                        {
                            k: s[k]
                            for k in ("set_type", "weight", "reps", "distance", "duration", "rest_seconds")
                            if s[k] is not None
                        }
                        for s in sets
                    ],
                }
            )

        return {
            "name": t["name"],
            "folder": t["folder"],
            "note": t["note"],
            "exercises": out_exercises,
        }
    finally:
        conn.close()


if __name__ == "__main__":
    init_db()
    mcp.run(transport="stdio")
