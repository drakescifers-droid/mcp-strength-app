# Architecture

Decisions and their reasons. Companion to `01-data-model.md`.

## Context

- **Product, not personal tool.** Multi-user from the start: real auth, row-level security,
  per-user MCP credentials.
- **Sync built properly.** The app must work fully offline in a gym with no signal, and AI
  writes must reach the same data from anywhere.

---

## The shape

```
┌──────────────────┐                    ┌──────────────────┐
│   iOS app        │                    │   MCP server     │
│   (SwiftUI)      │                    │  (remote, OAuth) │
│                  │                    │                  │
│  SwiftData       │                    │  list_exercises  │
│  = local truth   │                    │  create_template │
│  ─────────────   │                    │  log_workout     │
│  sync engine     │                    │  get_history     │
└────────┬─────────┘                    └────────┬─────────┘
         │                                       │
         │            ┌──────────────┐           │
         └───────────▶│   Postgres   │◀──────────┘
                      │  (Supabase)  │
                      │  + RLS       │
                      └──────────────┘
                       source of truth
```

Three clients, one database. The iOS app and the MCP server are peers — neither is privileged.
That symmetry is the whole point: anything the app can do, AI can do, because they're hitting
the same schema through the same rules.

**The app is local-first.** SwiftData on device is what the UI reads and writes. The sync
engine pushes to Postgres in the background. A workout logged in a basement gym is real the
moment it's tapped; the network is a detail that resolves later.

### Why not CloudKit

CloudKit would make the app half trivial — free, native, iCloud handles auth and offline sync.
It fails on the MCP half: server-to-server keys reach only the *public* database, and external
access to a user's private database needs a web auth token that expires and must be re-obtained
through user sign-in. An MCP server built on that sits on a credential that periodically
breaks. For an app where MCP is the reason the product exists, that's disqualifying.

### Why not a custom backend

You'd spend the first month rebuilding auth, RLS, and connection pooling. Supabase gives all
three, and Postgres means the MCP server is doing plain SQL.

---

## Sync

This is the hard part, and it's where the subtle bugs live. Two things make it tractable here.

### 1. Client-generated UUIDs

Every record's `id` is a UUID generated on whichever client creates it. No server round-trip to
get an identity, so offline creates are ordinary writes, and there is never an ID reconciliation
step. This is load-bearing — it's what makes offline-first sync merely hard instead of awful.

### 2. The conflict surface is much smaller than it looks

General bidirectional sync is genuinely hard. This app is close to the easy case, because each
entity has a natural writer:

| Entity | Written by | Conflict risk |
|---|---|---|
| **Workouts** | The app, during a session. Immutable once finished. | **None in practice.** Effectively append-only — push up, never merge. |
| **Measurements** | The app (or HealthKit). Append-only time series. | **None.** |
| **Exercises** | Both, but almost always appends. | **Low.** Fuzzy-match on create (below). |
| **Templates** | Both — this is where AI writes. | **Real, but rare.** |
| **Programs** | Both, at very different rates — the app advances position after every session; AI writes structure occasionally. | **Low**, by construction — see below. |

Programs look like the worst case on that table and aren't, because of how they're split in
`01-data-model.md`. The frequently-written field (`cursor`, a single position advanced after each
session) lives on the folder row; the rarely-written structure lives in separate `ProgramDay` rows. The
every-session write and the occasional AI write therefore land on **different records**, so
record-level last-write-wins never has to choose between them. `ProgramDay` was split out to allow
repeated day slots (a 3-day A/B split needs `A, B, A`); this is a second, independent reason it is
the right shape. The residual conflict — an AI edit to folder-level fields (`totalCycles`, `name`,
`kind`) landing while the phone is offline mid-block — has the same shape and rarity as the
Templates row.

So only templates need genuine conflict handling, and only when the same template is edited in
both places between syncs. Record-level last-write-wins on `updatedAt` is acceptable there: the
loser is one edit to one template, and the user is a single person who is unlikely to be editing
the same plan in two places seconds apart.

**Design against the grain of that table.** If a future feature makes workouts mutable long
after the fact, or makes templates collaboratively edited, revisit this — the simplicity is
earned by the access pattern, not guaranteed by the design.

