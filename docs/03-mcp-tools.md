# MCP Tool Surface

The contract between AI and the app. Companion to `01-data-model.md` and `02-architecture.md`,
and the first document in this series written from **evidence rather than design intent** — a
throwaway spike was built, driven by a real LLM client, and the failures recorded.

## What Phase 0 established

`02-architecture.md` set the bet: *"paste a YouTube link to Claude, watch a template appear. If
that doesn't feel as good as it sounds, everything downstream changes."*

It works. A transcript-style push day — messy prose, supersets, rep ranges, "leave one or two in
the tank" — became a saved six-exercise template in one call. Exercise resolution was the part
most likely to break, and it held.

But the fidelity loss was systematic, and that's the finding:

> **Every field the schema could not hold was a prescription field.** Sets and reps survived.
> *How hard*, *how many*, *how much*, and *what to do next week* all died at the boundary.

A template that survives this round-trip is a set-and-rep grid. The grid is the least interesting
part of a program, and it's the part a user could type themselves in ninety seconds.

### What the spike got right (keep these)

| Behavior | Evidence |
|---|---|
| Refuses to guess on ambiguity | `"Squat"` → wrote nothing, returned `Squat (Barbell)`, `Front Squat (Barbell)`, `Bulgarian Split Squat (Dumbbell)` |
| All-or-nothing writes | Any unresolved exercise → nothing written, suggestions returned |
| Fuzzy-match on create | `"Dumbbell Lateral Raise"` → returned existing `Lateral Raise (Dumbbell)`, `created: false` |
| Echoes what it resolved | `matched_to_existing: ["Barbell Bench Press -> Bench Press (Barbell)"]` |

The last two directly satisfy `02`'s stated integrity constraint — *"`create_exercise` should
return an existing close match rather than creating a near-duplicate, and say that it did."*
**Verified working.** Formalize both.

### What broke

| Failure | Detail |
|---|---|
| Silent field discard | `rpe: 8` and a set-level `note` vanished; call still returned success |
| Silent enum coercion | `set_type: "drop_set"` → written as `"normal"`, no error. The real value is `"drop"`; the silence turned a one-character fix into a false conclusion that drop sets were unsupported (see open question 4) |
| Name collision | Creating an existing template name **silently duplicated**; `get_template` returns the first, so the second is permanently unreachable |
| Suggestions are lexical, not semantic | `"Pec Deck"` → **zero** suggestions (answer is `Chest Fly (Machine)`). `"JM Press"` → suggested **`Leg Press`** |

That last one is the dangerous one. The same string matcher is load-bearing in two places with
**opposite requirements**: aggressive word-order matching makes dedup excellent, and makes
suggestions confidently wrong. A triceps movement was mapped to a quad machine. Split them.

---

## The four schema gaps

Reading the spike findings against `01-data-model.md` sorted them into three piles. Two piles are
noise — behavior already specced but not implemented in the throwaway (drop set, failure, `weight?`,
per-set rest, UUIDs), and spike-only bugs. **This pile is the real output: things absent from the
committed data model too.**

Prior art below is from a research swarm (`workout-mcp-tools`, 2026-08-14). Hevy schema claims were
**spot-checked firsthand** against the live spec at `api.hevyapp.com/docs/swagger-ui-init.js`.

### 1. Rep ranges — the single biggest gap

`TemplateSet.reps` is one optional integer. "3 sets of 6–8" is how every program on earth is
written, and it cannot be stored.

**Prior art:** Hevy carries **both**, per set:

```json
"reps":       { "type": "integer", "nullable": true },
"rep_range":  { "type": "object",  "nullable": true,
                "description": "Range of reps for the set, if applicable",
                "properties": { "start": {...}, "end": {...} } }
```

Note the asymmetry: `rep_range` exists on **routine** sets and *not* on workout sets. That's
correct and worth copying — **a plan has a range, a performance has a number.** It maps exactly
onto this project's Template/Workout split, which `01` already refused to collapse.

**Adopted — now in `01` § Prescribed effort.** `repRangeStart?` / `repRangeEnd?` on `TemplateSet`
alongside `reps?`; a set uses one or the other. `WorkoutSet` keeps `reps` only.

### 2. RPE / RIR — absent entirely

Not deferred in `01` — simply not there. "Leave one or two in the tank" is the most important
instruction in a training video and there is nowhere to put it.

