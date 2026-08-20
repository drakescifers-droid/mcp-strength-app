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
| `id` | UUID | For seeded exercises this is a **permanent contract** — see below |
| `name` | String | e.g. "HS Shoulder Press" |
| `aliases` | [String] | Common alternate names ("pec deck"). Deliberately **not** unique across exercises — see below |
| `bodyPart` | enum | Arms, Back, Cardio, Chest, Core, Full Body, Legs, Olympic, Other, Shoulders — the PRIMARY, never repeated in `secondaryBodyParts` |
| `secondaryBodyParts` | [enum] | Other body parts this exercise also trains. Deadlift is `bodyPart: .back, secondaryBodyParts: [.legs]` — see "Secondary body parts" below |
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

### The seeded library

The library ships with the app. It is **data, not architecture** — the schema above is what matters,
and the app can be built against thirty exercises with the real list dropped in any time before
launch. A row is: name, body part, secondary body parts, category, and a few aliases.

> **REBUILT 2026-08-20 — 25 exercises became 301** (`20260820120000_library_rebuild.sql`, generated
> from `exercise-seed.json` by `supabase/scripts/generate_library_seed.py`). Drake reviewed a
> 310-name list; the result is below, and the rules it settled are the reusable part:
>
> * **A name that does not say its equipment does not belong in the library**, whenever
>   equipment-specific versions exist. `Lat Pulldown` retired in favour of `Lat Pulldown (Cable)` /
>   `(Machine)`; likewise `Reverse Fly`, `Skullcrusher`, `Triceps Extension`, `Seated Calf Raise`.
>   **The ambiguity is the point:** asked for a bare "Incline Bench Press", the matcher now returns
>   every equipment variant as tied candidates and writes nothing, so an AI has to ask which one —
>   rather than one arbitrary variant winning a coin-flip. Verified against the real matcher, not
>   assumed.
> * **The BODYWEIGHT exception.** `Pull Up`, `Push Up`, `Crunch`, `Plank` keep their bare names —
>   there the unequipped version IS a specific exercise, not a placeholder for one.
> * **Equipment goes in parentheses, last**: `Bench Press (Hammer Strength)`, never `HS Bench
>   Press`. One shape for every variant of every movement.
> * **A retired name becomes an ALIAS on its successor — but only when there is exactly one.**
>   `Barbell Row` → `Bent Over Row (Barbell)`. Where two kept exercises were equally plausible
>   (`Lat Pulldown`, `Leg Curl (Machine)`, `Triceps Pushdown (Cable)`), no alias was written at
>   all: an alias pointing at one of several real options silently picks a winner the user never
>   chose, which is the same failure as keeping the generic row.
> * **Chin Up and Pull Up are DIFFERENT EXERCISES** (Drake, explicitly). `Pull Up` previously
>   carried `chin up` as an alias; that alias is gone and `Chin Up` is its own row with its own
>   assisted / machine / weighted variants.
> * **Retired rows are TOMBSTONED, never deleted** — AGENTS.md rule 1. Verified on the live
>   project: 311 rows, 301 live, 10 tombstoned.
>
> **Safe to rebuild wholesale only because NO workout history existed yet** — checked by dumping
> the project's data first, not assumed. The seeded-ID contract below is unchanged and is why that
> check came first: 15 of the original 25 survived and kept their original UUIDs.

Two properties of that data are load-bearing.

> **Seeded IDs are permanent.** Every workout ever logged points at an exercise by `id`. If the
> library is re-seeded later — new exercises in v1.2, a typo fixed, a better source imported — and
> an existing exercise comes back with a *new* UUID, every user's history for that movement silently
> detaches. So IDs must be **baked into the seed list itself**, never generated at import time.
> Cheap on day one; there is no good fix afterwards.

**Aliases are not unique, and that is the point.** They exist so that names sharing no spelling with
the library entry still resolve — "pec deck" → `Chest Fly (Machine)`. If an alias lands on
four exercises, that is not a bug: it produces *ambiguity*, and ambiguity is already handled
correctly (return candidates, write nothing, let the caller choose). A sloppy alias degrades into
"which one did you mean?" rather than into a wrong answer, so the list can stay small and informal.

