# Status

A living record of where the project actually is, and what is **deliberately** unfinished.

This is the one document that is expected to go stale, so it is deliberately narrow:

| Question | Where the answer lives |
|---|---|
| What changed, when, and why? | **git log** — commit messages carry the reasoning, not just the diff |
| Why is the schema shaped this way? | `01-data-model.md` |
| Why Supabase, how does sync work, what about observability? | `02-architecture.md` |
| What is the MCP tool contract? | `03-mcp-tools.md` |
| Why does the Postgres schema differ from the SwiftData one? | `05-database.md` |
| How does sync work on the client, and how is it made visible? | `06-sync.md` |
| Which worker models are good at what? | `~/ringer/docs/MODEL-NOTES.md` |
| **What is built, what is half-built, and what did we skip on purpose?** | **this file** |

Do not duplicate the other six here. If a design question is genuinely open, it belongs in
`01`/`02`/`03`/`05`/`06` under their Open questions sections, not in this list.

---

## Where the project is

**Phase 0 — complete.** A throwaway spike proved the transcript→template path works and, more
usefully, proved what it *loses*: every field the schema could not hold was a prescription field.
Findings are in `03-mcp-tools.md`; `spike/` is frozen and is not a starting point.

**Phase 1 — essentially complete.** `MCPStrength/` is a working offline iOS app: workout logging
with a live rest timer, templates with an editor and start-from-template, history with computed
volume and best set, an exercise library with alias/hint/spelling matching, seeded exercise and
measurement libraries, body measurements, a profile with an 8-week chart, a design token layer,
and a five-tab shell.

`02-architecture.md` defined Phase 1 as *"a working app you can train with, no backend."* That is
true today — with the standing caveat that it should **not** hold real training data until Phase 2
provides sync and backup, because a local-only store has no recovery story.

**Phase 2 — in progress. The transport is built and wired; nothing has been run against the real
project yet.**

> **START HERE IN A NEW SESSION.** The one-line state: the database is live, the app requires
> sign-in, deletes are soft, both mapping directions work, and **the transport now exists and is
> called** — claim → push → pull → report, triggered on launch, on foreground, and on finishing a
> workout. Every layer is covered by tests against a fake transport and a throwaway Postgres.
> **What has NOT happened is a single real round trip against `mcp-strength`.** No row has provably
> travelled; only that the code which would carry it passes its tests. The next thing worth doing
> is signing in on a simulator, logging one workout, and confirming the row appears in the project.

### Landed

- **The schema, on a real project.** Twelve tables, 18 RLS policies, 12 sync triggers, the seeded
  library, and now the last-write-wins guard (12 more triggers). **All 7 migrations applied and
  verified remote == local by dumping the schema back**, not by trusting `db push`.
  `05-database.md` is the decisions record; `./supabase/tests/run.sh` exercises it against a
  throwaway container.
  > **Two migrations had silently never been pushed**, and one of them was `workouts.summary` — a
  > column `SyncWorkoutRow` sends on every workout, so the first real push would have failed on an
  > unknown column. A note elsewhere claimed it was live. **Run `supabase migration list` before
  > trusting any statement about the remote schema, including one in this file.** "Applied"
  > written down is not the same as applied.
- **Sign-in, required up front.** Email/password via supabase-swift — the project's first external
  dependency. `AuthGate` replaces `ContentView` as the app root.
- **The sync design** (`06-sync.md`) and the sync columns on all eleven `@Model`s.
- **Soft deletes, everywhere.** 5 delete sites, 10 `@Query` filters, ~20 relationship reads via
  `live…` accessors.
- **The engine's decisions and its visible state** — order, cursor, conflicts, `PushFilter`, and
  the per-account `SyncStatus`. The Profile tab says "Not backed up yet", truthfully.
- **Both mapping directions.** `SyncRowMapper` (model → row) and `SyncRowApply` (row → model),
  the latter built by a Ringer worker and reviewed here.
- **THE TRANSPORT, and the loop that drives it.** `SyncClient.swift` is the network layer behind a
  protocol — behind one deliberately, because an engine reachable only through a live project and a
  real account is an engine nobody tests. `SyncEngine.swift` is claim → push → pull → report. It
  calls the existing pure rules rather than re-deriving them (`SyncEntity`, `SyncCursor`,
  `PushFilter`, `ConflictResolver`, both mappers). Triggered on launch, on foreground, and on
  finishing a workout — that third one matters most, because finishing is the only moment a workout
  becomes eligible to push at all.
