# Sync

How local SwiftData and the hosted Postgres stay in agreement, and how the app shows you when they
do not.

`02-architecture.md` decided the strategy — client UUIDs, record-level last-write-wins, soft
deletes, a 90-day tombstone window — and the conflict-surface argument behind it, which is not
repeated here. `05-database.md` decided the server half. **This file decides the client half, and
the visible sync state that `02` insists must be designed alongside the engine rather than bolted
on afterwards.**

> **Correction to `02-architecture.md` § Mechanics.** That table says *"Pull: fetch rows where
> `updated_at > last_synced_at`."* **Do not implement that.** `updated_at` is the client's wall
> clock, so a device with a slow clock writes rows stamped in the past and any device whose cursor
> has moved beyond that point never sees them again — no error, no retry, permanently absent. Pull
> on `server_updated_at`, which no client can move backwards. The reasoning is in `05-database.md`
> § "Two timestamps". `updated_at` remains correct for its other job: the last-write-wins
> comparison.

---

## The shape

Four moving parts, in the order a sync runs:

1. **Claim** — stamp any un-owned local rows with the signed-in user (first sync only, see below).
2. **Push** — send every row marked dirty, parents before children.
3. **Pull** — fetch everything changed since the cursor, parents before children, resolving
   conflicts as it goes.
4. **Report** — update the sync state the UI reads.

Push before pull, deliberately. A local edit that has not left the device is the only copy in
existence; a remote edit is already durable. If a sync is interrupted halfway, the half that ran
should be the one protecting the thing that could still be lost.

---

## Dirty tracking: an explicit flag

Every synced `@Model` gains `needsSync: Bool = false`.

The obvious alternative — derive dirtiness from `updatedAt > lastSyncedAt` — was rejected because
**its failure mode is silent data loss.** A push that succeeds for eight rows and fails on the
ninth leaves the cursor in a state that either re-sends everything or, if advanced, skips the rows
that never made it. Nothing in the app would report the difference.

An explicit flag is set on every local write and cleared **only after the server confirms that
specific row**. A failed push leaves the flag set and the row is retried forever. There is no
arithmetic to get wrong.

A per-row outbox recording individual operations was also considered and rejected: we push whole
records and resolve at record level, so operation history buys nothing that the record itself does
not already carry.

> **The echo trap.** Applying a row that came FROM the server must not set `needsSync`, or every
> pull immediately dirties everything it touched and the next push sends it all straight back — a
> loop that looks like the sync is working extremely hard and never settles. The local write path
> and the remote-apply write path have to be different code paths, and only the first sets the
> flag. This is the single easiest way to write a sync engine that never terminates.

Alongside it, each model gains `updatedAt: Date` and `deletedAt: Date?`, mirroring the server.

> **Every one of these needs a DECLARATION-LEVEL default.** `var needsSync: Bool = false`, not a
> default in `init`. This is the migration rule from `04-status.md`, and this change is the exact
> situation that rule exists for: three new properties across eleven models, applied to a store
> that already has data in it. A default only in `init` is invisible to SwiftData's lightweight
> migration and `ModelContainer(for:)` throws on launch. **Unit tests cannot catch it** — they
> build in-memory containers from the current schema, so there is never an old store to migrate.
> The two UI tests, run against a previous build's store, are the only thing that can.

---

## Deletes become soft, everywhere

This is the largest single piece of work in the phase, and it is not hard so much as *pervasive*.

- **Nothing calls `context.delete(...)` on a synced model any more.** A delete sets
  `deletedAt = .now`, `updatedAt = .now`, `needsSync = true`.
- **Every query and every relationship read filters `deletedAt == nil`.** A missed filter shows
  the user a workout they deleted last week.
- **Cascade becomes manual.** SwiftData's `.cascade` rules fire on real deletes and will not fire
  here. Soft-deleting a `Template` must walk its `TemplateExercise`s and their `TemplateSet`s and
  tombstone each one. The relationships stay declared — they still describe the shape, and they
  still govern the eventual hard delete — but they no longer do this job.