> **The 2026-08-20 rebuild sharpened this rather than contradicting it.** No alias in the shipped
> library is currently shared, and the bare `row` alias — once deliberately on three exercises to
> demonstrate ambiguity — was dropped: with ~15 `* Row *` exercises now in the library, aliasing
> three of them was picking arbitrary winners, and spelling similarity already surfaces them all.
> Non-uniqueness remains permitted and is still the correct behaviour when it happens; what changed
> is that it is no longer manufactured on purpose. `01_schema_test.sql` now proves the schema
> ALLOWS a shared alias using rows it creates itself, instead of asserting the shipped data happens
> to contain one — a test of the design that an ordinary library edit can no longer break.

### Secondary body parts

`bodyPart` is one value, and some real movements genuinely train two — Deadlift is filed under
Back but also loads the legs. Asked directly (2026-08-19): should Deadlift be able to show up
under both Back and Legs? Yes, as a real feature rather than a spreadsheet workaround.

**`bodyPart` stays the single PRIMARY value.** `secondaryBodyParts` is what it does not capture —
Deadlift is `bodyPart: .back, secondaryBodyParts: [.legs]`, never `[.back, .legs]` with no
primary. Every reader still has one unambiguous "main" answer plus a set of others: the library
filter pills (`ExercisesScreen`, both Back and Legs show it), the matcher's body-part hint (below),
and the MCP tools' `list_exercises` / `create_exercise` output (`03-mcp-tools.md`) all read
`Exercise.trains(_:)` — the one predicate, so "does Deadlift count as Legs" has exactly one answer
in the app. The Postgres column is `body_part[]`, matching the existing `text[] not null default
'{}'` shape of `aliases` on the same table (`20260819220000_exercise_secondary_body_parts.sql`).

**Deadlift is the worked example, not a hypothetical** — it is genuinely tagged
`secondaryBodyParts: [.legs]` in the shipped seed data, both in the app's bundled JSON and on the
live project. `WarmupSets`' 90 lb reference case and this decision are unrelated, but both are
reminders that a single observed fact ("the reference shows one body part") does not always
generalise into "there is only one".

### Matching a name to an exercise

Resolution uses three signals, cheapest first. No semantic search or embeddings required.

| Signal | Catches | Notes |
|---|---|---|
| **Aliases** | Synonyms with no shared spelling | "pec deck" → `Chest Fly (Machine)` |
| **Body-part hint** | Right words, wrong movement | Caller may pass a `bodyPart` alongside the query |
| **Spelling similarity** | Word-order and phrasing variants | "Dumbbell Lateral Raise" → `Lateral Raise (Dumbbell)` |

**The body-part hint ranks; it never filters.** Boost candidates that `trains(hint)` — primary OR
secondary — but keep the rest below them. Barbell Row is filed under Back only (no secondary), so
a Legs hint must still return it rather than hiding it — the failure mode the hint exists to
prevent. Deadlift used to be this document's example of "wrong hint, must not be hidden"; now that
its secondary carries Legs, a Legs hint genuinely boosts it instead of merely failing to hide it —
see "Secondary body parts" above. The general rule is unchanged: plenty of exercises still have
only one body part, and a hint that turns out wrong for one of those must never make it vanish.

> **Design note — the hint comes from the caller, not the server.** The query string carries no
> metadata; only library entries do. But an AI client already knows a JM press is a triceps movement,
> so the tool simply accepts that knowledge instead of reconstructing it. This is what stops
> `"JM Press"` resolving to `Leg Press`: filed under Legs, it can no longer outrank an arms entry.
> See `03-mcp-tools.md`.

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
`repRangeStart?`, `repRangeEnd?`, `rpe?`, `distance?`, `duration?`, `restSeconds`.

### Prescribed effort: rep ranges and RPE

These three fields are the direct output of Phase 0. The spike could store only a single integer
rep count, and the result was that *every* field it could not hold turned out to be a prescription
field — "3 sets of 6–8, leave one or two in the tank" collapsed into "3 sets of 6." See
`03-mcp-tools.md`.

**`reps?` vs `repRangeStart?` / `repRangeEnd?`** — a set uses one or the other. `reps: 5` is a fixed
target; `repRangeStart: 6, repRangeEnd: 8` is "6 to 8." Kept as two flat optionals rather than a
nested object to match the rest of this table; Hevy models the same idea as a nullable
`rep_range: {start, end}` object sitting beside its own `reps` integer, verified against their live
API spec.

**`rpe?`** — prescribed effort, 6–10 in half steps (`6, 7, 7.5, 8, 8.5, 9, 9.5, 10`), matching
Hevy's enum. This is how "leave one or two in the tank" survives the trip.