### Mechanics

Every synced table carries:

| Column | Purpose |
|---|---|
| `id` | UUID, client-generated |
| `user_id` | Owner. RLS policies key off this. |
| `updated_at` | Last write timestamp. The LWW comparison key. |
| `deleted_at` | Soft delete (tombstone) — so deletes propagate instead of resurrecting |

Each device keeps a `last_synced_at` cursor.

- **Pull:** fetch rows where `updated_at > last_synced_at`
- **Push:** send local rows marked dirty
- **Conflict:** compare `updated_at`, last write wins at record level
- **Delete:** never hard-delete a synced row; set `deleted_at` and let it propagate

> **The Pull line above is wrong, and is left in place so the correction is findable.** Pulling on
> `updated_at` — a CLIENT wall clock — loses rows silently: a device with a slow clock writes a row
> stamped in the past, and any device whose cursor has moved past that point never sees it again.
> Pull on `server_updated_at`, which the server sets and no client can move backwards, with a small
> overlap window. `updated_at` stays exactly right for the Conflict line. Full reasoning in
> `05-database.md` § "Two timestamps"; the client side is `06-sync.md`.

**Hard deletes only after a tombstone-retention window** (say 90 days), swept server-side — a
device offline longer than that resyncs from scratch rather than resurrecting deleted rows.

---

## Auth

Supabase Auth issues the user identity. Row-level security policies scope every table by
`user_id`, so a query without a valid user context returns nothing — a wrong or missing token
fails closed, at the database, not in application code.

### The MCP server's auth is the interesting part

Each user connects Claude to *their own* data. The MCP server is a remote server users add as a
connector; the connection is authorized via OAuth, and the resulting token is scoped to one
user. The MCP server then queries Postgres **as that user**, so RLS does the enforcement — the
MCP layer never decides who can see what.

That's the property worth protecting: the MCP server holds no privileged database credential
and has no ability to read across users. It's a thin translation layer between MCP tool calls
and a user-scoped Postgres session.

> **To verify at implementation time:** exact OAuth flow requirements and transport for remote
> MCP servers, and how the connector registration works on each Claude surface. The MCP spec
> moves; check current docs rather than trusting this paragraph.

---

## MCP tool surface (sketch — full design in `03-mcp-tools.md`)

The contract between AI and app. Roughly:

| Tool | Purpose |
|---|---|
| `list_exercises` | Search the library. AI calls this **before** creating anything. |
| `create_exercise` | Add to library. Fuzzy-matches first; returns the existing match if close. |
| `get_templates` / `get_template` | Read plans |
| `create_template` / `update_template` | Write plans — the YouTube→template path |
| `get_workout_history` | Read history, date-filtered — the reporting path |
| `get_exercise_progress` | Per-exercise time series for coaching |
| `log_workout` | Conversational logging |

**The exercise library is the integrity constraint.** Without a seeded library and fuzzy
matching on create, every AI-generated plan invents its own names and history fragments into
"Lateral Raise (Machine)" / "Machine Lateral Raise" / "Lat Raise" — and then progress tracking,
the entire point, silently breaks. `create_exercise` should return an existing close match
rather than creating a near-duplicate, and say that it did.

---

## Observability

Three different problems get called "error logging" here. They have different stakes and land in
different phases.

### 1. App crashes

Lowest stakes, effectively solved by picking a tool. Xcode Organizer reports crashes for free once
the app ships through the App Store; Sentry or Crashlytics if symbolicated non-fatals and
breadcrumbs are wanted. Phase 4.

### 2. Sync failures — the category that loses data

**Local-first makes this invisible by construction.** The user logs a workout, SwiftData accepts it,
the UI says done — and the push to Postgres fails. Nothing in the experience distinguishes that from
success. They find out weeks later on another device, or never.

So this needs more than a log line:

- Failed pushes stay marked dirty and get retried, never silently dropped
- A durable local record of what failed and why
- Something **visible in the UI** — a sync state the user can see and act on

