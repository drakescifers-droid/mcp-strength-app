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

> ⚠️ **Bidirectional Health has one trap worth designing for up front: the echo loop.** Write a
> weight entry to HealthKit → Health notifies observers of new data → the app imports it back as
> a *new* entry → duplicate. The fix is the `source` field already in the data model: tag
> entries this app writes with its own HealthKit source identifier, and skip those on import.
> Get this right the first time — the failure mode is silent duplicate measurements that
> corrupt the time series, and it is unpleasant to clean up after the fact.

## Open questions

1. **Seeding the exercise library.** Need a source for the initial library. Licensing matters
   if illustrations are included.
2. **Edge Function transport fit.** Verify at Phase 3 that Supabase Edge Functions can serve
   the MCP transport; the spec moves, so check current docs rather than assuming.