- **Nullify is emulated by doing nothing.** Soft-deleting a template leaves `Workout.template`
  pointing at a tombstoned row, which is fine: history reads its own stored `name`, never the
  template's. The link goes nil eventually, when the server purges the tombstone at 90 days and
  nulls `template_id` — and because that server write bumps `server_updated_at` without touching
  `updated_at`, the pull picks it up and it cannot outrank a real user edit. The two halves of that
  were built for each other; see `05-database.md`.

**Hard deletes still exist locally, for one case only:** a row that has never been pushed
(`needsSync == true` and never confirmed) has no server counterpart to tombstone, so it can simply
go. Everything else waits for the 90-day sweep and arrives as a pull.

---

## Ordering

Foreign keys mean parents before children, in both directions. One order serves both:

```
exercises → exercise_preferences → template_folders → templates →
template_exercises → template_sets → program_days →
workouts → workout_exercises → workout_sets →
measurement_types → measurement_entries
```

Because every operation is an upsert — including deletes, which are updates that set `deleted_at`
— there is no reverse pass. Nothing is ever removed by sync, so no child is ever orphaned by it.

---

## Conflicts

Record-level last-write-wins on `updated_at`, as decided. Concretely, for a pulled row that also
exists locally:

| Local | Remote | Outcome |
|---|---|---|
| clean | anything | take remote |
| dirty, `updatedAt` older | newer | **take remote, and drop the local edit** |
| dirty, `updatedAt` newer | older | keep local; it pushes on the next run |

**The middle row discards a real user edit, silently, by design.** That is the accepted cost of
LWW and it is the right trade at one user with two devices — but *"my template reverted"* has to be
diagnosable rather than spooky. So the discard is written to a local log with both timestamps and
both values, per `02-architecture.md` § Observability. The log is local; nothing about a discarded
edit needs to leave the device.

### The table above is the client half. The server has to enforce it too.

The client resolver only runs on a PULLED row. A PUSHED row is just an upsert, and for a while the
server had no opinion about which edit won — it overwrote unconditionally. So a device holding a
stale edit destroyed a newer edit made on another device, and the table above described something
nothing implemented.

