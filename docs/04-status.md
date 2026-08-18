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

**Phase 2 — in progress. Sync is PROVEN against the real project, and storage is canonical
kilograms.** What remains is per-exercise Preferences, the settings screen, syncing `AppSettings`,
and Apple Health.

> **The settings model that used to be item 2 on this list no longer exists as a requirement.** It
> was there to hold editable warm-up percentages — and the reference app offers no way to adjust
> them at all. You generate the sets and then edit the SETS. The ramp is hard-coded in
> `Workout/WarmupSets.swift` and the whole model evaporated. Worth remembering as a shape: a
> requirement inherited from "surely the reference app has a screen for this" that it does not have.

> **START HERE IN A NEW SESSION.** The one-line state: **sync works end to end against the real
> project, and every stored weight is now KILOGRAMS.** A workout logged on a simulator (Bench Press
> 135×5) reached `mcp-strength` with its exercise and set, correctly owned; 43 global library rows
> came down the other way; the cursor advances; the seeded library stays global. Read out of the
> database, not inferred from the UI.
>
> **The round trip found four real bugs that 350 green tests did not**, which is the single most
> useful thing this document can tell you — see "What running it for real found" below.
>
> **The bar on logging real workouts is LIFTED.** It existed only until the units conversion landed,
> and it has: nothing about the local store is waiting on a migration any more. What is still true
> is that there is **no App Store Connect app record**, so the build cannot be uploaded — see
> "Shipping to a device".
>
> ⚠️ **One ordering rule survives, and only for the live project.** Migration
> `20260818120000_weights_to_kilograms.sql` must be applied BEFORE a build of this client runs
> against `mcp-strength`. Run `supabase migration list` and check it is there. The client converts
> its own store without dirtying rows, so it will not re-push what it converted — except rows that
> were ALREADY dirty, which push kilograms. A server that has not converted yet would halve those.

### Landed

- **The schema, on a real project.** Twelve tables, 18 RLS policies, 12 sync triggers, the seeded
  library, and now the last-write-wins guard (12 more triggers). **All 8 migrations applied and
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
- **The per-exercise options menu**, one shared component with two callers, SEVEN of eight items.
  `Add Warm-up Sets` landed once the settings model it was blocked on turned out not to be needed;
  only Preferences is still absent, waiting on the `ExercisePreference` split.
- **The warm-up ramp** (`Workout/WarmupSets.swift`), wired into both screens. Percentages are
  MEASURED from the reference app, not chosen, and bar weight floors it so it cannot propose a load
  lighter than the bar. **Now watched running on a screen**, which is where the Previous-column bug
  below came from — see "What looking at the warm-up ramp found".
- **Bar types carry a weight PER UNIT** (`BarType.weight(in:)`), and a `hammerStrength` exercise
  category exists in the app and in the live database.
- **CANONICAL KILOGRAMS, both halves, in one change.** `AppSettings` and `WeightUnits` landed first
  with nothing wired to them; this closed it. Every read and write of a weight now goes through
  `WeightUnits` — the entry chips, `PreviousText`, history volume and best set, `OneRepMax`, the
  warm-up ramp — and the pounds already stored were converted on both sides:
  `WeightUnitMigration` on the client and migration `0009` in Postgres.
  > **The local conversion is guarded by a marker IN THE STORE** (`StoreMigrations`), not in
  > UserDefaults and not on `AppSettings`. Not UserDefaults because this project swaps store files
  > around to test SwiftData migrations, and a defaults dictionary that says "converted" over a
  > restored older store is the silent halving the guard exists to prevent. Not `AppSettings`
  > because that is about to become a synced table keyed by `user_id`, and a second device pulling
  > `didConvert = true` would skip its own conversion. Off `Syncable` makes that structural rather
  > than a comment somebody has to honour.
  > **The rows and the marker are written in ONE save**, so a crash between them cannot produce a
  > converted store that is marked unconverted.
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

### What running it for real found