> **Design note — the range is template-only; RPE is on both.** A plan has a range, a performance has
> a number, so `WorkoutSet` records `reps` and never a range. But it *does* carry `rpe`, and that
> asymmetry is deliberate: storing prescribed RPE on the template and actual RPE on the workout makes
> the delta computable. Hevy cannot do this — its `rpe` exists on workout sets but not routine sets,
> so it can record effort and never prescribe it. Boostcamp carries both. The gap between what you
> were told to do and what it actually felt like is a coaching signal, and it is free once both
> numbers exist.

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

## Programs (the block)

A folder is a drawer. A program is a drawer that knows what day it is.

**The decision: a program is a *mode* on a folder, not a separate top-level entity.**
`TemplateFolder` gains a `kind` — a folder is either a plain folder (everything above, unchanged)
or a program, which unlocks a different screen. Rationale:

- **Programs stay opt-in.** Someone who wants a logger never encounters one and pays nothing for
  it. No empty "Programs" tab, no second mental model on the main screen.
- **Promotion happens in place.** Build four templates in a folder over two weeks, decide to run it
  as a block, flip the switch. Nothing is re-created.
- **It closes the drift path.** Without a real switch, folder names become the informal program
  layer (`Q3 Week 1`, `Q3 Week 2`) and progression rules live in note prose. Both are migrations
  waiting to happen. See `03-mcp-tools.md`.

**TemplateFolder** — add `kind` (enum: `Folder` | `Program`), `cursor`, `totalCycles?`.
`cursor` is a position in the `ProgramDay` list and is the single source of truth for "what's next."
`totalCycles` null means run indefinitely. Both are meaningless when `kind == Folder`.

**ProgramDay** — `id`, `folderId`, `order`, `templateId`, `label?`

### The day sequence is its own list

`ProgramDay` is an ordered list of *pointers* to templates, not the folder's own template ordering.
This is load-bearing, and it's the one place the obvious simplification fails: **real programs
repeat templates.** A three-day A/B split is the standard counterexample —

```
Week 1:  A    B    A
Week 2:  B    A    B
```

— two templates, three training days, alternating. A folder holds each template once, so
"folder order = day order" cannot express it. Same for any block where Day 1 and Day 4 are the same
session. The templates still live in the folder exactly once; the program holds the sequence.

### A rotation, not a schedule

**Days are never bound to calendar dates or weekdays.** `ProgramDay.label` is advisory — "Day 1",
or "Heavy Squat" if that reads better — and nothing in the model says a slot happens on a Tuesday.

The reason is that binding days imports a pile of calendar logic that has nothing to do with
training. If Day 2 is Tuesday and the user trains Wednesday, are they late? Did they miss Monday or
move it? What if they train twice on Saturday? Every one of those needs a "missed workout" state
machine that mostly exists to make people feel bad. Boostcamp — the one reference app that models
programs properly — prints *"Recommended days: Mon, Tue, Thu, Fri."* **Recommended.** Even there,
weekdays are a hint on the program, never a per-slot assignment.

So the whole runtime is one question: **what is the next workout?** Answer: the slot at `cursor`.

**The list is the cycle, and the cycle repeats.** This covers both shapes with one mechanism:

- A plain upper/lower is 4 slots that loop. `totalCycles` null.
- 5/3/1 is 4 weeks where week 2 genuinely differs from week 1, so the cycle is all 16 slots and
  `totalCycles` is 1.

No separate "repeating" and "finite" concepts. Same list, same cursor, one optional stopping point.

**"Week 3 of 8" is computed, not stored.** Deriving it from `cursor` avoids a second position field
that can drift out of agreement with the first.

**Skip advances the cursor without logging.** That is the only cursor manipulation offered —
there is deliberately no jump-to-arbitrary-slot. A user who wants a specific session today opens
that template and trains it directly; templates remain independently usable, and an ad-hoc workout
does **not** move the cursor. Jump would be a second path to something already possible.

> **UI note.** Skip is the one cursor write a user can fire by accident, and in a finite program
> (`totalCycles: 1`) a mis-tap cannot be walked back without cycling through the entire block.
> An immediate undo on the skip action is worth having — that is a different affordance from
> arbitrary jump, and does not reopen it.

### Progression rules