**Prior art:** Hevy has `rpe` as `{"type":"number","nullable":true}` with enum
`[6, 7, 7.5, 8, 8.5, 9, 9.5, 10]` — **but only on workout sets, not routine sets.** So Hevy can
record RPE and cannot prescribe it. Boostcamp has "fields for both Rate of Perceived Exertion
(RPE, 5 to 10) and Reps in Reserve (RIR)" on *every* set.

**Adopted — now in `01` § Prescribed effort.** `rpe?` on **both** `TemplateSet` (prescribed) and
`WorkoutSet` (actual), 6–10 in half steps per Hevy's enum. RIR was considered and left out — it is
the same information on a different scale, and one scale is easier to coach against than two. The
prescribed-vs-actual RPE delta is a signal neither reference app can compute.

### 3. To-failure and AMRAP

"3 sets to failure" was written as `12` — false data. But the schema was never the obstacle:
`SetSpec.reps` is `int | None` defaulting to `None`, and `set_type` accepts `failure`. The correct
call — `set_type: "failure"` with `reps` omitted — was available the whole time and went unused,
because the field description reads *"Reps. Omit for cardio/duration exercises."* It names two cases
where omitting is correct and not the third.

> **This is a tool-description failure, not a schema gap** — and the most easily missed kind, because
> nothing errors and nothing is lost at write time. The schema permitted the right call; the
> description simply did not disclose it, so the client invented a number instead.

**Already solved in `01`:** `SetType` includes **Failure**. Hevy's enum is exactly
`["warmup", "normal", "failure", "dropset"]` — **identical four values, independently arrived at.**
Convergent validation that `01`'s enum is right.

**Recommendation:** no schema change. State in the description that `reps` is omitted for `failure`
sets as well as for cardio/duration. Per rule 5 above, the description carries the part of the
contract the schema cannot express — and this is what it costs when it doesn't.

### 4. Nothing above `TemplateFolder`

A folder is a filing concept. "A 4-day upper/lower split" is one object with an ordered rotation
and a progression rule; four templates sharing a folder string encode none of that, and
`list_templates` returns them alphabetized, so even the order is lost.

**Prior art — and this is the interesting one:**