- **Last-write-wins, actually enforced.** A `BEFORE UPDATE` trigger refuses a stale write
  (`20260816140000_last_write_wins.sql`, 15 assertions across two tables), and the engine carries
  what was true before its own push into the pull so the client resolver stops being lied to. Both
  halves are argued in `06-sync.md` § Conflicts.
- **`markEdited` at every mutation site**, and **template saves diff instead of rebuilding**. Both
  were open traps in this document; see the trap list below for what they were and why the shapes
  are worth remembering.
- **Finishing discards unticked sets**, and **unfinished workouts are ineligible to push** — see
  the decisions below.
- **The per-exercise options menu**, one shared component with two callers, six of eight items.
- **UI preview mode** — see below. This is the single most useful thing to know about.

### THE LOOP THAT WAS MISSING FOR A DAY: seeing the app

```
xcrun simctl launch <device> us.aiagent4.MCPStrength \
  -uiPreview 1 -uiPreviewFixtures 1 -uiPreviewTab history|profile|start|exercises|measure
```

Sign-in blocks every screen, so screens were built blind for a day. `Auth/UIPreviewMode.swift`
skips the GATE (not authentication — there is no session, RLS would still reject everything)
behind two independent gates: `#if DEBUG` so it cannot exist in a Release build, and an explicit
launch argument so it is off even in Debug. `-uiPreviewTab` exists because **the simulator MCP's
tap action crash-loops** — do not build a workflow on coordinate taps.

It found a real bug in its first minute: bodyweight exercises were silently dropped from history
cards, because "best set" required both weight and reps. Three sets of pull-ups logged, not
mentioned in the summary. That bug survived ~295 tests. **Use this before believing any UI is
right.**

### What is left, in order

1. **ONE REAL ROUND TRIP.** Sign in on a simulator, log a workout, and confirm the rows land in
   `mcp-strength`. Everything below the network is tested; the network itself has only ever talked
   to a fake. Until this happens the honest claim is "it should work", and the whole point of this
   document is not to make claims like that. Watch specifically for: the claim step on a store that
   predates the sign-in gate, RLS rejecting a row the client thought it owned, and enum or date
   encodings that the fake accepted and Postgres will not.
2. **A settings model**, which unblocks the two missing menu items. Decisions already made: the
   warm-up calculator is a **single global auto-generated config the user can then edit**,
   generating **3 sets at percentages**, rounded to the **nearest 5 lb**. `Preferences` needs a
   model for `exercise_preferences`, which exists as a table with no SwiftData model.
3. **Canonical units**, before there is real history (`05`).

### Traps around the transport

The first three were open warnings until the transport landed and are now **closed**. They are kept
here, briefly, because each one is a shape that will recur and the reasoning is the reusable part.

- **Pull on `server_updated_at` with a five-second overlap window, never on `updated_at`** (`05`).
  Still true, and still the single most consequential line in the pull.
- **CLOSED — `markEdited` at every mutation site.** It used to cover only EXERCISE-level edits on
  the active-workout path. Every set-level write (weight, reps, RPE, set type, the completion
  tick), the reorder loops, and the whole templates tab (folder and template renames, moving a
  template between folders, collapse) marked nothing. Harmless only while nothing cleared the flag.
  Closed in `f0d3274`, deliberately *before* the transport: shipping the engine first would have
  written the bug and its fix into two sessions with a window between them where the app claimed
  your data was backed up and it was not. **The shape to remember:** creating and deleting were
  always covered (`needsSync` defaults to `true`; `markDeleted` sets it), so the hole was only ever
  *edits to rows that already exist* — which is exactly the class a green test suite does not
  notice.
- **CLOSED — `TemplateEditorScreen.save()` rebuilt the whole subtree on every save**, which would
  have told the server every exercise and set was deleted and recreated on each edit. The root
  cause was identity, not the write: `loadDraft` minted a fresh `UUID()` for drafts hydrated from
  existing rows, so a diff was impossible by construction. Fixed in `c0fd5ed`; the rule is a pure
  function in `Workout/TemplateSaveDiff.swift` and the load-bearing test is that an unchanged save
  produces no insertions and no tombstones.