Also worth recording: last-write-wins discards the losing edit silently. That is correct behavior,
but *"my template reverted"* should be diagnosable rather than spooky — log the discard locally with
both sides' `updated_at`.

Design this in Phase 2 **alongside** the sync engine. Retrofitting visibility onto a sync layer that
was written assuming success is far harder than building it in.

### 3. MCP tool failures — the category with no feedback channel

> **Design note — the usual bug-report channel does not exist here.** An ordinary app has a free
> feedback loop: something breaks, a human sees it, they complain. An MCP server's client is an AI,
> and AI clients absorb errors — the model gets a failure, works around it, and tells the user the
> task succeeded. The failure never reaches anyone who could report it.

Phase 0 produced a live example. The spike silently coerced an unrecognised `set_type` to `"normal"`
and returned success; the client reported back that drop sets were unsupported — a confident bug
report about the wrong thing, for a feature that worked fine. In production that surfaces as a user
asking why a feature is missing when it is not.

The consequence: this server needs server-side call logging **more** than a conventional backend
does, precisely because its clients paper over the evidence. Per tool call, at minimum: tool name,
arguments, outcome, duration, and anything the server ignored, coerced, or fuzzy-matched. The
`ignored_fields` and `matched_to_existing` values in `03-mcp-tools.md` are not only responses to the
model — they are the audit trail.

Supabase Edge Functions provide the log sink, so this is a decision to record rather than
infrastructure to build. Phase 3.

---

## Phasing

Ordered to de-risk the *uncertain* thing first, not the familiar thing.

**Phase 0 — prove the magic is actually magic.**
Local SwiftData schema + a throwaway MCP server pointed straight at the local store, no auth,
no sync, no polish. Goal: paste a YouTube link to Claude, watch a template appear. If that
doesn't feel as good as it sounds, everything downstream changes — and you'll have spent days
instead of months finding out.

**Phase 1 — the app, offline.**
Real SwiftUI logging: templates, folders, live workout, set types, rest timers, history,
measurements. Fully usable on-device, no backend. This is a working app you can train with.

Also lands here, from Phase 0 (`03-mcp-tools.md`):

- **Rep ranges and RPE on `TemplateSet`** — `repRangeStart` / `repRangeEnd` / `rpe`, plus `rpe` on
  `WorkoutSet`. The spike proved a single integer rep count loses every prescription.
- **`aliases` on Exercise**, and stable seeded UUIDs in the library file.
- **The Program schema** — `TemplateFolder.kind`, `ProgramDay`, `cursor`, `totalCycles`. Schema
  only; the program UI is deferred to a post-launch update. This one is easy to skip and expensive
  to skip: because the UI ships after launch, letting the schema slide with it means adding a table
  to a database already holding real training history.

**Phase 2 — backend and sync.**
Supabase, schema, RLS, auth, sync engine. The long unglamorous phase.

**Phase 3 — the real MCP server.**
Multi-user, OAuth, hosted, on top of Phase 2's database.

**Phase 4 — product.**
App Store, onboarding, pricing.

Phases 1 and 2 look like "build a worse Strong," which is why Phase 0 exists: it front-loads the
question the rest of the project is betting on.

---

## Decisions

**MCP server hosts on Supabase Edge Functions.** Keeps the whole system on one platform — one
bill, one dashboard, and the database is already adjacent. The constraint to verify at Phase 3
is whether the Edge runtime supports MCP's transport for a long-lived connection; if it
doesn't, fall back to a container host (Fly / Railway / Render).

**Apple Watch is deferred to v2.** The phone app gets built cleanly first. Cost of deferring:
adding Watch later means revisiting the local data layer, since live Watch↔phone session sync
touches how an in-progress workout is represented.

**Apple Health is bidirectional.** Measurements import from Health *and* write back to it.

> **Scope fact found when this was built: only 4 of the 18 seeded measurement types exist in
> HealthKit** — Weight (`bodyMass`), Body Fat % (`bodyFatPercentage`), Caloric Intake
> (`dietaryEnergyConsumed`) and Waist (`waistCircumference`). The other fourteen are limb and torso
> circumferences and HealthKit has no type for any of them. "Measurements sync" is therefore
> narrower than it sounds, and the measurements screen will have to say which rows can travel
> rather than implying all of them do.

