# Data Model

Extracted from the Strong reference screenshots in this repo. This is the foundation — the
iOS app and the MCP server are both just interfaces onto these entities.

## Guiding principle

The data model is the product. The iOS app is one client; the MCP server is another. Anything
that can only be expressed through the app's UI and not through the schema is invisible to AI,
and anything invisible to AI can't be coached on, reported on, or generated. So the schema
comes first and stays honest.

---

## Core entities

### Exercise

The library entry. Reusable across templates and workouts.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `name` | String | e.g. "HS Shoulder Press" |
| `bodyPart` | enum | Arms, Back, Cardio, Chest, Core, Full Body, Legs, Olympic, Other, Shoulders |
| `category` | enum | **Determines what fields a set has** — see below |
| `isCustom` | Bool | User-created vs. seeded library |
| `weightUnitOverride` | enum? | Per-exercise override (lbs/kg) |
| `barType` | enum? | Olympic Bar (45lb), etc. Drives the plate calculator |
| `focusMetric` | enum | Total Volume, Volume Increase, Total Reps, Weight/Rep |
| `notes` | String? | Persistent exercise-level note |

### ExerciseCategory — the polymorphic key

This is the most important decision in the schema. Category determines which set fields are
meaningful:

| Category | Set fields |
|---|---|
| Barbell | weight + reps |
| Dumbbell | weight + reps |
| Machine / Other | weight + reps |
| Weighted Bodyweight | *added* weight + reps |
| Assisted Bodyweight | *assistance* weight (negative) + reps |
| Reps Only | reps |
| Cardio | distance + duration |
| Duration | duration |

**Recommendation:** store all four columns (`weight`, `reps`, `distance`, `duration`) as
optionals on a single set entity rather than modeling eight subclasses. Validation happens at
the category level. This keeps the MCP tool surface flat and makes AI-generated sets far easier
to validate — a subclassed hierarchy would force the MCP layer to know which concrete type to
construct before it can write anything.

---

## Templates (the plan)

```
TemplateFolder
  └── Template
        └── TemplateExercise   (ordered, may belong to a superset group)
              └── TemplateSet  (ordered)
```

**TemplateFolder** — `id`, `name`, `order`, `isCollapsed`.
Real examples from the reference data: "Q2 2026", "GPT Chest / Shoulders", "Easy Restart",
"Hypertrophy Gemini". Note these are already AI-generated plans, transcribed by hand.

**Template** — `id`, `name`, `folderId?`, `note?`, `order`, `lastPerformedAt?`.

**TemplateExercise** — `id`, `templateId`, `exerciseId`, `order`, `supersetGroupId?`,
`note?`, `stickyNote?`.

**TemplateSet** — `id`, `templateExerciseId`, `order`, `setType`, `weight?`, `reps?`,
`distance?`, `duration?`, `restSeconds`.

### SetType

| Type | Badge | Notes |
|---|---|---|
| Normal | `1`, `2`, `3`… | Numbered independently of warmups |
| Warm up | `W` (orange) | Excluded from working-set numbering and PR calculations |
| Drop set | `D` (purple) | |
| Failure | `F` (red) | |

### Rest timers

Rest is **per-set**, not per-exercise — the reference shows 1:30, 2:00, 0:30, 0:45 within a
single exercise. The "+ Add Set (2:00)" affordance means each exercise carries a *default* rest
that new sets inherit. Model as: `TemplateExercise.defaultRestSeconds` + per-set
`restSeconds` override.

### Supersets

`supersetGroupId` on TemplateExercise (and WorkoutExercise). Exercises sharing a group id are
performed round-robin. Nullable — most exercises aren't in one.

---

## Workouts (the performance)

Structurally near-identical to Template, which is intentional: starting a workout copies the
template's shape, then records what actually happened.

```
Workout
  └── WorkoutExercise  (ordered, superset group)
        └── WorkoutSet (ordered)
```

**Workout** — `id`, `name`, `templateId?`, `startedAt`, `completedAt?`, `durationSeconds`,
`note?`, `totalVolume`, `prCount`.
`templateId` is nullable to support "Start an Empty Workout" / quick workouts (named
"Afternoon Workout" by default in the reference).

**WorkoutSet** — same fields as TemplateSet, plus:
- `isCompleted` — the checkmark. A set can exist unchecked.
- `completedAt` — timestamp, enables true rest-interval analysis

> **Design note:** Do *not* collapse Template and Workout into one entity with a flag. They
> diverge: workouts have completion state and timestamps, templates have neither, and templates
> are edited long after the workouts derived from them are immutable history.

### Derived, not stored

- **Previous** column — looked up from workout history, not stored on the set. Its behavior is
  a user setting (`Previous Set: Any Workout` vs. same-template-only).
- **Focus metric badge** (`+44%`, `1800 lb`) — computed per exercise per session.
- **PRs** — computed. Worth caching on Workout for list performance.

---

## Measurements

**MeasurementType** — seeded set, two groups:
- *Core:* Weight, Body Fat %, Caloric Intake
- *Body part:* Neck, Shoulders, Chest, Left/Right Bicep, Left/Right Forearm, Upper Abs, Waist,
  Lower Abs, Hips, Left/Right Thigh, Left/Right Calf

**MeasurementEntry** — `id`, `typeId`, `value`, `unit`, `recordedAt`, `source` (manual vs.
HealthKit). Time-series; the main screen shows only the latest per type.

Apple Health sync is **bidirectional** (decided — see `02-architecture.md`), which makes
`source` load-bearing rather than informational: entries this app writes to HealthKit must be
tagged so they can be skipped on import, or every write echoes back as a duplicate.

---

## Settings

Global: rest timer defaults, warm-up calculator config, `previousSetBehavior`, language,
measurement weight unit, weight unit, distance unit, size unit, week start day, theme.

**Units decision (needs your call):** store canonically (kg, meters, seconds) and convert at
the display layer, or store as-entered with the unit attached? Canonical is cleaner for
aggregation and for MCP consumers doing math. Storing as-entered avoids float drift on values
the user typed. Recommendation: **canonical storage, unit as a display preference** — an AI
computing total volume across a year of workouts should never have to unit-convert first.

---

## Open questions

1. **Exercise library ownership** — ship a seeded library, or let it build from user entries?
   The reference seeds a large library with illustrations. Seeding matters for MCP: AI needs
   stable exercise names to write against, or every generated plan invents new exercises.
2. **Template/workout drift** — if a template is edited after workouts derive from it, past
   workouts keep their own copies. Confirmed by the model above, but worth stating in the app's
   behavior spec.
3. **Warm-up calculator** — is it a stored config that generates sets, or a one-shot helper?
   Affects whether it needs schema representation.
4. **Sync/backend** — the decision that gates the MCP server. See `02-architecture.md`.