- **CLOSED, and it was a design gap rather than a coding one — nothing enforced last-write-wins.**
  The server overwrote unconditionally, so a stale device destroyed a newer edit made elsewhere;
  and the client's resolver could never see a dirty row because push runs first and clears the flag
  before pull reads it. Both halves are fixed (`72dbcb2`, `e84d3b3`) and the reasoning lives in
  `06-sync.md` § Conflicts. **The shape to remember:** the contract was written in a design doc,
  implemented correctly on one side, and enforced nowhere — and it took building the caller to
  notice. Two tests could not be made to pass, and that was the only symptom.
- **Rows created before sign-in have no owner.** New installs cannot produce any; the store on this
  machine predates the gate.
- **The seeded library exists twice** — local rows and global Postgres rows sharing baked UUIDs.
  `PushFilter` already excludes them; do not undo that.
- **Give any Ringer task whose check compiles a `check_timeout_s`.** The check budget used to be a
  hard-coded 60s, which the ~36s compile check fitted only while nothing else was building — so a
  concurrent `xcodebuild` pushed it over and the *model* was recorded as failing. It is now a
  per-task manifest field (default still 60). Set it to ~300 on compile checks. Raising it removes
  the false failure, **not** the contention: two compiles still slow each other down.

### Decisions made this session, with their reasoning

- **Finishing a workout discards unticked sets** and removes exercises left with nothing. A workout
  records what you DID. It is a REAL delete, not a tombstone — tombstoning to avoid storing
  unnecessary data stores the unnecessary data.
- **Unfinished workouts, and everything under them, are ineligible to push.** This is what makes
  that hard delete safe, and it is enforced by `PushFilter` rather than by scheduling sync
  carefully. A rule that cannot be violated beats one you have to remember. Live session mirroring
  to a Watch is a different transport (Bluetooth) and does not belong on the Postgres path.
- **`Workout.note` and `Workout.summary` are different fields.** `note` is instructions going IN
  (from the plan or the MCP server, and now copied from the template at start); `summary` is the
  user's feedback coming OUT. Collapsing them would leave an AI unable to tell its own instruction
  from the user's report of how it went — which is what distinguishes a bad night from a downward
  trend.
- **Notes are a two-way coaching channel**, not metadata. Recorded as an explicit MCP contract
  requirement in `03-mcp-tools.md`: the read tools must RETURN them.
- **Note display truncates** at 200 characters for a session note, 100 for an exercise note, at a
  word boundary, tap to expand. Short notes are not tappable at all.
- **Replace Exercise keeps the sets** ("different machine", not "start over"). **Create Superset
  pairs with the exercise above** — round-robin in list order needs no second selection UI.

### Working with Ringer on this project

The routing rule is about COST, not capability: Ringer offloads grunt work to cheaper models under
supervision. Mechanical, checkable work (batches of similar edits, replicating an existing pattern)
goes to a worker; **visual work does not** — a check cannot assert whether something looks right.
Run area: `~/ringer/run-areas/mcpstrength-rowapply/` is the worked example, with a `verify_compile.sh`
that now knows about SPM dependencies. **Ringer scores the CHECK's exit code**, so an
orchestrator-side check bug is recorded as a model failure; one such misattribution is annotated in
ringer `docs/MODEL-NOTES.md`.

### Not verified

- **THE TRANSPORT HAS NEVER TALKED TO THE REAL PROJECT.** Every layer under it is tested — the
  engine against a fake, the schema and the LWW guard against a throwaway Postgres — and the two
  suites are green. But a fake accepts what Postgres might reject, so nothing here is evidence that
  a row actually travels. This is the top of the "what is left" list for a reason.
- **The second-account refusal has never been exercised, and DELIBERATELY STAYS AS IT IS.** The
  engine records which account claimed this device, and if a DIFFERENT one signs in it refuses to
  push and reports it. That guard is load-bearing — local rows carry no owner (ownership is stamped
  at push time), so without it a second person signing in would upload the first person's entire
  history into their account.
  > **Reviewed 2026-08-16 and left alone, because the state is nearly unreachable.** Sign-in is
  > required before any row exists, so only this dev machine has owner-less rows. A mistyped signup
  > email cannot produce it either: no confirmation mail arrives, so that account never signs in at
  > all. What remains is Drake with a test account, which self-heals by signing back in. The
  > message being a dead end is therefore not worth fixing yet.
  >
  > **REVISIT THIS WHEN SIGN IN WITH APPLE/GOOGLE LANDS.** Social sign-in has no email
  > verification step, so a user who already has an email account and then taps "Sign in with
  > Apple" is signed in INSTANTLY as a second account on the same phone — the one path that makes
  > this state genuinely reachable. It is the same fix as the identity-linking note below, not a
  > separate one.