Deliberately deferred, and the sequencing above works without them. When they land, the shape to
copy is Boostcamp's: percentage of a `Training Max` per set, plus a linear rule ("hit all reps at
the top of the range → increase load next session"). Start with the linear rule only — percentage
waves and RPE autoregulation are where this sprawls into a rules engine. Until then a program is
sequencing plus position, and the progression note stays human-readable prose on the Template.

> **Design note — this is the first entity in the schema with a *now*.** Workouts are the past;
> templates are a plan for whenever. A program has a current position that advances as you train,
> which means it must survive going offline and syncing back. Per `02-architecture.md`'s conflict
> table, programs are written by both the app and AI, so they inherit the Template row: real but
> rare conflicts, record-level last-write-wins on `updatedAt`. Advancing position is a write like
> any other.

> **Design note — demotion must not destroy data.** Flipping a program back to a plain folder makes
> the program data *dormant*, never deleted: templates stay put, `ProgramDay` rows and the week
> position persist unused, and flipping it back on resumes where the user left off. Deleting
> someone's eight-week progression because they tapped a toggle is a thing you get to do once.

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
`templateId` is nullable to support "Start an Empty Workout" / quick workouts.

**Workout naming has two cases, and only one of them is the time-of-day default.**

| Started from | `name` |
|---|---|
| A template | **The template's name**, copied at start and persisted on the Workout |
| Nothing (a quick workout) | A generated time-of-day name — "Afternoon Workout" in the reference |

The template case is the normal one; the generated name is the fallback for the path that has
no template to take a name from. `name` is stored on the Workout rather than read through
`templateId`, so renaming or deleting a template later never rewrites the history of workouts
already performed from it.

**WorkoutSet** — same fields as TemplateSet **except `repRangeStart` / `repRangeEnd`** (a performance
is a number, not a range — see the design note above), plus:
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

**Units decision — DECIDED 2026-08-18: canonical KILOGRAMS, unit as a display preference.**
The alternative considered was storing as-entered with the unit attached, which avoids rounding
values the user typed but makes every consumer convert before it can add anything up — and *"an AI
computing total volume across a year of workouts should never have to unit-convert first"* was the
point of having a canonical form at all. kg over lb because it is what HealthKit speaks, and
HealthKit is the next item in Phase 2.

The cost is accepted rather than avoided: 135 lb is 61.23496995 kg, so a typed value round-trips
through a conversion. Display rounds to `WeightUnits.displayPrecision` — **0.01, which is
deliberately FINE and is not a plate size.** An earlier version of this paragraph said display
rounded to the plate increment; that is the trap rather than the fix, because rounding a typed 138
to the nearest 2.5 lb silently edits what the user entered. Two different jobs:

| Rounding | Increment | Applies to |
|---|---|---|
| **Display precision** — so a typed value survives the round trip | 0.01, both units | Every weight read back out of storage |
| **Plate increment** — so a load the app invents is loadable | 5 lb / 2.5 kg | Only values the app generates, i.e. the warm-up ramp |

**LANDED 2026-08-18, both halves in one change.** Every read and write goes through `WeightUnits`,
and the pounds already in the local store and the live project were converted — `WeightUnitMigration`
on the client (guarded so it cannot run twice) and migration `0009` in Postgres. Neither half is
safe alone: rewiring without converting reads 135 lb as 298, converting without rewiring reads it as
61. There is no correct intermediate commit, which is why `WeightUnits` and `AppSettings` were landed
first — those two are safe alone because nothing called them.

> **The warm-up ramp is the one calculation that leaves canonical storage**, and it does so on
> purpose: it works entirely in the user's display unit and converts each step back on the way into
> the store. A plate increment is a fact about a gym, not a quantity to convert — ramping in
> kilograms and converting at the end tells a pounds lifter to load 49.6 lb.

> **Bar weights are the exception, and they are not a units problem.** `BarType.weight` cannot be
> one canonical number: 45 lb converts to 20.41 kg and a metric lifter wants a **20 kg** bar, while
> 20 kg converts to 44.09 lb and a pounds lifter wants **45**. Both values are real-world constants
> and both are correct; neither is a conversion of the other. So `BarType` carries a weight PER
> UNIT. Recorded here because it reads like rounding and is not.

The global unit lives on `AppSettings` (`MCPStrength/Models/Settings.swift`), which carries this
whole section's field list rather than only the units — see that file for why the fields with no
screen are there anyway, and why `theme` and `previousSetBehavior` are deliberately `String?`
instead of enums.

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