> ✅ **WORKOUTS → HEALTH SHIPPED 2026-08-19, one direction.** Drake's call on sequencing, and it
> makes the echo loop below *structurally impossible for this half*: nothing is ever read, so
> nothing can be re-imported. Measurements — the genuinely bidirectional part — land afterwards on
> permission and settings plumbing that is already proven.
>
> **Decisions worth not re-deriving:**
>
> * **Idempotency comes from `HKMetadataKeyExternalUUID`, not a local flag.** The workout's own id
>   goes in that metadata field and the writer asks Health whether it already has it. A
>   `didWriteToHealth` column was rejected: it is a stored property on a synced model (the
>   crash-on-launch rule), it needs a Postgres column to travel, and it would still be WRONG across
>   devices, because Health syncs via iCloud and the entry can already be there while a second
>   phone's flag says otherwise. Ask Health what Health has.
> * **No energy burned, and no total volume.** Nothing computes calories — no heart rate, no body
>   mass on the workout, no METs table — so any number would be invented, and `0` is worse than
>   absent because Apple Fitness would render "0 calories" against an hour of squatting. That is
>   AGENTS.md rule 4 applied to somebody else's UI, where we cannot add a caveat. Revisit if a
>   defensible estimate ever exists.
> * **Authorization IS the on/off switch.** No stored preference: HealthKit already keeps a
>   per-device answer and iOS owns the UI for it, so a second flag is a second source of truth that
>   can disagree. The consequence is real and is stated on the settings row — turning it back off
>   happens in Health, not here.
> * **Read Active Energy in the workout interval; workouts still go out only.**
>   `NSHealthShareUsageDescription` is present and the read set is that one type.
>   The query exists so a Watch that was already recording can be associated with
>   our entry rather than doubled by our estimate. Asking to read anything we do
>   not query is a permission prompt that cannot be honestly explained.
> * **`HKWorkoutBuilder`, not `HKWorkout(activityType:start:end:)`.** Every one of those
>   initialisers is `API_DEPRECATED("Use HKWorkoutBuilder", ios(8.0, 17.0))` — read out of
>   `HKWorkout.h` in the SDK rather than recalled.
> * **Eligibility mirrors `PushFilter.shouldPush(_ workout:)`** and a test asserts the two agree. If
>   they diverge, the app is telling Health something different from what it tells its own server.