A `BEFORE UPDATE` trigger now cancels any write whose `updated_at` is older than the row it would
replace (`supabase/migrations/20260816140000_last_write_wins.sql`). Three properties of it are
load-bearing and are argued in that file rather than repeated here: a suppressed write must not
bump `server_updated_at` (it is every device's pull cursor), tombstones must still pass, and ties
are allowed through because housekeeping writes deliberately leave `updated_at` alone.

### Push-before-pull hides the local flag, so the engine carries it

A run pushes first, and a confirmed push calls `markSynced()`. So by the time the pull examines a
row, **this run's own push has already cleared the flag the conflict decision wants to read.** Read
naively, `needsSync` is false for every row the run sent — which is every dirty row — and all three
outcomes above collapse to `.takeRemote`, making `.keepLocal` and
`.takeRemoteDiscardingLocalEdit` unreachable in normal operation.

The engine therefore records the ids it sent this run and decides dirtiness as *flag OR sent*.
`updatedAt` needs no such treatment: `markSynced` clears the flag and touches nothing else.

> **Do not "fix" this by leaving the row dirty after a confirmed push.** It makes the obvious test
> pass and re-sends the same row on every subsequent run, forever — an unreachable branch traded
> for an infinite upload loop, and no structural check can see it.

One imprecision is accepted deliberately: a row pushed successfully and *then* superseded by a
newer remote edit inside the same pull is logged as a discard, though nothing was discarded. The
common case is already silent, because an echo of our own write carries the same `updatedAt` and
ties go to local, so this needs two devices writing inside one pull window. The alternative —
`upsert(returning: .representation)`, inferring rejection from an absent row — couples the client
to the guard's internals for the sake of a local diagnostic log.

---

## The visible sync state

`02-architecture.md`: *"Local-first makes this invisible by construction. The user logs a workout,
SwiftData accepts it, the UI says done — and the push to Postgres fails. Nothing in the experience
distinguishes that from success."*

So the app carries a sync state that is always truthful and never flattering:

| State | Meaning | How it shows |
|---|---|---|
| `.never` | Signed in, never completed a sync | Stated plainly. **Not** shown as "up to date" |
| `.syncing` | In flight | Quiet indicator |
| `.upToDate(at:)` | All local changes confirmed | Timestamp, not a checkmark alone |
| `.pending(count:)` | Changes waiting — usually offline | Count, and it is not an error |
| `.failed(count:, reason:)` | Retried and still failing | Visible and actionable |

Three rules about this, all of them versions of *never display a fabricated zero*:

- **`.never` is not `.upToDate`.** A fresh install that has never reached the server must not show
  a reassuring state. That is the fabricated-zero mistake with the highest stakes in the app.
- **`.pending` is not a failure.** Being in a gym with no signal is the normal case this app was
  designed for. It reports a count and nothing alarming.
- **`.failed` must say what is safe.** Every message says the workouts are still on the phone,
  because they are, and because the user's first fear is that they are not.

**Where it lives:** the Profile tab, beside the account card, as the detailed view — and a single
unobtrusive indicator that appears **only** in `.failed`, where the user will see it without
looking. A permanent status badge on the logging screen would be noise 99% of the time and would
train people to ignore the one moment it matters.

---

## Two problems specific to this app

### Rows that predate sign-in

Sign-in is required up front, so no *new* install can create un-owned rows. But the store on the
development machine predates the gate, and `user_id` is `NOT NULL` on the server — those rows
cannot be pushed until something claims them.

So the first sync after sign-in stamps un-owned rows with the current user. **The device records
which user it claimed for.** If a different account later signs in on the same device, it must NOT
re-claim: that would hand one person's training history to another, which is the worst bug this
document could allow. Different user, different data — sign-out with unpushed rows is a case that
needs its own decision before this ships.

### The seeded library exists twice

The seeded exercises and measurement types are local SwiftData rows *and* global Postgres rows
(`user_id IS NULL`), sharing the same baked UUIDs by design.

- **Push only `isCustom == true` exercises.** A seeded row pushed as user data would be rejected by
  the `exercises_custom_iff_owned` constraint, which is the constraint doing its job — but it would
  also fail every sync until fixed, so filter rather than discover.
- **Pulled seeded rows reconcile by id** and simply match what is already there. Their per-user
  fields live in `exercise_preferences`, which is ordinary owned data.

---

## Per-exercise preferences get their own local model

**Status: APPROVED by Drake 2026-08-16. THE MODEL IS BUILT (2026-08-18). The sheet is not.**

> **What exists now:** `Models/ExercisePreference.swift`, an optional `Exercise.preference`
> relationship, and every display site reading through it. What does NOT exist: the Preferences
> sheet, so nothing calls the write path yet, and the conformance below.
>
> ⚠️ **IT IS NOT `Syncable` AND MUST NOT BECOME ONE UNTIL THE CONFLICT TARGET IS PER-ENTITY.**
> `SyncClient.upsert` hard-codes `onConflict: "id"` and this table's key is
> `(user_id, exercise_id)`. PostgREST would reject the batch, and a rejected batch aborts the
> WHOLE RUN — the pull never happens either and every later sync fails identically. That is what
> the 18 seeded measurement types did (`04-status.md` § "What running it for real found"). Same
> arrangement as `AppSettings`, same one fix for both.

> **Two things learned after this was written, from screenshots of the reference app.** Neither
> changes the decision below; both change the scope.
>
> 1. **The Preferences sheet is TWO items, not four** — Weight Unit and Bar Type. `focusMetric` and
>    `notes` are not edited there. The model still carries all four; only the sheet is smaller than
>    assumed.
> 2. **Weight Unit has three options, not two:** Default, Metric (kg), US/Imperial (lbs), where
>    *Default* follows a global setting. `weightUnitOverride: WeightUnit?` already expresses that
>    exactly — `nil` IS Default. The global setting it defers to now exists (`AppSettings.weightUnit`),
>    though item 2 on the status list — the settings screen — is what lets anyone change it.
>
> ~~**And one open question this raised:** the reference app's Bar Type carries a WEIGHT per
> case…~~ **CLOSED.** `BarType.weight(in:)` exists and carries two real-world constants per bar
> (45 lb / 20 kg for an Olympic bar are different bars, not two spellings of one), and the cases
> are values of the live Postgres enum `public.bar_type`. The picker can show weights. Do not
> rename the cases.

`exercise_preferences` has existed as a table since the first migration with nothing writing it
(`05-database.md` § "The one real divergence"). Wiring it up looked like a small job and is not,
because four things do not line up between the two sides. They are recorded here because three of
them have the silent-data-loss failure mode, and because the alternative — hanging the sync off
`Exercise`, which already carries the four fields — makes all four worse at once.

### What does not line up

1. **The table has no `id`.** Its primary key is `(user_id, exercise_id)`. Every other synced table
   has a single `id`, and `SyncWireRow`, the pull's index, and the upsert's conflict target all
   assume that.
2. **The upsert always conflicts on `"id"`.** Hard-coded in `SyncClient`. This table needs the pair.
3. **The push rule is INVERTED relative to exercises.** `PushFilter.shouldPush(Exercise)` requires
   `isCustom`, because a seeded exercise is global library and pushing it as owned data breaks the
   run. But a *preference* on a seeded exercise — the bar type you use for Bench Press — is the
   user's own data and MUST travel. Two rules reading the same object, disagreeing by design, is a
   thing somebody later "tidies up" into one.
4. **One local object, two server rows, one dirty flag.** With the fields on `Exercise`, the
   exercises push and the preferences push share `needsSync` and `updatedAt`. Exercises push FIRST
   (`SyncEntity` order), and a confirmed push calls `markSynced()` — so by the time the preferences
   pass runs, the flag it needs to read has already been cleared by the pass before it. That is the
   same shape as the bug fixed in `e84d3b3`, one phase earlier in the run.

### The decision: move the four fields to an `ExercisePreference` @Model

`weightUnitOverride`, `barType`, `focusMetric` and `notes` leave `Exercise` and become their own
synced model, keyed to an exercise. `Exercise` goes back to being purely what the library defines —
which is exactly the split the server already made. `05-database.md` says of that split: *"This line
already existed; it just wasn't a table boundary yet."* This makes it one on the client too.

Doing that dissolves three of the four problems rather than solving them:

- **(1) and (2) shrink to one line.** The local model gets an ordinary `id`, so the pull index and
  `SyncWireRow` work unchanged. The conflict target becomes a per-entity fact on `SyncEntity`
  alongside `tableName`, defaulting to `"id"`, because the two facts about a table belong together.
  > **CORRECTED WHEN THIS WAS BUILT: the id is ordinary in SHAPE, not in VALUE.** It is a `UUID`
  > property, so the pull index and `SyncWireRow` do work unchanged — but its value is **the
  > exercise's id**, not a freshly minted one, because the server table has no `id` column to
  > match a minted one against. There is at most one preference row per user per exercise, so the
  > exercise's id is the natural key and is already agreed by every device (exercise ids are baked
  > into the seed). `ExercisePreference(id: UUID())` would mint two different local ids for what
  > the server stores as ONE row, and the pull would create a duplicate on every device with no
  > way to tell them apart — last-write-wins cannot settle two rows it does not know are the same
  > thing. `init` therefore takes `id:` with no default; the resolver is the only construction site.
  >
  > **The consequence for the conflict-target work:** the wire row's `id` has nothing to decode
  > from. It has to be derived from `exercise_id` on the way in, not read off the row.
