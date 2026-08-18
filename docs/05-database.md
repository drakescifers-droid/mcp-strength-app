# Database

The Postgres schema, and why it differs from the SwiftData model where it does.

`01-data-model.md` says what the entities *are* and does not change here. `02-architecture.md`
decided Supabase, RLS, client UUIDs, record-level last-write-wins and 90-day tombstones, and those
decisions are inputs to this file, not restated in it. **This file only carries what translating
that model into Postgres forced us to decide.**

| | |
|---|---|
| Schema, enums, tables, indexes | `supabase/migrations/20260815120000_schema.sql` |
| Sync trigger, tombstone purge | `supabase/migrations/20260815120100_sync.sql` |
| RLS policies and grants | `supabase/migrations/20260815120200_rls.sql` |
| The seeded library, generated | `supabase/migrations/20260815120300_library_seed.sql` |
| Tests | `supabase/tests/`, run with `./supabase/tests/run.sh` |

Twelve tables, mirroring eleven `@Model` types plus one split (below). The SQL files carry the
reasoning at the point of edit; this file carries the reasoning that spans files.

---

## Naming

**Enum values are the Swift raw values, character for character** — `fullBody`, `machineOther`,
`dropSet`, `healthKit`. Not snake_case. Column *names* are snake_case because that is Postgres, but
enum values are **data that crosses the wire** to the app and, in Phase 3, to the MCP server. Two
spellings of the same value means a mapping layer, and a mapping layer is a place for a value to
get silently rewritten — which is the exact failure Phase 0 produced.

Four columns are renamed, all forced by Postgres reserved words:

| Swift | Postgres | Why |
|---|---|---|
| `order` | `sort_order` | `ORDER` is reserved |
| `cursor` | `program_cursor` | `CURSOR` is reserved |
| `group` | `group_kind` | `GROUP` is reserved |
| `duration` | `duration_seconds` | Not reserved; renamed for consistency with `restSeconds` |

That is the complete list. Everything else is a mechanical camelCase → snake_case of the Swift
property name.

---

## Ownership: `user_id IS NULL` means the shared library

Every table has a `user_id`. On ten of them it is `NOT NULL` and means exactly what it looks like.
On `exercises` and `measurement_types` it is **nullable, and null means a seeded row shared by
every user**.