**Four bugs in about an hour, none of which the suite could see.** Kept because the *reasons* they
were invisible recur, and because together they are the argument for doing this before shipping
anything else.

| Bug | Why no test could catch it |
|---|---|
| `workouts.summary` missing from the live database — the migration existed locally and had never been pushed, and every workout push sends that column | Tests build their Postgres from the local migration files, so the schema is correct there **by construction** |
| All 18 seeded measurement types rejected with RLS `42501`, aborting the entire run — push stopped, so the pull never happened, and every later sync failed identically | The fake transport accepts anything. Only a real policy refuses |
| Infinite recursion in `PushFilter` — introduced while fixing the above; compiled clean, killed the app on launch, and crashed the **test host** so the suite reported `0 passed, 1 failed` | A compile cannot see it, and the crash prevented the very test written to catch it from running |
| Rows created but never edited pushed with `updated_at = 0001-01-01`, so they lose every conflict forever | Visible only in the stored data. The local model looks fine |

> **`0 passed, 1 failed` is not one broken test.** It means the host crashed before bootstrapping
> and NOTHING was verified. It looks like a trivial failure and is the most serious one there is.

> **One row on the server still reads `0001-01-01`** — the workout_exercise pushed before the
> backfill landed. Harmless (it is test data on a project with no users) and left as the before/after
> evidence, but a store that already pushed such rows will not re-push them, because they are clean.

### What looking at the warm-up ramp found

**One bug, and the tooling needed to see it at all.** Both are worth keeping: the bug is a shape,
and the tooling replaces a workflow that no longer works.

**The bug: the Previous column moved onto the warm-ups.** `Previous` tells you what you lifted for
that set last time, and it matched last time's sets to today's rows by RAW LIST POSITION. Warm-ups
are inserted at the TOP, so generating a ramp shifted every row down one slot: `135 lb × 5` ended up
displayed against a 45 lb warm-up, and the working set — now row 4, where last time had no row 4 —
showed "—". The number you need in order to pick today's load was simultaneously missing from the
row that needs it and misleading on a row the app filled in for you.

Fixed by counting **within a KIND** on both sides — warm-ups match warm-ups, everything else
matches the working sequence: `SetNumbering.positionsWithinKind` on the display side, a filter in
`WorkoutHistory.previousSet` on the history side. Both halves have to agree or the column just lies
differently.

> **This was decided twice, and the second answer came from the reference.** The first fix showed
> "—" on every warm-up row, on the reasoning that the app picks warm-up loads from the working
> weight so it has nothing to report. Then `Workout screen/editing weight by plate.PNG` turned out
> to show the reference app doing the opposite — `90 lb × 10 (W)` and `140 lb × 5 (W)` against its
> warm-up rows. Drake chose to match it. **Check the reference before diverging from it**, which is
> already a rule in `AGENTS.md` and was not followed here until after the fact.

> **The shape to remember: two rules that walk the same list and do different things.** Working-set
> numbering skips every lettered type and returns nil for it, because a drop set is not "set 3".
> Previous skips nothing and gives warm-ups their own sequence, because a drop set IS a performance
> at that point and a warm-up is a warm-up. They look like the same rule and a later tidy-up would
> collapse them; `numberingAndPreviousPositionsDisagreeOnDropSets` exists to fail when somebody does.

**Why no test saw it.** Both halves were internally consistent and agreed with each other — they
just pointed at the wrong row. Every existing test used a set list with no warm-ups in it, where
raw position and working position are the same number. The feature that broke the assumption is the
feature that generates warm-ups, and it was tested for what it inserts, not for what it displaces.