- The per-exercise menu, sticky notes and truncation limits have not been used on a real device.
- **The tappable rest divider has not been used on a real device either.** A hairline is far under
  the 44pt minimum target, so the hit area is expanded and then negated out of layout
  (`RestDivider`) — the divider should look unchanged and be comfortably tappable. Both halves of
  that are worth confirming with a thumb, and the template editor and live workout screen are still
  the two screens nothing has ever visually verified.
- Creating an account, the confirmation email, and password reset — **email confirmation is
  currently DISABLED on the project** because the confirmation link pointed at `localhost:3000`.
  Must be re-enabled before launch, together with deep links.

> **When Apple/Google/Facebook sign-in is added, LINK the identity to the existing account.** Drake
> intends to offer all three, which makes Sign in with Apple mandatory rather than optional (Apple
> requires it only once a third-party login is offered — email/password alone does not trigger it).
> A new provider treated as a fresh sign-up gives the user a second, empty account and their history
> appears to have vanished.

**Phases 3–4 — not started.** The real multi-user MCP server, then product.

---

## Deliberately deferred

These are not oversights. Each was cut with a reason, and the reason is the point.

| Deferred | Why |
|---|---|
| **Program UI** (rotation view, "what's next") | Post-launch. Not critical to the app succeeding, and with no plan to train on a half-built app, shipping it early teaches nothing. **The schema still landed in Phase 1** — see the note below. |
| **Personal records / PR counts** | Real feature (compare against all prior history, per exercise, per rep count). Nothing computes them, and a hardcoded "0 PRs" reads as *you set no records* rather than *not implemented*. |
| **Apple Health sync** | Phase 2. `02` decides it is bidirectional and flags an echo-loop trap; doing it half-way is worse than not doing it. The reference's "enable Health" hint is deliberately absent — it would point at a setting that does not exist. |
| **Progression rules beyond linear** | One structured rule (hit all reps → add X) covers most intermediate programs. Percentage-of-training-max, RPE autoregulation and waves turn a field into a small programming language. |
| **RIR** | Same information as RPE on an inverted scale. One scale is easier to coach against than two. |
| **Supersets, plate calculator, exercise artwork, per-exercise overflow menus, calendar view, widget dashboard, accounts/avatars** | Scope. None block the core loop. |

> **The Program schema is the exception worth watching.** Its UI is post-launch, but
> `TemplateFolder.kind` / `ProgramDay` / `cursor` / `totalCycles` shipped in Phase 1 on purpose.
> Because the UI comes *after* launch, letting the schema slide with it would mean adding a table
> to a database that already holds real training history. Additive-by-construction only helps if
> the columns exist before there are users.

---

## Known loose ends

Small, none blocking, roughly in the order I would do them.

- **Create Superset sets the data and draws nothing.** Both screens write `supersetGroupID`
  correctly (and the workout screen marks the rows dirty), but no view reads it except the menu
  label, which flips to "Leave Superset". So the user taps Create Superset and sees one word change
  somewhere they are not looking. Note that **supersets are in the Deliberately deferred table
  below** — the action shipped anyway, which is how the two halves came apart. It does NOT heal
  itself when the transport lands: the grouping will travel to the server, but nothing on either
  screen will draw it. Resolve it by designing the grouping and building it, or by removing the
  menu item until then — the same choice Archive is waiting on, and for the same reason.

> **Archive and Share are deliberately absent from the template menu.** The reference has both.
> Archive has no schema *and no designed behaviour* — does it hide the row, where do you
> unarchive, does it affect history? The Program schema precedent does **not** license adding a
> column here: that shipped early because its design was settled and only its UI was deferred.
> Design it, then build it. Share is out of scope.

> **Exercises can be reordered inside a workout by dragging the title**, and every exercise
> collapses to its title row while the drag is active — a workout is taller than the screen, so
> without collapsing you cannot reach an exercise two screens away. The list-move rule is shared
> with the template grid as `ListOrdering`.

> **Templates can be dragged between folders and reordered within one.** `Template.order` now
> means position within its folder rather than a global rank — documented at the declaration,
> no migration needed because the views already sorted per-folder. `TemplateOrdering` owns the
> move rule as a pure function, and cards are themselves drop targets so the insertion index
> never has to be computed from a drop point. Folders do NOT collapse during a drag.

> **`BodyPart` / `ExerciseCategory` labels live in one file** (`Design/EnumLabels.swift`), not
> duplicated per screen. They stay in the view layer deliberately — presentation, not model.