The alternative was giving each user a private copy of the seeded library. It was rejected because
seeded UUIDs are baked into the seed file and identical for everyone (`01-data-model.md` § "The
seeded library"), so private copies would mean the same `id` appearing once per user — `id` stops
being unique on its own, and a composite `(user_id, id)` key propagates into every foreign key in
the schema. A shared row keeps `id` a real primary key and keeps the permanent-id contract exactly
as the seed file states it.

Seeded rows are written by migration under the service role, which bypasses RLS. **No client policy
admits a null `user_id`**, so no user can write to the shared library or edit a row out from under
everyone else. That is asserted in `02_rls_test.sql`, not merely intended.

---

## The one real divergence: `exercise_preferences`

SwiftData's `Exercise` carries ten fields. Postgres splits them across two tables:

- **`exercises`** — `name`, `aliases`, `body_part`, `category`, `is_custom`. Library-defined.
- **`exercise_preferences`** — `weight_unit_override`, `bar_type`, `focus_metric`, `notes`,
  keyed `(user_id, exercise_id)`. Per-user.

**This line already existed; it just wasn't a table boundary yet.** `ExerciseSeedImporter` refreshes
only `name`/`bodyPart`/`category`/`aliases` on re-seed and explicitly preserves the other four,
documenting them as "user preferences, not library properties." On device that distinction is a
comment. On a shared row it has to be a table, because one row cannot hold four different users'
answers.

Nothing writes `exercise_preferences` yet — the app has no UI for editing those fields. It exists
now for the reason the Program schema shipped in Phase 1: additive-by-construction only helps if
the columns exist before there are users.

---

## Two timestamps, and why neither can do the other's job

Every synced row carries both. Collapsing them loses data, quietly.

**`updated_at` — the client's wall clock. The last-write-wins input.**
It must be the client's. An edit made offline has no server time, and resolving conflicts by
arrival time would mean *whoever reconnected last* wins rather than *whoever edited last*.

**`server_updated_at` — the server's clock. The pull cursor, and nothing else.**
Set by trigger on every write, ignoring whatever the client sent.

The failure that forces the split: a device with a slow clock writes a row stamped in the past. Any
device whose pull cursor has already moved past that point **never sees that row again** — no error,
no retry, no tombstone. It is simply absent. A server-controlled cursor cannot be moved backwards by
a client, so it cannot skip a row.

The trigger also **clamps a far-future `updated_at`** to now, with five minutes of slack for
ordinary drift. Without it, one device with a badly-set clock wins every conflict on the account
forever, and each win silently discards the other device's edit. The clamp is deliberately
one-sided: a slow clock only loses its own conflicts, which is recoverable; a fast clock poisons
everyone's.

> **Caveat to carry into the sync engine.** `now()` is transaction-start time, so two concurrent
> transactions can commit out of commit-timestamp order, and a pull of
> `server_updated_at > cursor` can in principle miss a row committed late by a transaction that
> started early. At one user with two or three devices this is close to unreachable, and the fix is
> cheap: **pull from `cursor - 5 seconds` and rely on idempotent upserts**, rather than build a
> commit-order sequence. Write it into the client from the start; retrofitting an overlap window
> after a row goes missing means never knowing which row it was.

---

## Deletes are soft, and tombstones expire

`deleted_at` is the tombstone. `purge_tombstones()` hard-deletes past 90 days; it is not scheduled
in a migration because enabling `pg_cron` is a project-level action (the `cron.schedule` call is
commented at the bottom of the sync migration).

The delete rules are where training history lives or dies, and they mirror SwiftData's:

| Foreign key | Rule | Consequence |
|---|---|---|
| `workouts.template_id` | **SET NULL** | Deleting a template never deletes the workouts performed from it |
| `program_days.template_id` | SET NULL | Deleting a template empties a program slot, not the program |
| `templates.folder_id` | SET NULL | Deleting a folder unfiles its templates |
| `*_exercises.exercise_id` | SET NULL | Deleting a custom exercise empties a slot, not the plan |
| `measurement_entries.type_id` | SET NULL | |
| everything else child→parent | CASCADE | Sets go with their exercise, exercises with their template |

Purging a tombstoned template nulls `template_id` on **live** workout rows. That write bumps
`server_updated_at` so clients re-pull and learn the link is gone, and leaves `updated_at` alone so
a housekeeping job can never outrank a real user edit. Both halves are asserted in
`01_schema_test.sql`.

**A device offline longer than the retention window must be reset, not synced.** Past 90 days it can
no longer distinguish "deleted while I was away" from "created while I was away," and no amount of
tombstone data recovers the difference.

---

## Constraints as the loud-failure boundary

`02-architecture.md` § "MCP tool failures" makes the case that this server needs to fail loudly
because its Phase 3 clients are AI, and AI clients absorb errors and report success. Phase 0's
example was the spike coercing an unrecognised `set_type` to `"normal"`.

So the schema is deliberately strict where the app is already strict, and the checks are the ones
`RepRangeParser` and the RPE scale already enforce on device:

- **Native enums, not `text` + CHECK** — an unknown value is a hard error at the database boundary
- `reps` **XOR** a rep range, never both; a range is both ends or neither; `reps > 0`
- `rpe` is 6–10 in half steps (every legal value is exactly representable in binary floating point,
  so the check is exact rather than approximately true)
- `is_custom = false` **if and only if** `user_id IS NULL`

And one place it is deliberately *not* strict: **`weight` has no non-negative constraint.** Assisted
bodyweight sets carry assistance weight, which is negative. `weight >= 0` would reject an entire
exercise category, and it is the obvious-looking constraint most likely to be added by someone
tidying up later.

Two more absences worth stating so they are not re-added by reflex:

- **No unique index on `(parent_id, sort_order)`.** Reordering renumbers densely and transiently
  collides mid-move; a non-deferrable unique constraint would reject it. Ordering is owned and
  tested by `ListOrdering` / `TemplateOrdering`.
- **No CHECK forcing `program_cursor`/`total_cycles` null when `kind = 'folder'`.** Demoting a
  program to a plain folder must leave its data dormant, never delete it. That check is exactly the
  thing that would delete it.

---

## What is not here yet

- **Settings — the Postgres half.** No longer guessing at a shape: the units decision landed
  (`01-data-model.md`, 2026-08-18) and `AppSettings` exists locally with the full field list, so the
  Program exception now DOES apply — the design is settled and only the UI is deferred. What is
  missing is the table, its RLS policies and triggers, and the engine wiring; `AppSettings`
  deliberately does not conform to `Syncable` until they exist.
  > **One row per user means the key is `user_id`, not `id`** — the same per-entity conflict-target
  > problem `06-sync.md` already works through for `exercise_preferences`. Do it once for both. Until
  > then settings are local-only, so a second device silently shows pounds to a kg lifter.
- **Canonical units.** Set `weight`/`distance` carry no unit, matching the app, which means they are
  implicitly in the user's global unit — a setting that does not exist yet. `01-data-model.md`
  recommends canonical storage with unit as a display preference. **That decision has to land before
  there is real history**, because converting a year of stored values afterwards is a data migration
  against numbers a user typed. `measurement_entries.unit` is per-entry and is not affected.
- **The sync engine itself**, and the visible sync state `02-architecture.md` insists must be
  designed alongside it. That is the next piece of Phase 2, and it is the one that decides whether
  a failed push is something the user can see.
- **MCP call logging** (Phase 3) and **crash reporting** (Phase 4), both already placed in
  `02-architecture.md`.

---

## Running it

```
./supabase/tests/run.sh
```

Applies the shim, then every migration in order, then the tests, against a throwaway Postgres
container. Needs Docker and nothing else — no Supabase CLI, no project, no credentials. The
container is removed on exit, so it cannot touch a real project.

The tests are not a formality. **RLS is the entire authorization model here** — without it one
authenticated user reads every user's training history with a single unfiltered GET — and a policy
nobody has executed is a guess whose failure mode is silent. The suite was checked against three
deliberate regressions (RLS disabled on `workouts`; the trigger trusting a client-supplied
`server_updated_at`; `workouts.template_id` switched to CASCADE) and catches all three.

After editing either seed JSON, regenerate the library migration and commit both together:

```
python3 supabase/scripts/generate_library_seed.py
```