**The second bug, found while proving the first fix: the preview fixtures were wired to the wrong
exercises.** `UIPreviewFixtures` looked its exercises up with `localizedCaseInsensitiveContains`
over a fetch with no sort descriptor, so it got whichever matching row SwiftData handed back first.
`"Bench Press"` matched **Incline Bench Press (Dumbbell)** and `"Pull Up"` matched **Assisted Pull
Up** — so the block explicitly commented as "a loaded barbell movement", carrying 95 lb and 135 lb
warm-ups and 185 lb working sets, hung off a dumbbell incline press. Nothing failed and nothing
looked broken; the numbers were simply nonsense, **in the one tool this project uses to judge
whether a screen is right.** Now an exact full-name match, and a miss trips an assertion instead of
silently skipping the block.

> **The fixtures are idempotent on a marker workout named "Preview Session", so an existing
> simulator store keeps the OLD, wrongly-wired data.** Delete that workout, or use a device with no
> store, to see the corrected fixtures. This was verified on a fresh `iPhone 17 Pro` rather than by
> erasing the iPhone 17's store.

**The tooling: `WarmupRampWalkthroughTests`.** The documented way to drive the simulator —
computer-use taps on the Simulator window — **no longer works.** The clicks land (macOS hit-testing
puts them on the Simulator window, and keyboard shortcuts to the app still work) but they never
become touches in the device. Quitting the overlay apps named in HANDOFF.md changed nothing. The
iOS Simulator MCP is still crash-looping.

So the walkthrough is an XCUITest instead: it starts an empty workout, adds Bench Press, types a
working weight, opens the `⋯` menu, taps `Add Warm-up Sets` three times under different conditions,
and attaches a screenshot at each step. A second test does the same against history that CONTAINS
warm-ups, which only the fixtures can produce. Both assert almost nothing on purpose — **they are
cameras, not tests.** Extract the pictures and look at them:

```
xcodebuild test -project MCPStrength/MCPStrength.xcodeproj -scheme MCPStrength \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath DerivedData \
  -only-testing:MCPStrengthUITests/WarmupRampWalkthroughTests -resultBundlePath /tmp/walk.xcresult
xcrun xcresulttool export attachments --path /tmp/walk.xcresult \
  --test-id "WarmupRampWalkthroughTests/testWalkAddWarmupSetsAndPhotographIt()" --output-path /tmp/shots
```

Two failures of the harness itself are worth knowing, because both produced a screenshot that looked
completely plausible and was of the wrong thing. It addressed the weight field by absolute index,
which silently became a WARM-UP's field the moment warm-ups existed; and tapping the middle of a
right-aligned entry chip puts the caret BEFORE the text, so the backspaces deleted nothing and "135"
was typed in front of "90" — the ramp was then correctly generated from 13590 lb. **A screenshot is
only evidence if you know what produced it**, which is the same trap as reading a hand-edited ramp
as a generated one.

### What is left, in order

1. **Per-exercise Preferences.** Design decided and approved: `docs/06-sync.md` § "Per-exercise
   preferences get their own local model". The sheet is two rows — Weight Unit and Bar Type — not
   four; `focusMetric` and `notes` are not edited there. The *Default* option in its weight-unit row
   now has something to defer to.
   > **The display side is already built and is waiting for it.** Every screen resolves its unit
   > through `WeightUnits.displayUnit(override:global:)` and passes `exercise.weightUnitOverride`
   > as the override — which is always nil, because nothing writes it. When the four fields move to
   > `ExercisePreference`, the change is what those four call sites PASS, not a hunt for screens
   > that resolved the unit their own way. They are: `ExerciseBlock.displayUnit` (workout screen),
   > `TemplateEditorScreen.displayUnit(for:)`, `ExerciseDetailBlock.displayUnit` (history detail),
   > and the best-set row in `WorkoutHistoryCard`.
2. **Settings screen, units rows only**, off the profile page — reference screenshots are in
   `Settings accessed from profile page/`. This is what makes canonical storage visible: without it
   nobody can change the unit, **so the conversion is still only ever exercised in one direction.**
   Every weight is stored in kilograms today and every screen renders pounds; the kg path is covered
   by tests and has never been seen on a screen. `SetRow` already reacts to a unit change
   (`.onChange(of: unit)`), and this screen is what proves that works.
