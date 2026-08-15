# Phase 0 Spike — ⛔️ FROZEN, ANSWERED, DO NOT BUILD ON THIS

> **Status: closed 2026-08-14.** This spike did its job and is kept only as a reference for what
> the MCP tool surface *felt like* to drive. **Do not extend it, fix it, or use it as a starting
> point for anything.**
>
> - The findings live in **`../docs/03-mcp-tools.md`** — that is the real output, not this code.
> - Its SQLite schema is **not** the Phase 1 schema. Phase 1 is SwiftData, per `../docs/01-data-model.md`.
> - Known-wrong on purpose, all documented in `03`: unknown fields are silently discarded,
>   `set_type` silently coerces to `"normal"`, duplicate template names create unreachable records,
>   and there is no update or delete path.
> - The local `spike.db` was deleted; it held throwaway test data from the Phase 0 session
>   (including two templates named "Push Day", one of them unreachable). Rebuild per Setup below
>   if you ever need to poke at it again.

**Throwaway.** Existed to answer one question before we build anything real:

> Does "here's a workout — put it in my app" actually feel like magic?

If yes, the architecture in `../docs/02-architecture.md` is worth the effort. If it feels
clunky, we learned that in an afternoon instead of after building a sync engine.

Not here, deliberately: auth, sync, multi-user, workouts, measurements, iOS. Just a local
SQLite file and an MCP server over stdio.

## Setup

Already done, but to rebuild from scratch:

```bash
python3 -m venv .venv && .venv/bin/pip install mcp && .venv/bin/python db.py --reset
```

`db.py --reset` wipes `spike.db` and reseeds 62 exercises. Safe to run any time — it's a spike.

## Connect it to Claude Desktop

Add this to `~/Library/Application Support/Claude/claude_desktop_config.json`, then fully quit
and reopen Claude Desktop:

```json
{
  "mcpServers": {
    "workout-spike": {
      "command": "/Users/drakescifers/MCP Workout App/spike/.venv/bin/python",
      "args": ["/Users/drakescifers/MCP Workout App/spike/server.py"]
    }
  }
}
```

Merge it into the existing file rather than replacing — the config already has other top-level
keys.

## What to try

The point is to stress the flow, not to admire it. Worth trying in roughly this order:

1. **Baseline** — "What exercises do I have for shoulders?"
2. **The actual bet** — paste a workout from a YouTube transcript, an article, or a screenshot
   and say "add this to my app as a template called Push Day."
3. **Ambiguity** — ask for something with a vague exercise name ("3x8 squats"). It should ask
   which squat rather than silently picking one.
4. **A real program** — "build me a 4-day upper/lower split in a folder called Q3" and see
   whether the result is something you'd actually train with.
5. **Read-back** — "what's in my Push Day template?" Confirms the round trip.

## Tools

| Tool | Notes |
|---|---|
| `search_exercises` | Library search. Fuzzy, filterable by body part. |
| `create_exercise` | Refuses near-duplicates; returns the existing match instead. |
| `create_template` | All-or-nothing. Unresolvable names write nothing and return suggestions. |
| `list_templates` | Everything saved, grouped by folder. |
| `get_template` | One template in full, every set. |

## The part that matters: name resolution

The library is the integrity constraint. If "Lateral Raise (Machine)", "Machine Lateral Raise",
and "Lat Raise" become three rows, progress tracking silently breaks — and progress tracking is
the entire point of the app. So `create_template` resolves every name before writing anything:

| Input | Behavior |
|---|---|
| `"barbell bench press"` | → **matches** `Bench Press (Barbell)` (word order ignored) |
| `"Bulgarian Split Squat"` | → **matches** the Dumbbell variant (only one exists — unambiguous) |
| `"Squat"` | → **asks**: Barbell? Front? Bulgarian Split? (genuinely ambiguous) |
| `"Kettlebell Turkish Getup"` | → **no match**, prompts an explicit `create_exercise` call |

Two rules do the work: token-order-insensitive similarity, and a *unique subset* rule — if a
short name's words appear in exactly one library entry it's unambiguous, and if they appear in
several it must ask. `create_template` also reports every rename it applied
(`"barbell bench press -> Bench Press (Barbell)"`), because silent renaming is how libraries rot.

**Known gap:** acronyms don't resolve — `"RDL"` finds nothing rather than `Romanian Deadlift
(Barbell)`. Real version wants an alias table. Left unfixed on purpose; it's a spike.

## What we're evaluating

Not "did it work" — it works. The questions are:

- How often does it need to ask about an ambiguous name before it gets annoying?
- Does an AI-built program come out *good*, or just structurally valid?
- Is the round trip fast enough to feel live?
- What did you want to say that the tools couldn't express?

That last one is the real output of this phase — it's what shapes `03-mcp-tools.md`.