- **(3) disappears.** The preference row is not the exercise row, so it needs no exception and no
  second opinion about `isCustom`. A preference on a seeded exercise pushes because it is an
  ordinary owned row that happens to point at a global one.
- **(4) disappears.** Its own `needsSync` and its own `updatedAt`, so nothing upstream in the run
  can clear a flag it depends on.

And one thing it buys that the alternative cannot: **the table stays sparse by construction.** A
preference row exists only where the user actually set one. Hanging sync off `Exercise` would push a
row for every dirty exercise — and on a fresh install every one of the 25 seeded exercises is dirty,
because `needsSync` defaults to `true` and the exercise push filter never clears them. The first
sync would have written 25 rows of pure defaults. That is the same shape as the 43 fabricated
discard entries in `00faec1`: a flag that means "never confirmed" being read as "the user did
something".

### Why this migration is the safe kind

The rule that has cost this project the most is *every `@Model` property needs a declaration-level
default* — adding a property to a model whose store already has rows. **This is not that.** Adding a
NEW `@Model` type creates a new local table with no existing rows to migrate, which lightweight
migration handles without an opinion.

Removing the four properties from `Exercise` is the half worth checking, and it is safe for a
reason that will not stay true: **nothing writes them today.** There is no UI for them — that is
precisely why this work exists — so there is no user data to carry across. `ExerciseSeedImporter`
preserves them on re-seed and must stop referring to them; that is the one call site to update.