3. **Sync `AppSettings`.** It carries the sync columns and deliberately does NOT conform to
   `Syncable` — there is no Postgres table yet (`05-database.md`). One row per user means the key is
   `user_id`, which is the same per-entity conflict-target work `06-sync.md` specifies for
   `exercise_preferences`; do it once for both.
   > **`StoreMigrations` must NOT be swept up in this.** It sits next to `AppSettings` and looks
   > like more of the same. It is the opposite: a device-local record of which data migrations this
   > STORE has run. Syncing it would let one device tell another that its weights are already
   > converted.
4. **Apple Health.** The last item in Phase 2, and no longer blocked — see the signing note below.

> **`Add Warm-up Sets` has now been looked at and is off this list.** It found one real bug, which
> is recorded below rather than here because the shape of it is the reusable part.

### Shipping to a device — the account side is DONE

**The Apple Developer Program is active** (team `ZD2SRFJUPS`, enrolled as an Individual, renewing
2026-08-16), and the whole path to a distributable build is proven: `xcodebuild archive` then
`-exportArchive` with `method: app-store-connect` produces an `.ipa` signed
`Apple Distribution: DRAKE PHILIP SCIFERS (ZD2SRFJUPS)` carrying a Store provisioning profile, and
it passes Apple's `-validate-for-store` on the way through. `DEVELOPMENT_TEAM` is pinned in the
project because the machine knows two teams and automatic signing was otherwise free to guess.

This unblocks **Apple Health** — HealthKit is a restricted capability Apple does not grant free
accounts at all — and **Sign in with Apple**, which is paid-only and carries the identity-linking
work already flagged under "Not verified".

What is NOT done: **no app record exists in App Store Connect**, so nothing can actually be
uploaded yet. That record is Drake's to create (name, bundle id `us.aiagent4.MCPStrength`, SKU).

> **Two hours went into diagnosing this and the diagnosis was wrong twice**, so the reusable part is
> how to read the output rather than the conclusion:
>
> * **`security find-identity` prints the certificate's COMMON NAME, and for an Apple Development
>   certificate the value in parentheses is not the team.** `Apple Development: … (8THV5TS24T)` has
>   `OU=ZD2SRFJUPS` — the parenthetical is the developer's personal id, stable across teams. Read
>   the `OU` field (`openssl x509 -noout -subject`), never the display name.
> * **A 7-day provisioning profile does not prove a free account.** Xcode issues one under
>   free-provisioning rules whenever it has not yet refreshed membership status, and stamps it with
>   the paid team anyway. The tell that the membership is live is a profile expiring in a YEAR.
> * **Certificates and provisioning profiles are different objects and the words blur.** The
>   certificate is the identity; the profile is the permit naming an app id, the certificates it
>   trusts, and where it may run. Every failure here was a stale PROFILE while the certificates were
>   fine, and "doesn't include signing certificate" means that literally — the profile predates the
>   certificate — rather than indicating a team mismatch.
>
> Apple limits quoted from memory were wrong too (a third Apple Development certificate was created
> without complaint after "two is the cap"). Check the portal rather than trusting a recalled limit.

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

- **Sync itself is now VERIFIED against the real project** (see above), so it has moved off this
  list. What remains unverified there: a SECOND device pulling the first one's data, anything
  involving a genuine conflict between two devices, and a push large enough to page.
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
  that still want a thumb; a walkthrough test can photograph the divider but cannot judge whether it
  is comfortable to hit.
- **The live workout screen has now been SEEN** — the set list, the `⋯` menu, the rest dividers and
  the warm-up ramp are all in the walkthrough's screenshots. **The template editor still has not
  been**, and it is now the last completely unseen screen. `WarmupRampWalkthroughTests` is the
  worked example of how to photograph it; the editor's own `Add Warm-up Sets` path is the obvious
  thing to point it at next, since that half of the wiring has still only been reasoned about.
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