> ✅ **ENERGY SHIPPED 2026-08-19 — the client half of `workout_calorie_rate` is built and the
> setting is reachable.** `WorkoutCalorieRate` (five cases, the server's five values), the field on
> `AppSettings` with the server's own `medium` default, the wire row / mapper / apply, the picker
> under Settings → Apple Health, and an `activeEnergyBurned` sample attached to the
> `HKWorkoutBuilder`. **What is NOT verified is the number** — see the double-counting warning
> below, which is a fact about Apple's ring merging and cannot be tested anywhere but a phone.
>
> **Two implementation facts worth not re-deriving:**
>
> * **Energy is a SECOND write permission, asked for in the same prompt.** `activeEnergyBurned` is
>   authorized separately from workouts and can be switched off separately in Health, so both
>   statuses are checked before writing — and energy is SKIPPED rather than allowed to throw.
>   Adding a sample the app may not share makes `finishWorkout` throw, which would lose the WORKOUT
>   over a permission about its energy: trading a record for an estimate.
> * **`none` writes no sample at all, not a zero one**, and that is the one branch a rule written as
>   "multiply by the rate" gets silently wrong. `HealthWorkoutPlan.activeEnergyKilocalories` is
>   `Double?` for exactly that distinction.
>
> The design, unchanged from when it was decided: a FLAT RATE PER HOUR that the user picks — None / Low / Medium / High /
> Very High at 0 / 150 / 200 / 250 / 300 kcal per hour, Medium by default. No MET table, no
> bodyweight calculation, no reading Active Energy back out of HealthKit.
>
> **Why a user-chosen rate is not the fabricated number this project keeps refusing to write.** The
> objection to `0`, or to an invented MET estimate, is the app presenting a figure it did not
> measure as though it had. A rate the user selects is the opposite — the user saying "count my
> lifting at roughly this" — and the screen says exactly what it does. `none` stays first-class and
> is what the app did before.
>
> ⚠️ **UNVERIFIED ON DEVICE: whether attaching another source's samples actually
> works.** The decision and the HealthKit wiring are in; the fact is not. If
> `addSamples` of Watch energy throws, we fall back to the estimate. If the query
> returns empty (denied read looks identical), we keep the estimate. Check a real
> Watch-on session in Apple Fitness before trusting that the rings now show one
> number rather than two.
>
> **Watch samples are preferred over the estimate (HANDOFF.md item 1, wired
> 2026-08-19).** `HealthEnergyAction` / `energyAction` is the pure decision
> (Ringer, grok-4.6, first try); `HealthStore` queries `[start, end]`, attaches,
> or writes the estimate. Rate `none` still means no energy, even if samples
> exist. Intended behaviour: none → no energy; existing samples → attach those
> and skip the estimate; none found → keep the flat rate; attach throws → fall
> back to the estimate.

> **Two more corrections the reference screens forced, beyond energy:**
>
> 1. ✅ **Workouts toggle — landed 2026-08-19.** `writeWorkoutsToHealth` on
>    `AppSettings`, default on, synced. The Settings Apple Health row is a
>    switch when permission is granted, not a dead "On". HealthStore will not
>    write unless permitted AND switched on. `None` on the calorie rate still
>    turns off energy only.
> 2. ✅ **BACKFILL — landed 2026-08-19.** Yellow strip under Workouts when
>    permitted and switched on: `missingFromHealth` minus this app's
>    `HKMetadataKeyExternalUUID` values, `backfillPrompt` nil at 0.
>    Add writes through `writeWorkout`. A failed query hides the banner
>    rather than looking like "Health has none of ours".
> 3. ✅ **MEASUREMENTS BOTH WAYS — four types, 2026-08-19.** Mapping/echo/import
>    rule is `HealthMeasurementRule` (Ringer, grok-4.6, first try on mapping and
>    on import-plan + both banners). Weight, Body Fat %, Caloric Intake and
>    Waist write when permitted AND `writeMeasurementsToHealth` is on, and
>    import when permitted AND `readMeasurementsFromHealth` is on. Identity
>    of an inbound sample is `externalID ?? sampleID`. The other fourteen
>    types have no HealthKit type.

> ⚠️ **Bidirectional Health has one trap worth designing for up front: the echo loop.** Write a
> weight entry to HealthKit → Health notifies observers of new data → the app imports it back as
> a *new* entry → duplicate. The fix is the `source` field already in the data model: tag
> entries this app writes with its own HealthKit source identifier, and skip those on import.
> Get this right the first time — the failure mode is silent duplicate measurements that
> corrupt the time series, and it is unpleasant to clean up after the fact.

## Open questions

> ✅ **CUSTOM NUMBER KEYPAD — LANDED 2026-08-19 on the phone.** Chip + pinned keypad view, not a
> `UITextField` `inputView` and not `ToolbarItemGroup(placement: .keyboard)`. Facts from the
> reference: weight has a decimal (rest and reps do not); − / + steps 2.5 lb / 1 rep / 10 s
> (`WeightUnits.keypadStep`; metric is 1.25 kg); Next on reps ticks the set (non-last set starts
> rest and focuses the timer; last set of an exercise jumps to the next exercise's weight);
> Next on the timer skips rest. `markEdited` stays on the commit path; template reps keep the
> `6-8` hyphen range; first input after focus replaces. Two layout traps: Next must not take
> `maxHeight: .infinity` inside `safeAreaInset`, and the rest-bar focus ring is white on a
> clipped fill. Next work is Watch energy, not another keypad.


1. **Seeding the exercise library.** Need a source for the initial library. Licensing matters
   if illustrations are included.
2. **Edge Function transport fit.** Verify at Phase 3 that Supabase Edge Functions can serve
   the MCP transport; the spec moves, so check current docs rather than assuming.