> **If this is deferred, do it before there are users, not after.** The moment somebody has set a
> bar type, moving the field stops being free. **Done 2026-08-18, with a real store on a real
> phone and no preference ever written — the last moment it was free.**

> **The third half, which this section missed: the RELATIONSHIP is also a property added to
> `Exercise`.** `var preference: ExercisePreference?` goes onto a model whose store already has
> rows on Drake's phone, so it is squarely the crash-on-launch class after all. It is safe only
> because it is OPTIONAL on both sides. A non-optional relationship there would be the same launch
> crash as `var sortOrder: Int`, and the unit suite would stay green through all of it — in-memory
> containers are built from the current schema, so there is never an old store to migrate. The
> inverse is declared on `Exercise`, matching every other parent in the codebase.

> **`current(for:in:)` returns a TOMBSTONED row rather than skipping it, and that is deliberate.**
> `AppSettings.current` filters `deletedAt == nil` and creates a fresh row with a fresh id when it
> finds none. This one cannot: its id IS the exercise's id, so creating a second row would mean two
> rows with the same UUID, which is worse than handing back the tombstone. Nothing deletes a
> preference today. **Whoever builds the first delete path owns reviving it** — clearing
> `deletedAt` when the user sets a preference again — and this is the note that says so.

## Syncing the two singleton-ish tables: `app_settings` and `exercise_preferences`

**Status: DECIDED 2026-08-18, before building any of it.** Same order as the preferences split
above, and for the same reason: three of the four problems here are silent-data-loss shaped, and
two of them were only found by writing the design down.

These are one job because they share one blocker. Every other synced table is keyed on `id`, and
`SyncClient.upsert` hard-codes `onConflict: "id"`. Neither of these is:

| Table | Server key | Because |
|---|---|---|
| `app_settings` | `user_id` | one row per person |
| `exercise_preferences` | `(user_id, exercise_id)` | one row per person per exercise |

### The conflict target becomes a per-entity fact

`SyncEntity` gains `conflictTarget`, defaulting to `"id"`, alongside `tableName` — the two facts
about a table belong together, and a table's key is not something a caller should have to remember.
`SyncTransport.upsert` takes it as an argument rather than reading a global.

> **Nothing may conform to `Syncable` until the migration is applied AND VERIFIED REMOTE.** If the
> client pushes to a table the server does not have, PostgREST rejects the batch — and a rejected
> batch aborts the WHOLE RUN, so the pull stops too and every later sync fails identically. That is
> the 18-seeded-measurement-types failure exactly. The ordering rule that got broken on 2026-08-18
> was defended by a comment and lost; this one is defended by sequence, because the conformance is a
> separate commit from the migration and `supabase migration list` is the gate between them.

### `AppSettings` does NOT go through the pull index

The generic pull matches a server row to a local one with `index[row.id]`. **For a singleton that is
the wrong question**, and asking it anyway destroys a real setting:

> **The failure it would cause, concretely.** Drake's phone already has an `AppSettings` row,
> created before sync existed, carrying a random `UUID()`. The server will identify settings by
> `user_id`. On the first pull the ids do not match, so the engine treats the server's copy as a new
> row and inserts a SECOND one. `AppSettings.current(in:)` resolves "oldest live row wins", so the
> app would then read whichever happened to be older — and the unit choice appears to revert at
> random, on a value whose entire job is telling the user what their numbers mean.

So settings pull through `AppSettings.current(in:)` rather than an id lookup: resolve the one row,
run the same `ConflictResolver` against it, apply onto it. `SyncAppSettingsRow.id` is a COMPUTED
property returning `userID`, present only to satisfy `SyncWireRow`; nothing matches on it.

**Rejected: rewriting the local row's id to the user id.** It cannot be a `StoreMigrations` step —
those run at launch and this needs a signed-in user, so it would be a sync-time fixup wearing a
migration's clothes. And it solves a problem that only exists if we insist on using the index.

`ExercisePreference` is the opposite case and needs no special path: its local `id` IS the exercise's
id (see the correction above), which every device agrees on independently, so the generic index
works unchanged. Its wire row's `id` is likewise computed — from `exercise_id`, because that table
has no `id` column either.

### A never-touched settings row MUST NOT PUSH, and this is the one that would have bitten

`needsSync` defaults to `true` and `MCPStrengthApp` creates the settings row at first launch. So a
newly installed device has a settings row that is dirty, carries pure defaults, and has never been
touched by anybody.

> **The sequence that loses data.** Drake picks kilograms on phone A; it pushes at time T. He
> installs on phone B. B creates its default row (pounds, `updatedAt == .distantPast`,
> `needsSync == true`). A run is claim → **push** → pull, so B pushes BEFORE it pulls — and
> `pushModels` backfills `.distantPast` to `Date()` on the way out, which is now, which is later
> than T. **Phone B uploads pounds over the kilograms Drake chose, wins last-write-wins doing it,
> and then pulls its own answer back.** The setting silently reverts on both devices and nothing
> anywhere reports a conflict, because as far as the engine is concerned B made the newer edit.

The fix is a push filter, not scheduling: `PushFilter.shouldPush(_ settings: AppSettings)` requires
`updatedAt != .distantPast` — *this row has actually been edited*. A defaults row is "never touched",
and `.distantPast` is exactly how this codebase already spells that. `setWeightUnit` stamps it, so
the moment a user genuinely chooses something the row becomes eligible.

This is the same shape as the seeded-library filter and as the sparse `exercise_preferences` table:
**a value meaning "never touched" must never be read as "the user did something".** That is now the
fourth instance in this project (43 fabricated discards, 25 rows of default preferences, the seeded
push, this), which is enough to call it the house failure mode.

> The backfill is safely downstream of the filter — `pushModels` checks `shouldPush` before it
> stamps — so no extra guard is needed there. Do not reorder those two.

`exercise_preferences` needs no equivalent filter, because a preference row only exists where the
user set something. That is the whole point of keeping it sparse.

### A nil field must travel as an explicit `null` — the synthesised encoder will not do it

**Found by the test suite on 2026-08-18, after the Ringer check had passed.** Swift's synthesised
`encode(to:)` uses `encodeIfPresent` for every `Optional`, so a nil property is OMITTED FROM THE JSON
ENTIRELY. An upsert is `INSERT … ON CONFLICT DO UPDATE` and its SET clause is built from the keys the
payload actually contains — so **an omitted column keeps whatever the server already had.**

That silently turns *clear this* into *leave it alone*:

1. the user picks Olympic Bar for Bench Press; `bar_type` pushes and the server stores it;
2. they change their mind and pick *Not set*; `barType` becomes nil, the key vanishes from the
   payload, and the server keeps `olympicBar`;
3. the next pull brings `olympicBar` back down and overwrites the local nil. **The setting
   un-clears itself**, on every device, and nothing reports anything.

`ExercisePreferencesSheet` offers *Default* and *Not set* as real choices — `nil` IS the chosen value
there, not a missing one — so this is reachable the day that sheet ships. Both new row structs write
`encode` rather than `encodeIfPresent` and the clear travels as `null`.