| App | Program entity? |
|---|---|
| **Strong** (this project's reference) | **None.** Unit is the `Workout Template`, "no completion time or date" |
| **Hevy** | **None.** Two levels only: `routine_folder` → `routine`. HevyGPT: *"In Hevy a workout plan is n routines in a folder"* |
| **Boostcamp** | First-class `Program` — ordered `Day 1..N` / `Week 1..N`, `%` of Training Max, structural deload weeks, mesocycles, fork-to-reuse |
| **TrainHeroic** | First-class, date-free Library `Program`; copy-on-assign |

Neither reference logger models a program. Boostcamp does, and also encodes progression:
*"Hit your reps and the app increases the load next session — no spreadsheet required."*

> **Design note.** This is the clearest product opening the research surfaced. A multi-week program
> with a progression rule is (a) absent from both apps this project is modeled on, (b) tedious for a
> human to build by hand, and (c) exactly what an LLM is good at generating. It is also the one gap
> where shipping a `Program` entity changes what the MCP server can *be* — from a template writer to
> something that can actually plan a training block. Deferring it is defensible; deferring it by
> accident is not.

**Resolved — see `01-data-model.md` § Programs.** A program is a *mode* on `TemplateFolder`
(`kind: Folder | Program`) rather than a separate top-level entity, with an ordered `ProgramDay`
list pointing at templates. This keeps programs opt-in and makes promotion an in-place upgrade, so
the build can be deferred by phase without the schema drifting in the meantime. What the MCP server
needs from that decision is small: a folder it can create in program mode, and a day sequence it can
populate.

---

## Tool contract rules

From the MCP specification (2026-07-28) and Anthropic tool-design guidance. These are not style
preferences — the first one is a spec requirement the spike violates.

**1. Validate strictly. Never discard silently.**
The spec states `Servers MUST: Validate all tool inputs`. The spike's silent drop of `rpe` and
silent coercion of `drop_set` → `normal` are spec violations, not merely bad manners. Use
`additionalProperties: false` and explicit `enum` arrays throughout.

**2. Validation failures are Tool Execution Errors, not protocol errors.**
Per SEP-1303, return `isError: true` with the reason in `content` — *"language models can receive
validation error feedback in their context window, allowing them to self-correct."* A rejected
write should teach the model how to fix it. The spike's Pydantic dump already does this well;
keep that behavior, drop the stack-trace framing.

**3. Address records by stable ID, never by name.**
Anthropic guidance: *"Return semantic, stable identifiers (for example, slugs or UUIDs) rather than
opaque internal references."* `02` already mandates client-generated UUIDs on every record and calls
them load-bearing. The duplicate-`Push Day` orphan is purely an artifact of the spike using name as
a primary key. Tools accept a name for *lookup*, return a UUID, and take a UUID for mutation.

**4. Surface ambiguity through the spec's own mechanism.**
The spike's refusal-with-candidates was the right instinct. The spec now has a first-class path:
`InputRequiredResult` on `tools/call`, with an embedded `elicitation/create` carrying an `enum` of
candidates. Use it for the `"Squat"` case rather than an error-shaped response.

**5. Echo every resolution and every ignored input.**
`matched_to_existing` was the spike's best idea. Formalize it in `structuredContent` alongside an
`outputSchema`. The spec defines **no** standard "warnings" channel, so an explicit
`ignored_fields: []` in `structuredContent` is the available convention. **An agent must never have
to read a record back to learn what was written.**

**6. Collision behavior is ours to define — so define it.**
The spec is silent on idempotency, upsert semantics, and duplicate handling; there is no
`idempotencyKey` convention. Decision: **`create_template` errors on an existing name in the same
folder** and returns the existing record's UUID, so the model can choose `update_template`.

---

## The surface

Refines the sketch in `02`. Changes from that sketch are marked.

| Tool | Purpose | Notes |
|---|---|---|
| `list_exercises` | Search the library | Add `category` and `equipment` filters — the spike could not answer "what barbell movements do I have". Also accepts an optional `body_part` hint that **ranks** results (see open question 3) |
| `create_exercise` | Add to library | Fuzzy-match first, return existing on match, always say which. **Verified working in spike** |
| `get_templates` / `get_template` | Read plans | Accept UUID; name accepted only as a lookup that returns candidates when ambiguous |
| `create_template` | Write plans — the transcript path | Errors on name collision (**new**) |
| `update_template` | Revise plans | **Missing from the spike entirely**; "add 3x8 squats to my leg day" has no path today |
| `get_workout_history` | Read history, date-filtered | **Must return notes** — see below |
| `get_exercise_progress` | Per-exercise time series | **Must return notes** — see below |

> ### Notes are a two-way coaching channel, not metadata
>
> This is the requirement most easily lost, because "note" reads like a
> throwaway string field. It is not one here.
>
> **The AI writes them as instructions.** `TemplateExercise.note` and
> `.stickyNote` are how a generated plan says *"elbows tucked"* or *"stop one
> short of failure"*. A sticky note stays pinned under the exercise for the
> whole session; a plain note lives behind the options menu. So
> `create_template` / `update_template` MUST accept both, per exercise — and
> `Workout.note`, `WorkoutExercise.note` and `.stickyNote` carry the same text
> into the performed session.
>
> **The user writes them back as context.** *"Slept badly"*, *"quad still
> sore"*, *"gym was packed, rushed the last two sets"*. Without them the
> reporting tools see a bad session and cannot distinguish it from a downward
> trend — which is the single most likely way this product gives confidently
> wrong coaching advice.
>
> So the READ tools must return them too. A history response that omits notes is
> a response that has thrown away the explanation for its own numbers.
>
> **Phase 0 already lost these once.** The silent-field-discard row in the
> findings table above is a set-level `note` vanishing while the call returned
> success. That was the cheap version of this mistake.
| ~~`log_workout`~~ | Conversational logging | **Cut 2026-08-20.** Drake: it defeats the purpose of the app. Claude plans and reads history; the phone is how a session is recorded. Do not add this tool. |
| `create_program` | Ordered multi-week plan | **New.** Creates a folder with `kind: Program` plus its `ProgramDay` sequence — see `01` § Programs. Day slots reference templates by UUID and **may repeat** (a 3-day A/B split needs `A, B, A`) |
| `delete_template` | Remove a plan | **New.** Soft, UUID-only, destructive-annotated — see below |
| `delete_program` | Remove a block | **New.** Same rules. Deletes the program and its `ProgramDay` rows; the templates it pointed at survive |

### Deletion scope

**Decided: AI can delete templates and programs. Nothing else.**
**Decided 2026-08-20: AI can also not CREATE workouts.** Same table, other direction.
Logging is the app. A `log_workout` tool would let someone train in chat and never open the
phone — which is the product failing, not a missing feature. `02`'s symmetry principle
("anything the app can do, AI can do") does not apply here; this is the exception.

| Entity | AI can delete? | Reasoning |
|---|---|---|
| Template | **Yes** | AI creates these, so AI should be able to clean them up. `02`'s symmetry principle also applies — anything the app can do, AI can do |
| Program | **Yes** | Same. Removing the program leaves its templates intact; only the sequence and position go |
| Exercise | **No** | Referenced by every workout ever logged against it. Deleting a library entry orphans history, and history is the point of the app |
| Workout | **No** | Irreplaceable, and not AI-created either. A template rebuilds in thirty seconds; the fact that you squatted 140kg on a Tuesday in March does not. Correcting a mistyped set is an update, not a delete. There is no `log_workout` |
| Measurement | **No** | Append-only time series |

Three rules govern the two tools that exist:

**1. Soft only.** Delete sets `deleted_at` and lets the tombstone propagate, per `02` § Mechanics.
Recoverable for the retention window; the server sweep is the only thing that hard-deletes.

**2. UUID only — never a name.** The name matcher is not allowed anywhere near a destructive call.
The spike demonstrated it suggesting `Leg Press` for `"JM Press"` — a triceps movement mapped to a
quad machine. A fuzzy match feeding a delete is exactly how a user loses data they never knew was at
risk. Look up first, delete by the ID that came back.

**3. Annotate as destructive.** Set the MCP `destructiveHint` annotation so the client prompts for
confirmation rather than firing silently. Standard mechanism, no custom work.

> **Design note — the create/delete asymmetry on exercises is deliberate.** `create_exercise` exists
> and `delete_exercise` does not, so an AI-created library entry can only be removed in the app. That
> is an accepted cost, bounded by two things: `create_exercise` fuzzy-matches before inserting (so
> junk entries are rare), and any entry that *has* been used is one you would not want deleted anyway.
> If library clutter becomes a real complaint, the answer is an app-side archive/hide that keeps old
> records resolvable — **not** a delete tool.

### Set payload shape

Derived from the spike's failure modes. `sets` was typed as a bare array with no item schema, so
the shape had to be discovered by triggering validation errors — every field below should be
explicit in the JSON Schema.

```jsonc
{
  "exercise_id": "uuid",          // or exercise_name for lookup
  "superset_group": "A",          // worked in spike, was undocumented
  "sets": [{
    "set_type": "normal",         // enum: normal | warmup | drop_set | failure
    "reps": 8,                    // optional when set_type == failure
    "rep_range_start": 6,         // NEW
    "rep_range_end": 8,           // NEW
    "rpe": 8,                     // NEW — enum 6..10, half steps
    "weight": 60.0,               // already in 01 AND in the spike's SetSpec
    "rest_seconds": 150
  }]
}
```

Also worth having: a `sets: 4, reps: 5` shorthand alongside the explicit array. Building the 4-day
split required repeating identical set objects 28 times in one call.

---

## Open questions

1. **Resolved — `Program` ships in pieces, across phases.** It is additive by construction (day slots
   reference templates by UUID; templates already have UUIDs), so the parts can land separately:

   | Part | Phase |
   |---|---|
   | Schema — `kind`, `ProgramDay`, `cursor` | **1**, and this one matters. A nullable column and an empty table cost almost nothing now. Because the UI is deferred past launch, letting the *schema* slip too would mean adding a table to a database that already holds real users' training history |
   | Program UI — the rotation view, "what's next" | **Post-launch update.** Decided: not critical to the app succeeding, and with no plan to train on a half-built app during Phase 1, nothing would be learned by shipping it early |
   | `create_program` / `delete_program` | **3**, with the rest of the real server |
   | Progression rules | Last — see question 2 |

   The binding deadline is **before Phase 4**, not Phase 1. Everything up to launch has no users, so
   schema changes stay cheap; once people have training history, adding a table means a migration
   across devices you do not control.

2. **Resolved — both, deliberately.** Structure exactly one rule: linear progression ("hit all
   prescribed reps → add X next session"), which covers the large majority of intermediate programs.
   Everything else stays a prose note on the Template, exactly as today.

   The app executes the common case, the human handles the exotic case, and no one is ever blocked
   from writing down their program — worst case a rule degrades to advisory text, which is current
   behavior, so there is no regression. The trap this avoids: structured progression looks like a
   field and is actually a small programming language (linear, double progression, %-of-training-max
   waves, RPE autoregulation, rest-pause, AMRAP-driven), where every scheme supported is code and
   every scheme unsupported is a user whose program cannot be represented.

   **The MCP surface should reflect the split:** `create_program` accepts a structured linear rule
   *or* a prose note, and its response must say which one it wrote — so the user always knows whether
   the app is running their progression or merely displaying it.
3. **Resolved — three ranked signals, not two algorithms.** The diagnosis stands (one lexical
   matcher serving two jobs with opposite needs), but the fix is smaller than "add semantic search":

   | Signal | Catches |
   |---|---|
   | Aliases on the exercise | Synonyms sharing no spelling — `"Pec Deck"` → `Chest Fly (Machine)` |
   | `body_part` hint on the query | Right words, wrong movement — `"JM Press"` can no longer reach `Leg Press` |
   | Spelling similarity (existing) | Word-order variants — already works, keep it |

   **The hint ranks, it does not filter** — a hard filter on a slightly-wrong hint would hide the
   right answer. Boost, then fall through.

   The reason this works without the server understanding movements: **the caller already does.**
   Claude knows a JM press is triceps work, so `search_exercises` just accepts `body_part` as an
   optional argument rather than the server inferring it. Aliases need not be unique — a collision
   produces ambiguity, and the ambiguity path already returns candidates and writes nothing. Full
   shape in `01` § Matching a name to an exercise.

   > **UPDATE 2026-08-19: `secondary_body_parts` landed** (`01` § "Secondary body parts"), and it
   > changes what "Deadlift is filed under Back" means. The boost now checks `body_part` OR
   > `secondary_body_parts`, so a `legs` hint genuinely boosts Deadlift rather than merely failing
   > to hide it — the general rule above (hint ranks, never filters) is exactly why that upgrade
   > was safe to make without touching the boost's contract. `list_exercises` and `create_exercise`
   > both now return `secondary_body_parts` on every exercise, so an AI caller can see the same
   > fact the phone app's exercise row shows.
4. **Resolved by reading `spike/server.py`: validation is *inconsistent*, not absent.**
   `create_exercise` validates both enums strictly and returns a usable message
   (`body_part must be one of: ...`) — already the pattern SEP-1303 asks for. But `SetSpec.set_type`
   is a bare `str` whose valid values live only in the field description, and the write path does
   `st = s.set_type if s.set_type in SET_TYPES else "normal"` — an explicit silent fallback.

   The contrast inside one file is the lesson. `reps: int | None` made Pydantic reject `"6-8"` with a
   precise error that was self-corrected in a single turn. `set_type: str` produced silence — and
   because of it a plausible-but-wrong value (`"drop_set"`; the real enum value is `"drop"`) was
   misread as *"drop sets aren't supported."* That is false: `SET_TYPES` is
   `["normal", "warmup", "drop", "failure"]`, all four present. **Silent coercion did not just lose
   data — it produced a confident, wrong conclusion about what the product could do.** That is the
   strongest argument in this document for rule 1 above.

   Fix is one line: type it `Literal["normal", "warmup", "drop", "failure"]` and delete the fallback.
   Strictness has to be a property of the whole surface, not applied per-tool by whoever wrote it.
5. **Mostly moot — the library is first-party.** The concern was mapping an imported source's
   category scheme onto `01`'s eight. Since the exercise list is being authored rather than imported,
   there is nothing to translate, and Hevy's undocumented `ExerciseTemplate.type` vocabulary (no
   inline enum in their public spec, only the example `"weight_reps"`) stops being load-bearing.
   It would only matter again if migrating users in from another app. The live residual is not the
   vocabulary but the **seed format**: name, body part, category, aliases, and a stable permanent
   UUID per row — see `01` § The seeded library.

---

## Appendix — evidence base

- **Spike session, 2026-08-14.** Four scripted requests against the local `workout-spike` MCP
  server: library query, transcript→template, deliberately ambiguous exercise, 4-day split. Plus two
  follow-up experiments (unresolvable exercise names; template name collision).
- **Research swarm `workout-mcp-tools`, 2026-08-14.** Three verified lanes: Hevy data model and
  public API; multi-week programs and progression across Strong / Hevy / Boostcamp / TrainHeroic;
  MCP write-tool conventions. Reports carry verbatim quotes and access dates. A fourth lane
  (rep-range/RPE across training formats) never ran — the free model assigned to it was blocked by
  an OpenRouter account data-policy setting, not a research failure.
- **Firsthand verification.** All Hevy schema fragments quoted here (`rep_range`, the four-value
  set-type enum, `rpe`) were confirmed directly against the live spec, not taken on the worker's word.