> **The template overview sheet is done, and the play button is gone.** Tapping a card opens an
> overview (name, Last Performed, `3 × Exercise` rows, full-width Start Workout) with Edit as a
> nested sheet it owns. The card carried a play button only because this screen did not exist;
> removing it also gave the card title back the width the type-size change was working around.

> **Measurement ordering, seed placement, and the Previous-column set-type annotation are done.**
> Measurements sort anatomically from a seeded `sortOrder`; both seed importers now live in
> `MCPStrengthApp` but stay independent; a prior drop set reads `75 lb × 11 (D)`.

> **Set-type editing, folder lifecycle, and the per-template menu are all done.** Set types are
> editable from the badge and working-set numbering excludes lettered sets. Folders can be
> created, renamed, deleted, collapsed, and filled via Add Template; deleting one keeps its
> templates and unfiles them. Templates can now be renamed, duplicated, and — for the first
> time — **deleted**, and deleting one keeps every workout performed from it.

> **Lesson from the folder work, worth not relearning.** `Add Template` shipped through a green
> structural check and 125 green tests while filing nothing, because `.sheet(isPresented:)` reads
> companion `@State` that is lost when written from inside a `Menu` action. Two things hid it: a
> check can only assert structure, not presentation-state timing; and the delete test asserted
> `folder == nil` *after* deleting without asserting it was set *before*, so it passed vacuously.
> **Prefer `.sheet(item:)` whenever a sheet needs a value**, and when a test asserts something
> becomes nil, assert it was non-nil first.

---

## Lessons worth not relearning

- **Every `@Model` property needs a declaration-level default or optionality — `var x: Int = 0`,
  not a default in `init`.** SwiftData's lightweight migration cannot see initializer defaults, so
  adding `var sortOrder: Int` made `ModelContainer(for:)` throw when opening a store written
  before the property existed, and the app died on launch. **Unit tests cannot catch this by
  construction**: they build in-memory containers from the *current* schema, so there is never an
  old store to migrate. Only launching the app against a previous build's store exposes it, which
  is what the two UI tests are actually for. Cheap now; a broken-on-update app once Phase 2 gives
  real users real history.
  - **How to actually verify one — the canary.** Back up the simulator's store, confirm with
    `PRAGMA table_info` that it lacks the new columns, then plant a value re-seeding is
    contractually required to preserve (a `notes` on a seeded exercise). Install the new build
    over it and launch. **Row counts prove nothing**: a fresh store also ends up with 25 exercises
    carrying the same seeded UUIDs, so only the canary distinguishes "migrated the old store" from
    "silently started over". Watch for `simctl install` relocating the data container — the first
    attempt at this was inconclusive because the store being inspected was not provably the old
    one. The sync-column commit (`d49d75e`) is the worked example.
- **Look at the running app.** Three bugs passed a green test suite and were caught only by
  launching it: a seed importer that nothing ever called, a navigation title rendering black on a
  dark background (system chrome does not read our tokens), and `totalVolume` that nothing computed
  — every history card would have shipped reading `0 lb`.
- **Never display a fabricated zero.** "0 PRs", "0 inches" for an unmeasured body part, or a
  weekly chart that silently drops empty weeks all read as *data* rather than *absence*. Show
  nothing instead.
- **Black-box first, then read the source.** Driving a tool surface as a client shows where a
  caller trips; only the source tells you whether the cause was a schema gap or a description gap.
  They look identical from outside and have completely different fixes.
- **Never classify an error by `String(describing:)`.** `AuthErrorPresenter` detected a lost
  connection by scanning for "network" / "offline" / "timed out", and that branch could never fire:
  a `URLError` stringifies to `URLError(_nsError: Error Domain=NSURLErrorDomain Code=-1009 "(null)")`
  and contains none of those words. Every offline user would have been told "something went wrong" —
  useless *and* false, since nothing was lost. Match on the TYPE (`error as? URLError`, then the
  code), and keep string matching only as a backstop for errors a library has wrapped. The same trap
  is waiting in the sync engine, which has far more error paths than sign-in does.
- **A dependency's behaviour is a fact to look up, not to assume.** Where supabase-swift persists
  the session (keychain, not UserDefaults) and what `signUp` returns when confirmation is pending
  (a user, no session) were both read out of the checked-out source. The second one decides whether
  a successful sign-up shows a "check your email" screen or silently returns you to an empty form.