> **`serverUpdatedAt` is the one field that must still be OMITTED rather than nulled.** It is
> server-owned, the trigger writes it on every write, and a key for it is at best noise.

> ✅ **FIXED ACROSS ALL THIRTEEN ROWS, 2026-08-19.** Every struct now writes its own
> `encode(to:)`, so a nil travels as an explicit `null`. The most reachable instance was one this
> section originally missed: **Leave Superset** is a shipped menu item that clears
> `superset_group_id`, so leaving a superset never travelled and the next pull put you back in it.
> Unfiling a template, deleting a note or summary, and removing a prescribed or logged weight were
> the others.
>
> **Do NOT write `init(from:)`.** Providing only `encode(to:)` leaves the decoder synthesised, and
> it already reads an explicit `null` as nil for an Optional. A hand-written decoder is more
> surface for no gain, and "completing the Codable pair" is a plausible tidy-up to resist.

> ⚠️ **THE FIX CREATES A WORSE BUG IF IT IS EVER EXTENDED CARELESSLY, and this is the paragraph
> that matters.** With hand-written encoders, a field whose `c.encode` line is FORGOTTEN never
> travels at all — set or cleared — where the original bug at least let a set value through. It
> would compile, the mapper would fill it, and every existing round-trip test would still pass,
> because those all assert on keys they already know about.
>
> So the defence is structural, not care: **every `CodingKeys` is `CaseIterable`**, and
> `everyNilOptionalStillEmitsItsKeyExceptServerUpdatedAt` builds each row with every optional nil
> and iterates `CodingKeys.allCases`, asserting each key is present. Adding a column and forgetting
> the encoder line fails that test immediately. **If you add a row struct or a column, that test is
> the thing to keep working.**
>
> The conformance sits on a same-file `extension`, not on the enum's declaration line, and that is
> forced rather than stylistic: `supabase/scripts/check_row_mapping.py` matched
> `enum CodingKeys: String, CodingKey {` literally, so `, CaseIterable` there made it report every
> struct as having no keys at all. **The script has since been relaxed to allow extra
> conformances**, so either placement works now — but the extension is what shipped and moving it
> is churn.
>
> **Why no test caught it for eleven structs:** every existing round-trip test builds a row with
> values PRESENT. The absence is the case nobody wrote, which is the same shape as the warm-up ramp
> bug (every test used a set list with no warm-ups in it).

### What the Postgres half needs

A new migration, verified remote before anything else moves: an `app_settings` table keyed on
`user_id` with the field list from `Models/Settings.swift`, two new enums (`distance_unit`,
`size_unit`), the owner-only RLS policy, and registration in BOTH trigger lists — the
`set_sync_metadata` list in `0002` and the last-write-wins list in `0008`. Those lists are explicit
rather than looped over `information_schema` on purpose, so a new table has to be added deliberately;
adding one and forgetting the lists yields a table with no `server_updated_at` maintenance, which
means it never appears in a pull.

`theme`, `language` and `previous_set_behavior` are `text`, not enums — their case lists are
deliberately undecided (`Models/Settings.swift`), and an enum on the server would commit both sides
to cases nobody has chosen.

## Out of scope

- **Realtime.** Pull on launch, on foreground, and after a workout is finished. A push
  subscription is a Phase 3+ refinement; polling at those three moments covers a single user with
  two devices.
- **HealthKit.** Phase 2 per `02-architecture.md`, but after this. It has its own echo-loop trap
  and `MeasurementEntry.source` exists for it.
- **Partial-field merge.** Record-level LWW is the decision; field-level merge is what you build
  when the conflict table says you must, and it does not.

---

## Open question

**Signing out with unpushed changes.** Today sign-out leaves the local store untouched and the
dialog says so. Once sync exists, signing out with dirty rows means those edits may never reach the
server — and offering to clear local data turns a reversible action into a destructive one, on the
device holding the only copy. Decide before sync ships; do not let the current copy quietly become
untrue.
