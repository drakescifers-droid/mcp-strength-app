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

**Phase 2 — in progress. Sync is PROVEN against the real project, storage is canonical
kilograms, per-exercise Preferences is DONE, the units setting is REACHABLE, both of them SYNC,
Apple Health writes workouts when the in-app toggle is on, prefers Watch Active Energy when it
exists, falls back to the flat-rate estimate, offers backfill for sessions Health never got,
writes the four HealthKit measurement types and can import them back (banners + Add),
and the custom number keypad is ON THE PHONE.**
**Phase 3 has started.** The MCP Edge Function, `list_exercises`, and
`create_exercise` landed 2026-08-19. Consent lives on **mcpstrength.com**
(site in `web/`, Cloudflare Pages), not on the Edge Function — hosted
`*.supabase.co` will not serve HTML. The site is live at
https://mcpstrength.com (and www). Site URL and `/oauth/consent` are set
on the live project. Claude's connector URL is **https://mcp.mcpstrength.com**.
`get_templates` and `get_template` landed 2026-08-19 (notes included, weights
in kg, `dropSet` not `drop_set`). `create_template` / `update_template` landed
the same day: all-or-nothing, lbs→kg, name collision returns the existing id,
notes + sticky notes. A later session (2026-08-19) added `secondaryBodyParts`
and unblocked `hammerStrength` in Swift — see landed bullets below.
`get_workout_history` / `get_exercise_progress` landed 2026-08-20: completed
sessions only, notes + summary + sticky notes, kilograms, `dropSet`.
`create_program` / `delete_program` / `delete_template` landed the same day:
soft deletes, UUID-only, repeating day slots, linear progression recorded
as prose and not executed. Remaining MCP tool: `log_workout`. GitHub is
`https://github.com/drakescifers-droid/mcp-strength-app`.
What remains of Phase 2 is proving Watch-attach on a real session — a gym
check, not a blocker.

> ⚠️ **THE CLAIM BELOW IS WRONG, AND THE SUB-SCREEN HAS NOW BEEN LOOKED AT.** It was used to
> delete a requirement. `Settings accessed from profile page/IMG_2990.PNG` has a
> **`Warm-up Calculator >`** row under LOG WORKOUT, and **`IMG_3002.PNG` IS that sub-screen** — it
> was in the captured set all along, unopened. It carries:
>
> * a **FORMULA** list — `Default` (40×5 / 60×5 / 80×3), `With Empty Bar`, `Alternative`, and
>   `Custom`, with `Default` ticked;
> * a **PLATE ROUNDING** list — `Loose` (10 kg or 20 lbs), `Normal` (5 kg or 10 lbs), `Strict`
>   (2.5 kg or 5 lbs), with `Strict` ticked.
>
> So the reference DOES let you adjust the ramp, with named presets rather than editable
> percentages, and the settings model that "evaporated" is a real deferred feature rather than a
> requirement that never existed. It is not scheduled; it is recorded so nobody deletes it twice.
> `WeightUnits.plateIncrement` (5 lb / 2.5 kg) is already the reference's `Strict`.
>
> ⚠️ **AND IT CAUGHT A REAL BUG: OUR RAMP PERCENTAGES WERE WRONG, AND THEY ARE NOW FIXED.**
> `WarmupSets.Ramp` ran at 50 / 60 / 75 where the reference's `Default` is **40 / 60 / 80**. The
> rep counts (5 / 5 / 3) were always right. **Corrected 2026-08-19 and confirmed against the
> reference app's own generated output**, not against its settings screen alone.
>
> **How it survived: it was FITTED TO ONE OBSERVATION, and both candidate formulas reproduce that
> observation.** The old percentages came from a 90 lb working set generating 45×5, 55×5, 70×3.
> 50 / 60 / 75 lands on 45 by arithmetic; 40 / 60 / 80 lands on it via the BAR FLOOR, which the
> reference applies too:
>
>     0.40 × 90 = 36  -> 35  -> raised to the 45 lb bar -> 45 × 5
>     0.60 × 90 = 54  -> 55                             -> 55 × 5
>     0.80 × 90 = 72  -> 70                             -> 70 × 3
>
> **They diverge everywhere else, and 135 lb is where it showed.** Ours proposed 70 / 80 / 100; the
> reference generates **55 × 5, 80 × 5, 110 × 3** — both ends wrong by 10 lb, middle step
> coincidentally identical. Read off the reference app on 2026-08-19, and it matches the
> Warm-up Calculator screen's stated `Default` exactly.
>
> **`WarmupSetsTests` now pins BOTH cases and says why neither may be deleted.** 90 lb alone is
> satisfiable by a formula that is wrong at every other weight; 135 lb alone does not exercise the
> floor.
>
> **Three shapes worth keeping, and the middle one is the expensive one:**
>
> 1. **A fit to a single observation is not a formula.** One data point and two unknowns (the
>    percentage, and whether the reference floors at the bar) has no unique solution. The comment
>    saying the numbers were "measured, not chosen" was TRUE and not the same as *correct*.
> 2. **A correction can over-correct.** The percentages originally in this file were 0.4 / 0.6 /
>    0.8 — right — with a first rep count of 10 — wrong. The fix moved all three percentages to
>    make one rep count fit. Changing what agrees with the evidence in order to explain what does
>    not is how a partly-wrong answer becomes a wholly-wrong one.
> 3. **"Whose output am I looking at" caught this project THREE times in one paragraph:** an edited
>    ramp read as a generated one, a screenshot declared absent without opening the folder, and a
>    135 lb ramp generated in OUR app and reported as the reference's. The last one was caught only
>    by asking, and by noticing the numbers were exactly what our own formula predicts.
>
> **The shape worth keeping, and it has now caught the SAME MISTAKE TWICE: a claim was made on the
> strength of an absence, and an absence is only evidence if you looked where it would have been.**
> The original claim came from the WORKOUT screens, where there is indeed no way to adjust
> percentages, and nobody had opened the settings screenshots at that point. Then the correction
> itself said the sub-screen was "not among the captured screenshots" — without opening the
> fourteen files to check. It was file eleven.

> ~~**The settings model that used to be item 2 on this list no longer exists as a requirement.**~~
> **SUPERSEDED by the block above — the reference app DOES have that screen, and it was in the
> captured screenshots the whole time.** Kept as the record of a requirement deleted on the strength
> of an absence nobody had looked for. The ramp is still hard-coded in `Workout/WarmupSets.swift`
> and there is still no screen for it here; what changed is that this is now a DEFERRED feature
> rather than a mistaken one.

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
> ⚠️ **THE ORDERING RULE WAS BROKEN, BY ME, WITHIN AN HOUR OF WRITING IT DOWN.** Migration
> `20260818120000_weights_to_kilograms.sql` says: apply it BEFORE running a build of this client
> against `mcp-strength`, because rows that were already dirty when the client converted push
> KILOGRAMS, and a server that has not converted yet converts them a second time. The client ran
> first, and ten rows on the live project were halved. Repair is
> `20260818140000_repair_double_converted_weights.sql`, **applied and verified by reading the rows
> back**: all eleven weighted rows land on real plate loads and the three session volumes read
> 675, 675 and 6730 lb.
>
> **The reusable part is not the ordering rule, it is that writing a hazard down does not defend
> against it.** The comment was accurate, prominent, and in the file being applied. What was
> missing was a check that could FAIL — nothing anywhere asks "has a client already pushed
> converted rows?" before the conversion runs.
>
> **SOLVED: RUNNING THE UNIT SUITE SYNCED TO THE LIVE PROJECT.** `MCPStrengthTests` is app-hosted
> (`TEST_HOST = MCPStrength.app`), which is the ordinary arrangement and has a consequence nobody
> had looked at: `xcodebuild test` launches the REAL app — real store, real keychain session, no
> `-uiPreview` argument — and its launch trigger ran a full sync against `mcp-strength`. That is
> what pushed at 13:35, and what put the preview fixtures on the server the evening before.
>
> **No test could have caught it, and that is the part to remember.** The tests never touch the
> network: in-memory containers, fake transport, exactly as designed. The damage happened
> *outside* the code under test, before the first test case ran. A suite cannot test the harness
> it is running inside.
>
> Fixed by `Auth/AutomatedLaunch.swift`, checked at both sync triggers. `AutomatedLaunchTests`
> pins it and is unusual in being able to observe its own subject — it runs under XCTest, so
> `isRunningTests` must be true where it is asserted.
>
> > **`XCTestConfigurationFilePath` is set to an EMPTY STRING.** Presence is the signal; the value
> > is not. A reasonable-looking `!(path ?? "").isEmpty` reports "not a test run" throughout a test
> > run — false in the one direction that lets a sync reach the live project. This cost a second
> > wrong diagnosis: the first version of the test asserted a non-empty value, failed, and was read
> > as "the variable disappears once tests are running". It never disappears.
>
> > **Never let two `xcodebuild` runs share a log file.** Both redirect with `>` and the output
> > interleaves: a passed count is inflated, and a stale `Failing tests:` block from one run sits
> > beside a `TEST SUCCEEDED` from the other. It produced a reported "603 tests green" when the
> > real figure was 415, and a log carrying both verdict lines. One unique log path per run, and
> > check that exactly ONE verdict line exists before believing it.
>
> > **A per-test log line can go MISSING from a redirected `xcodebuild` log, so a passed count is
> > a floor rather than a figure.** Two consecutive runs reported 495 and 504 where the real delta
> > was 8 new tests; the extra one was `SyncStatusTests/aFreshAccountHasNoCursor`, a committed test
> > that simply did not appear in the earlier log. Swift Testing runs in parallel and the lines
> > interleave. **`** TEST SUCCEEDED **` plus zero failures is the signal; the count is not.** If a
> > count must be trusted, diff the two runs BY SUITE rather than comparing totals — that is what
> > located this in a minute.
>
> > **A dump diff told me preview mode was the culprit and it was wrong.** `pg_dump --data-only`
> > does not emit rows in a stable ORDER, so a plain `diff` of two dumps reports changes that did
> > not happen. Compare parsed rows keyed by id — `server_updated_at` is the field that actually
> > answers "was this row written".

### Landed

- **The schema, on a real project.** Twelve tables, 18 RLS policies, 12 sync triggers, the seeded
  library, and now the last-write-wins guard (12 more triggers). **All 8 migrations applied and
  verified remote == local by dumping the schema back**, not by trusting `db push`.
  `05-database.md` is the decisions record; `./supabase/tests/run.sh` exercises it against a
  throwaway container.
  > **`supabase db dump` WRITES `CREATE OR REPLACE TRIGGER` AND `CREATE TABLE IF NOT EXISTS`.**
  > So grepping a dump for `CREATE TRIGGER` or `CREATE TABLE` returns ZERO and reads as "the
  > object is missing" — which is a false negative on the exact method this project uses to verify
  > a remote schema. It happened while verifying `app_settings` on 2026-08-18: the table and policy
  > matched, the triggers appeared absent, and the triggers were fine. **Before believing an object
  > is missing from a dump, check whether the dump contains that KIND of object at all** — one
  > `grep -oE '^CREATE [A-Z ]+' | sort | uniq -c` answers it, and it is the same discipline as
  > reading `0 passed, 1 failed` correctly.
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
- **The warm-up ramp** (`Workout/WarmupSets.swift`), wired into both screens. Percentages are the
  reference app's `Default` formula — **40 / 60 / 80 at 5 / 5 / 3, corrected 2026-08-19** from a
  wrong fit; see the Warm-up Calculator block at the top of this file — and bar weight floors it so
  it cannot propose a load lighter than the bar. **Now watched running on a screen**, which is where the Previous-column bug
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

- **Explicit-null encoding, all thirteen row structs.** A cleared field now travels as JSON `null`
  instead of vanishing from the payload and leaving the server's old value in place.
  > **The most reachable instance was one the design doc missed: Leave Superset.** It is a shipped
  > menu item that clears `superset_group_id`, so leaving a superset never travelled and the next
  > pull put you back in it. Unfiling a template, deleting a note or summary, and clearing a
  > prescribed or logged weight were the others.
  > **The fix's own risk is bigger than the bug, and is guarded structurally.** A hand-written
  > encoder that FORGETS a field means that field never travels at all — set or cleared — and it
  > would compile, pass every existing round-trip, and be invisible in review. So every
  > `CodingKeys` is `CaseIterable` and `everyNilOptionalStillEmitsItsKeyExceptServerUpdatedAt`
  > iterates `allCases` per row with every optional nil. **Keep that test working when you add a
  > column.**
  > **Why eleven structs carried this for months:** every round-trip test built rows with values
  > PRESENT. The absence is the case nobody wrote — the same shape as the warm-up ramp bug, where
  > every test used a set list with no warm-ups in it.

- **Apple Health, the WORKOUTS half — one direction, out only.** A finished workout is added to
  Apple Health, so training counts toward Activity. `Health/HealthWorkoutRule.swift` is the pure
  eligibility rule and `Health/HealthStore.swift` is the framework behind a protocol, the same
  split as SyncPlanning versus SyncClient and for the same reason: HealthKit cannot be exercised in
  a unit test, so everything that DECIDES sits where a test can reach it.
  > **The entitlement provisioned automatically** with `-allowProvisioningUpdates` on the paid
  > team — no portal work — and was verified by reading it back out of the SIGNED app
  > (`codesign -d --entitlements`), not from the build log.
  > **Idempotency is `HKMetadataKeyExternalUUID`, not a flag on `Workout`.** A `didWriteToHealth`
  > column would be a stored property on a synced model, would need a Postgres column to travel,
  > and would still be wrong across devices — Health syncs via iCloud, so the entry can already be
  > there while a second phone's flag says otherwise. Ask Health what Health has.
  > **No energy burned and no total volume**, deliberately. Nothing computes calories, so any
  > number is invented, and `0` is worse than absent: Apple Fitness would render "0 calories"
  > against an hour of squatting. Rule 4 applied to somebody else's UI, where we cannot add a
  > caveat.
  > **Authorization IS the switch** — no stored preference, because HealthKit already keeps a
  > per-device answer and a second flag is a second source of truth. The cost is that turning it
  > off happens in Health, and the settings row says exactly where.
  > **`HKWorkoutBuilder`, not the `HKWorkout` initialisers** — all of them are
  > `API_DEPRECATED("Use HKWorkoutBuilder", ios(8.0, 17.0))`, read out of `HKWorkout.h` rather than
  > recalled.

- **WORKOUT CALORIES — the client half of `workout_calorie_rate`, which was a live column with no
  client code.** A flat rate per hour the user picks (None / Low / Medium / High / Very High at
  0 / 150 / 200 / 250 / 300 kcal), taken from the reference app's own Apple Health screen
  (`Settings accessed from profile page/IMG_2996.PNG`). The Swift enum, the `AppSettings` field,
  the wire row + mapper + apply, the picker under Settings → Apple Health, and an
  `activeEnergyBurned` sample on the `HKWorkoutBuilder`.
  > **`none` writes NO SAMPLE, not a zero one.** `HealthWorkoutPlan.activeEnergyKilocalories` is
  > `Double?` so the two cannot be confused, and `noneWritesNoEnergySampleAtAllRatherThanZero` is
  > the load-bearing test. A rule written as "multiply by the rate" passes every other test in that
  > file and silently writes a 0 kcal sample into Apple Fitness — rule 4, in somebody else's UI.
  > **Energy is a SECOND write permission and it is checked separately.** iOS authorizes
  > `activeEnergyBurned` independently of workouts and Health can switch the two off
  > independently, so both statuses are read before writing and energy is SKIPPED when refused.
  > Adding a sample the app may not share throws out of `finishWorkout`, which would lose the
  > WORKOUT because of a permission about its energy — trading a record for an estimate. Both types
  > are requested in ONE prompt, so nobody meets a permission sheet at the end of a session.
  > **The rate row appears only once workouts are authorized**, which is the absent-unit-rows rule
  > applied to a preference: until Health is allowed, nothing reads the rate. The reference shows
  > its row unconditionally — a deliberate divergence, and it costs nothing, because the row
  > appears the moment the permission it depends on is granted.
  > **The client default is `medium` because the SERVER's default is `medium`.** A client
  > defaulting to `none` against a column defaulting to `medium` means a device that never touched
  > the setting disagrees with the row the server hands its next device.
  > ⚠️ **ENERGY WRITES — verified 2026-08-19 on a sub-minute session (0.25 kcal).** Watch-attach
  > is wired (see Landed below) and still unverified on a Watch-on session.

- **WATCH ACTIVE ENERGY — prefer existing samples over our estimate.** `HealthEnergyAction`
  decides none / attach / estimate; `HealthStore` queries `activeEnergyBurned` in `[start, end]`,
  `addSamples` those when present, and falls back to the flat rate if the query is empty or
  attach throws. `NSHealthShareUsageDescription` is in the plist; the read set is that one type.
  Written as a Ringer job for the rule (`mcpstrength-watch-energy`, grok-4.6, first try) and
  wired here. **Unverified on a Watch-on session.**

- **WORKOUTS TOGGLE — permitted AND switched on.** `writeWorkoutsToHealth` on `AppSettings`,
  default `true`, synced (`20260819200000`, applied and verified in the dump). The Settings
  Apple Health row is a switch when permission is granted. HealthStore will not write unless
  both are true. Re-flipping the switch that is already on does not mark the row edited.

- **HEALTH BACKFILL — "N workouts without corresponding Apple Health entries. Add?"**
  `HealthWorkoutRule.missingFromHealth` subtracts this app's written external UUIDs from
  eligible local workouts (eligibility is `plan`, not a second list of reasons).
  `backfillPrompt(count:)` is nil at 0 (rule 4) and singular at 1. Settings shows the
  yellow strip under Workouts when permitted AND switched on; Add writes through the
  same `writeWorkout` path Finish uses. A failed Health query hides the banner rather
  than treating it as "Health has none of ours" (that would duplicate). Ringer job
  `mcpstrength-health-backfill` (grok-4.6, attempt 2 — the retry was a one-line
  `#expect` the check demanded, not a logic miss). **Unverified on the phone: whether
  the count matches what Health actually lacks, and whether Add lands them.**

- **MEASUREMENTS ↔ HEALTH — four types, both directions.** `HealthMeasurementRule` maps
  Weight / Body Fat %, Caloric Intake / Waist by seed UUID, converts to Health
  units (body fat 20% → 0.20, not 20), refuses `.healthKit` source on the way
  out, and skips our own samples on the way in (`importPlan` identity is
  `externalID ?? sampleID` so a scale sample with no metadata still dedupes).
  Settings has write and read toggles (`writeMeasurementsToHealth` /
  `readMeasurementsFromHealth`, `20260819210000`, applied and verified in
  the dump) plus two yellow banners: local rows Health never got, and Health
  samples the app never got. The other fourteen types have no HealthKit type
  and are not sent or imported. Ringer jobs `mcpstrength-health-measurements`
  and `mcpstrength-health-measurement-import` (both grok-4.6, first try).
  **Unverified on the phone: whether Allow asks to read, whether Add from
  Health lands a Weight on the Measure tab, and whether our own write does
  not echo back as a duplicate.**

- **PHASE 3 SCAFFOLD — MCP Edge Function, 2026-08-19.** `supabase/functions/mcp`
  serves Streamable HTTP, answers unauthenticated POSTs with a `401` that
  points Claude at protected-resource metadata, and queries Postgres as the
  caller (`ctx.supabase` only — `neverAdmin_test.ts` holds that). First tool
  is `list_exercises` (search + category filter + body-part ranking hint;
  matcher ported from `ExerciseMatcher.swift`) and `create_exercise` (fuzzy
  match first, echo `matched_to_existing`, refuse to guess on ambiguity).
  Consent is `web/` on Cloudflare Pages at mcpstrength.com (`/oauth/consent`),
  because Edge Functions on `*.supabase.co` cannot serve HTML. Claude's
  connector URL is `https://mcp.mcpstrength.com` (Worker in
  `workers/mcp-proxy/`, `MCP_RESOURCE_URL` matches). The `oauth-consent`
  function is leftover and not the live Allow page.
  Remaining tool is `log_workout`.

- **WORKOUT HISTORY MCP TOOLS — 2026-08-20.** `get_workout_history` (date-filtered
  completed sessions, newest first) and `get_exercise_progress` (per-exercise
  time series). Both return the coaching channel: workout `note` (instructions
  in), `summary` (how it went), per-exercise `note` and `sticky_note`. Weights
  are kilograms. `dropSet` not `drop_set`. Unfinished sessions are not history.
  Progress name-lookup uses the same matcher as `create_exercise`: several
  library rows (`Lat Pulldown` after the rebuild) return candidates and no
  series rather than picking a winner. 57 Deno tests green. **Live as of
  the 2026-08-20 `mcp` Edge Function deploy.**

- **PROGRAM AND DELETE MCP TOOLS — 2026-08-20.** `create_program` writes a
  `template_folders` row with `kind: program` plus `program_days` that may
  repeat a template (A, B, A). Referenced templates are filed into the folder.
  Linear progression is accepted and echoed with `executed: false` — the app
  still has no rules engine, and lying about that is how a caller would think
  the load will auto-increase. `delete_template` / `delete_program` are soft,
  UUID-only, `destructiveHint: true`. A program delete keeps its templates
  (SoftDelete.folder's nullify). A plain folder is refused. 71 Deno tests
  green. **Live as of the 2026-08-20 `mcp` Edge Function deploy.**

- **CUSTOM NUMBER KEYPAD — on the phone 2026-08-19, Drake approved it after two layout fixes.**
  Chip + pinned keypad (`Views/NumberKeypad.swift` + `Workout/NumberKeypadEditing.swift`), not
  `ToolbarItemGroup(placement: .keyboard)` and not a `UITextField` `inputView`. Hosted on the
  live workout, the template editor, and the measurement sheet. Per-set rest sheet removed;
  divider tap focuses the keypad. Writes still go through `commitWeight` / `commitReps`.
  `WeightUnits.keypadStep` is 2.5 lb / 1.25 kg and is **not** `plateIncrement`.
  > The two layout bugs that must not come back: Next must not take `maxHeight: .infinity`
  > inside a `safeAreaInset` (it filled the screen), and the rest-bar focus ring is white
  > on a clipped fill, not `Theme.accent` on a `Rectangle` (that painted the empty end of
  > the bar blue). Reference facts and Next-walk rules are in `HANDOFF.md` and
  > `02-architecture.md`.

### What turning sync on for real found — one outage, and the harness was hiding it

**2026-08-19. The first sync after settings backup went live failed, and the failure was total:
exactly ONE request left the phone.**

    POST /rest/v1/app_settings → 403
    postgres: permission denied for table app_settings

`app_settings` is FIRST in `SyncEntity.allCases`, so the rejected batch aborted the whole run —
no other table was attempted and the pull never happened. The account card said "Backup failed".

**The cause: `grant … on all tables in schema public` is a ONE-TIME SNAPSHOT.**
`20260815120200_rls.sql` granted `authenticated` on every table that existed in August 15.
`app_settings` was created on August 18 and was never granted. RLS was correct and irrelevant —
the role could not reach the table at all.

> **The same file had already understood this and fixed HALF of it.** It ends with
> `alter default privileges in schema public revoke all on tables from anon;` under a comment
> saying *"Applies the same rule to tables added by later migrations."* The anon REVOKE was made
> durable; the mirror-image GRANT to `authenticated` was not. So every table added since arrives
> correctly locked down and also unreachable.

> ⚠️ **THE TEST SUITE COULD NOT HAVE CAUGHT IT, AND THAT IS THE REAL LESSON.** `00_shim.sql` did
> `alter default privileges in schema public grant all on tables to anon, authenticated,
> service_role`, so in the throwaway container every new table was granted automatically. **The
> harness was MORE PERMISSIVE THAN PRODUCTION, in exactly the dimension the bug lived in.** A test
> environment more permissive than production cannot test authorization — it can only agree with
> you. This is the same family as "tests build their Postgres from the local migration files, so
> the schema is right there by construction", and worse, because that one is written down and this
> one was a convenience nobody re-examined.
>
> Fixed by removing the blanket grant from the shim and adding `07_grants_test.sql`, which asserts
> the four verbs for `authenticated` and none for `anon` on every synced table — **plus a canary
> table created at test time**, to prove a table added TOMORROW inherits both rules. That last
> assertion is the one that prevents a recurrence: the others describe today, and the bug lived in
> tomorrow. Self-tested by removing the fix migration and watching it fail with
> `authenticated lacks SELECT on public.app_settings`.

> **Generalises past grants: `… on all tables` in ANY migration is a snapshot, not a rule.** If it
> must hold for tables added later, it needs `alter default privileges` beside it.

> **And the app made it harder than it needed to be.** `failureReason` flattened every non-offline
> error to "Backup could not finish.", so a sentence that named both the table and the cause was
> discarded and the answer had to be dug out of the project's server logs. The engine had even
> logged it — the decision was "logged, not surfaced", on the reasoning that a user's sentence and
> a developer's detail are different artefacts. True in general, empty here: there is one user and
> he is also the person debugging it. A server's own refusal now reaches the screen, behind the
> `ServerRefusal` protocol so `SyncEngine` stays free of the Supabase SDK. **Revisit when there are
> users who are not Drake.**

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

### What a gym session found — seven bugs, and three of them were the same shape

**2026-08-18. Drake used the app to train, and reported seven things in about an hour.** All are
fixed; the log is `bug-triage/BUGS.md`. Keeping the causes here because three of them are one
shape, and it is a shape this codebase produces repeatedly.

**A wrapper silently swallowing the thing it wraps.** Not one of these threw, logged, or failed a
check. Each compiled cleanly, read correctly in a diff, and did nothing:

| Symptom | Cause |
|---|---|
| Templates could not be dragged between folders — and `04-status.md` claimed the feature was DONE | `TemplateCard`'s root was a `Button`, which consumes the long press `.draggable` needs. Written, reviewed, unreachable |
| Making the whole folder a drop target changed nothing | A drop destination hit-tests the RENDERED shape, and the section's background was `.clear` until targeted. A clear fill is not hit-testable. `.contentShape(Rectangle())` |
| The rest bar closed toward its middle instead of draining | The fill sat in a `ZStack`, which centres by default, so shrinking its width took the same off both edges |

> **The reusable question: "is this modifier on a view that can actually receive what it is
> about?"** All three were correct modifiers on views that could not take them. The existing
> `.sheet(isPresented:)` trap in this document is the fourth member of the family.

**Two more were state with a second, undocumented job.** `defaultRestSeconds` on the workout screen
was a hardcoded `90`, so the options menu wrote a value nothing read — the Add Set button always
said 1:30 and always appended 90 seconds. And `draggingExerciseID` means both "what was lifted" and
"something is being dragged, here is an arbitrary id", so a new condition that read it the first
way suppressed the insertion marker on exactly the block the user was aiming at.

**One was a design decision that only use could overturn.** The rest-timer menu deliberately
applied to NEW sets only, with per-set edits via the divider — defensible on paper, and in a gym it
reads as the control doing nothing. It now rewrites every set in the exercise. The per-set override
survives.

**And one was pure interaction language.** Dragging a template onto a card looked like filing it
INSIDE that card. Three things said so at once: the hovered card was outlined (a container
affordance), the dragged card stayed fully drawn so no empty slot existed, and the gutters between
cards belonged to the folder rather than to any card, so the reflow stopped and started. The rule
underneath never changed — only whether the screen described it honestly.

### Also landed

- **A local notification when a rest ends**, plus a haptic for the app-in-front case.
  `RestNotificationRule` is a pure function of (timer, now) and the view hands it the timer whenever
  it changes — so start / pause / resume / adjust / reset / skip are all covered by watching the
  value, and so is any seventh operation added later. Same reasoning as `PushFilter`: a rule that
  cannot be violated beats one you have to remember. Every test in it is about firing at the WRONG
  moment, which is the only failure that matters.
- **Swipe-to-delete on set rows**, hand-built because `.swipeActions` needs a `List` and this app
  has none. Tombstones on the workout screen, drops a draft in the template editor.
- **Template fixtures**, which did not exist — the Start Workout tab was empty in preview mode, so
  nobody had ever looked at it with content.
- **`AutomatedLaunch`**, which stops a test run syncing to the live project. See the START HERE
  block above; this was the cause of the double-converted rows.
- **`ExercisePreference`, the model half of per-exercise Preferences.** The four per-user fields
  left `Exercise`; an optional relationship replaced them; seven display sites now read
  `exercise.preference?.…`; the seed importer no longer has to remember not to overwrite them.
  Written by a Ringer worker (grok-4.6, first attempt, run
  `mcpstrength-per-exercise-preferences`) and reviewed here — the routing call the handoff asked
  for, and the right one: a required init argument disappearing turned all ~65 stale construction
  sites into compile errors, which is what made the work checkable by a sandbox that cannot run a
  test.
  > **Three things the worker got right that are worth keeping.** It corrected `06-sync.md` on the
  > `id` (there is no `id` column on the server to match a minted one against) rather than
  > implementing the doc as written. It noticed that `current(for:in:)` cannot copy
  > `AppSettings.current`'s tombstone behaviour, and said which future change owns the difference.
  > And it left `ExerciseOptionsMenu.swift`'s now-stale comment alone because the spec put that
  > file out of bounds, and recorded the staleness instead of silently fixing it.
- **The Preferences sheet — the EIGHTH and last item of the reference app's per-exercise menu.**
  Two rows (Weight Unit, Bar Type), Save rather than commit-on-tap, and the bar weights labelled in
  whichever unit the row above is currently set to.
  > **A Save that changed nothing writes nothing at all**, and that is a rule with tests rather
  > than a property of the view. `ExercisePreference.current(for:in:)` CREATES on a miss, so a
  > Save that resolved the row unconditionally would insert a row of pure defaults, dirty it, and
  > eventually push it — for the completely ordinary act of opening the sheet and looking at it.
  > `ExercisePreferenceEditing.write` is the decision; the load-bearing test is the one that
  > expects `nil`.
  > **The case that looks like a no-op and is not: CLEARING a preference back to Default.** A rule
  > written as "write only when something is set" passes every other test and silently drops that
  > one, leaving the old value on the row forever. The test names it.
  > **The sheet is where the kilogram display path first became visible to a human.** Set an
  > exercise to Metric and the bar list re-labels — 45 lb becomes 20 kg, which `BarType.weight(in:)`
  > insists is a DIFFERENT BAR rather than a conversion. `PreviousText.formatWeight` is the right
  > formatter there and `weightText` is the wrong one, because a bar weight is already in the
  > display unit and must never be converted.
  > **In the template editor it deliberately does NOT go through the draft**, unlike every other
  > item on that menu. A preference belongs to the exercise, not the template, so routing it
  > through the draft would let Cancel on a template silently revert a bar type the user set for
  > every workout they will ever log.
- **The settings screen, and with it the global weight unit — ONE ROW.** Gear on the Profile tab →
  Settings → Weight Unit → Metric (kg) / US/Imperial (lbs). **This is what finally makes the
  kilogram half of canonical storage reachable for every exercise**, rather than one at a time
  through a per-exercise override.
  > **The other three unit rows are ABSENT, and that was a decision Drake made explicitly.** The
  > reference's UNITS AND LOCALIZATION section has six rows and `AppSettings` carries a field for
  > every one — but only `weightUnit` has a READER. Shipping the rest would mean controls that
  > write a value no screen consults, which is not a hypothetical: it is the rest-timer bug from
  > the gym session, where a menu wrote `defaultRestSeconds` and the screen read a hardcoded 90.
  > Same call as Archive and Share. Each row arrives with its reader.
  > **`Measurement Weight Unit` and `Size Unit` carry a real undecided question**, which is why
  > they are not a quick follow-up: measurements are NOT stored canonically the way weights are —
  > `MeasurementEntry.unit` is a string on each row — so changing the setting either converts the
  > history or leaves a mixed list, and nobody has decided which. `Distance Unit` has nothing to
  > affect at all; there is no cardio logging screen.
  > **Re-picking the unit that is already ticked must NOT mark the row edited**
  > (`AppSettings.setWeightUnit`). Opening a picker to see which option is selected and tapping it
  > is ordinary, and a row that dirties itself every time somebody LOOKS at it would — once this
  > syncs — beat a genuine edit made on another device purely because this one was opened more
  > recently. Same rule, same reason, as the Preferences sheet's no-change Save.
  > **One label for both screens** (`WeightUnit.settingsLabel`), and the wording is the reference's:
  > `Metric (kg)` / `US/Imperial (lbs)`. The Preferences sheet was corrected to match in the same
  > change — two screens that choose one setting and name it differently read as two settings.
  > Deliberately distinct from `abbreviation` (trails a number) and `columnHeader` (heads a
  > column); a test fails if somebody collapses the three.
- **`secondaryBodyParts` — an exercise can train more than one body part.** Drake asked directly
  (2026-08-19): should Deadlift show up under both Legs and Back? Built as a real feature rather
  than a spreadsheet workaround. `bodyPart` stays the single PRIMARY value; `secondaryBodyParts`
  (`[BodyPart]`, declaration-defaulted `= []` — AGENTS.md rule 2) is what it does not capture.
  Deadlift is `bodyPart: .back, secondaryBodyParts: [.legs]`, never `[.back, .legs]` with no
  primary. `Exercise.trains(_:)` is the one predicate — the library filter pills, the matcher's
  body-part hint, and the MCP server's `list_exercises`/`create_exercise` output all read it, so
  "does Deadlift count as Legs" has exactly one answer across phone app and AI caller.
  > **A full-stack change discovered mid-task, not scoped that way going in.** Phase 3's MCP
  > server (`supabase/functions/mcp`) ports the matcher to TypeScript deliberately — its own header
  > comment says so — so the boost had to change in both places or an AI caller and the phone app
  > would rank the same hint differently. `exerciseMatcher.ts`, `listExercises.ts`,
  > `createExercise.ts`, `createTemplate.ts` and `types.ts` all changed; 42 Deno tests green.
  > **Postgres migration `20260819220000`**, applied and verified remote (dumped the schema back,
  > then read Deadlift's own row back rather than trusting the `UPDATE`): `body_part[]`, matching
  > the existing `aliases text[] not null default '{}'` shape on the same table. Same ordering
  > discipline as every prior `exercises`-touching migration: schema applied and verified BEFORE
  > the client build that sends the column, because `exercises` is second in the sync push order
  > and an unknown column aborts the whole run.
  > **Deadlift is the worked example, not a hypothetical** — genuinely tagged
  > `secondaryBodyParts: [.legs]` in the bundled JSON and on the live project, both reached via the
  > same UPDATE statement (client) and re-seed refresh-on-match (any future device). 648 Swift
  > tests green, including a tie-break test proving the boost fires via a SECONDARY body part, not
  > just the primary (`ExerciseMatcherTests.legsHintBoostsAnExerciseViaItsSecondaryBodyPart`).
  > **The exercise-library-refresh spreadsheet (`exercise-library-refresh/exercise-review.xlsx`,
  > sent to Drake for review, not yet merged) gained a "Secondary Body Part" column** with the
  > posterior-chain candidates pre-filled (Romanian/Stiff-Leg/Sumo Deadlift, Good Morning, Rack
  > Pull, Zercher Squat, and others) — flagged, not silently decided. Still open from that review:
  > ~26 likely duplicates against the existing 25. See `HANDOFF.md`.
- ~~**`ExerciseCategory.hammerStrength` — deferred as a string constant, no real case.**~~
  **UNBLOCKED 2026-08-19**, once real Hammer Strength / iso-lateral exercises showed up in Drake's
  library-refresh list and he confirmed the naming ("Bench Press (Hammer Strength)", not "HS Bench
  Press" — matches how every other equipment variant in the list is already named). The blocker
  really was exactly one line: `OneRepMax.supportsEstimate`'s exhaustive switch, extended to treat
  `.hammerStrength` the same as `.machineOther` (plate-loaded, has a real total load). Bar types
  already carry a weight per unit (`BarType.weight(in:)`, above); this is the matching move for the
  category enum.
  > The Postgres enum value and the AI server's TypeScript types have both had `hammerStrength`
  > since `20260817120000_hammer_strength_category.sql` and Phase 3's build — only the Swift app
  > was missing the case, so this closes a three-system gap in one line rather than opening a new
  > one, unlike `secondaryBodyParts` above.
  > **11 rows in the review spreadsheet retagged and renamed**: the 9 `HS`-named ones, plus 2
  > `Iso-Lateral` ones Drake confirmed are the same brand. `generate_library_seed.py`'s validation
  > set gained `"hammerStrength"` too, so the eventual seed-file merge won't reject them.
  > `BarTypeTests` and `OneRepMaxTests` both updated — `ExerciseCategory.allCases.count == 9`, not
  > 8. **The bundled 25-exercise seed file still asserts exactly 8 categories present** — true and
  > unchanged, since no Hammer Strength exercise has actually been merged into it yet.

- **THE EXERCISE LIBRARY, REBUILT — 25 exercises became 301** (`20260820120000_library_rebuild.sql`).
  Drake reviewed a 310-name list across several passes; this is the merge. Applied to the live
  project and verified by reading the rows back: **311 rows, 301 live, 10 tombstoned.** The rules
  it settled are in `01-data-model.md` § The seeded library — the short version is that a name
  which does not say its equipment does not belong in the library when specific versions exist,
  with a deliberate exception for bodyweight movements whose bare name IS the exercise.
  > **The rebuild was only safe because there was NO workout history — and that was CHECKED, not
  > assumed.** Dumped the live project's data first and found zero `workouts` /
  > `workout_exercises` / `workout_sets` rows. The seeded-ID contract makes this the load-bearing
  > question: with history, re-minting an id detaches it silently and there is no good fix after
  > the fact. 15 of the original 25 survived and kept their original UUIDs anyway; the 286 new ones
  > get deterministic `uuid5(namespace, name)` ids, so regenerating the seed cannot silently
  > re-mint one.
  > **Retired rows are TOMBSTONED, not deleted** (AGENTS.md rule 1) — a hard delete cannot reach a
  > device that was offline when it happened, so the row returns on that device's next pull. The
  > upsert path also sets `deleted_at = null`, so an id that comes BACK into the library returns
  > rather than staying invisible.
  > **A retired name becomes an alias on its successor ONLY when there is exactly one successor.**
  > `Barbell Row` → `Bent Over Row (Barbell)`. For `Lat Pulldown`, `Leg Curl (Machine)` and
  > `Triceps Pushdown (Cable)` two kept exercises were equally plausible, so no alias was written:
  > an alias pointing at one of several real options silently picks a winner, which is the same
  > failure as keeping the generic row in the first place.
  > **`Chin Up` is no longer an alias of `Pull Up`** — Drake, explicitly: they are different
  > exercises. `Chin Up` is its own row with its own assisted / machine / weighted variants.
  > **The generator now writes a NEW migration, not the original seed.** `20260815120300` is
  > already applied, and rewriting an applied migration changes what a FRESH database gets while
  > doing nothing at all to the live project. The original stays frozen as history; the rebuild
  > layers on top, which is the order a fresh database and the live project both see.
  > **Two SQL tests had to change, and one of them was testing the wrong thing.** The counts, and
  > the "aliases are non-unique" test — which asserted that the shipped library happened to contain
  > a shared alias (`row`, on three exercises). The rebuild dropped that alias deliberately: with
  > ~15 `* Row *` exercises, aliasing three of them picks arbitrary winners and spelling similarity
  > already surfaces them all. So a test of the DESIGN was failing for a change to the DATA. It now
  > creates two rows sharing an alias and asserts the schema permits it — an ordinary library edit
  > can no longer break it.

### What is left, in order

1. **Phase 3 — remaining MCP tools.** Connect is live at
   `https://mcp.mcpstrength.com`. Scaffold is in `supabase/functions/mcp`
   (Streamable HTTP, user-scoped client, exercise + template tools) and the
   site in `web/`. Contract for the rest is `03-mcp-tools.md`. `spike/` is
   frozen. Next: `log_workout`. Programs and template delete are live on
   `mcp` as of 2026-08-20. GitHub:
   `https://github.com/drakescifers-droid/mcp-strength-app`.

2. **Prove Watch-attach on a real session — gym check, does not block Phase 3.**
   Wired 2026-08-19: rate none → nothing;
   existing `activeEnergyBurned` in the interval → `addSamples` those and skip our
   estimate; no samples → keep the flat rate; attach throw → fall back to the estimate.
   Read entitlement and prompt are in. **Unverified on a Watch-on session**, including
   whether HealthKit lets an app attach samples another source owns.

> ~~**A cleared field does not travel.**~~ **FIXED 2026-08-19, all thirteen row structs.** Kept
> below only as the record of what it was.

2. ~~**Sync `AppSettings` and `ExercisePreference`.**~~ **DONE 2026-08-18.** Kept below because the
   reasoning is the record of why it was one job.
   
   **Sync `AppSettings` — and `ExercisePreference`, which is waiting on exactly the same
   thing.** Both carry the sync columns and deliberately do NOT conform to `Syncable`. `AppSettings`
   has no Postgres table yet (`05-database.md`); `exercise_preferences` has had one since the first
   migration. What they share is that neither is keyed on `id`: one row per user means `user_id`,
   and a preference means `(user_id, exercise_id)`. `SyncClient.upsert` hard-codes
   `onConflict: "id"`, so making the conflict target a per-entity fact on `SyncEntity` is one
   change that unblocks both.
   > **This is now the item that decides whether a bar type survives losing the phone**, which it
   > was not when it was written. Turning either conformance on before the conflict target moves
   > would abort the whole sync run on the first push, not just fail that table.
   > **The wire row for `exercise_preferences` has no `id` to decode.** Its id must be derived from
   > `exercise_id` on the way in — see the correction in `06-sync.md`.
   > **`StoreMigrations` must NOT be swept up in this.** It sits next to `AppSettings` and looks
   > like more of the same. It is the opposite: a device-local record of which data migrations this
   > STORE has run. Syncing it would let one device tell another that its weights are already
   > converted.
3. **Apple Health.** The last item in Phase 2, and no longer blocked — see the signing note below.

> **`Add Warm-up Sets` has now been looked at and is off this list.** It found one real bug, which
> is recorded below rather than here because the shape of it is the reusable part.

### ON THE PHONE, and the units conversion is proven on a real pounds store

**2026-08-18. `us.aiagent4.MCPStrength` is installed and running on Drake's iPhone 14**, built
against the paid team and installed OVER the existing app — no delete, so the device's own store
survived. That store was written by the pounds-era build, which makes it the only real test of the
conversion that exists.

It passed, and it was read out of the database rather than inferred:

- **It launched.** The store predates both `AppSettings` and `StoreMigrations`, so this was the
  crash-on-launch case in AGENTS.md rule 2 — a `@Model` added to the `Schema` against a store
  written before it existed. The process was still alive afterwards.
- **It converted its own data exactly once.** Two rows it had never synced arrived on the server at
  `61.2350 kg` — 135.00 lb to five decimal places. A second conversion would have produced 27.78.
- **It corrupted nothing.** Zero pre-existing rows were rewritten; five rows were added.
- **Every weighted row on the server lands on a real plate load** (35 / 95 / 135 / 155 / 185 /
  225 lb). That is the same signature used to find the damaged rows earlier, now used as the
  all-clear.

> **The signing checks in this section were applied and they worked.** The profile is 365 days
> (a 7-day one would mean free provisioning), and the team is `OU=ZD2SRFJUPS` read out of the
> certificate — NOT the `(8THV5TS24T)` in the common name, which is the personal id and the thing
> that produced a whole false diagnosis last time.

Rebuild and reinstall with:

```
xcodebuild build -project MCPStrength/MCPStrength.xcodeproj -scheme MCPStrength \
  -destination 'platform=iOS,id=6902E742-268A-53A7-98B9-C9A034110AC8' \
  -derivedDataPath DerivedData DEVELOPMENT_TEAM=ZD2SRFJUPS -allowProvisioningUpdates
xcrun devicectl device install app --device 6902E742-268A-53A7-98B9-C9A034110AC8 \
  DerivedData/Build/Products/Debug-iphoneos/MCPStrength.app
```

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
- **The settings screen has not been used on a real device**, and it carries the one interaction
  nothing has ever exercised: `SetRow` reacts to a unit change with `.onChange(of: unit)`, and
  until this screen existed nothing could produce that change. Switching to Metric with a workout
  open is the case to try — every entry chip on screen should re-render in kilograms.
- ⚠️ **WATCH-ATTACH IS UNVERIFIED ON A REAL SESSION.** The decision and the
  HealthKit wiring landed 2026-08-19. Energy itself DID write earlier (a
  sub-minute test session showed **0.25 kcal** in Apple Fitness). What remains
  is whether a Watch worn during a REAL session has its samples associated with
  our workout instead of sitting beside our estimate. If attach throws or the
  read is denied, we still write the estimate — so a session that looks
  double-counted is a failed attach, not a missing fallback.
  > The picker footer now says Watch numbers win when they exist.
- ~~**APPLE HEALTH HAS NEVER WRITTEN A WORKOUT.**~~ **VERIFIED 2026-08-19 — a finished session
  appeared in Apple Fitness.** Kept so the next session does not re-ask. What remains is
  double-counting (above) and idempotency: finishing the SAME workout twice must produce ONE
  entry, which is the whole reason for the external-uuid lookup.
- **The Preferences sheet has not been used on a real device either**, and it is the newest thing
  on the phone (installed 2026-08-18). Two questions a test cannot answer: whether the bar list
  re-labelling the instant you tap Metric reads as responsive or as flicker, and whether a Save
  that deliberately writes nothing feels broken. The second is the sparse-table rule made visible,
  and if it reads as a bug the fix is the wording, not the rule.
  > **The MIGRATION half is verified, though — the canary was run and it passed.** This change
  > adds a `@Model` and a relationship to `Exercise`, which is the crash-on-launch class, and the
  > unit suite cannot see it by construction. So the documented canary was run against a real
  > old-schema store on `iPhone 17` (`ZEXERCISE` carrying all four columns, no
  > `ZEXERCISEPREFERENCE`): installed over it, launched with `-uiPreview 1`, and
  >
  > * the process stayed alive — no `ModelContainer(for:)` throw;
  > * the store MIGRATED — `ZEXERCISEPREFERENCE` created, `ZEXERCISE` gained `ZPREFERENCE` and
  >   lost the four columns;
  > * the data survived rather than starting over — 3 workouts / 14 sets / 25 exercises before and
  >   after, with the named canary workout intact;
  > * and **zero preference rows existed afterwards**, which is the sparse rule holding through a
  >   real launch that rendered real screens, not just through a unit test.
  >
  > **`simctl install` RELOCATED THE DATA CONTAINER**, exactly as this file warns. The first
  > inspection was of the pre-install path and would have reported on a store the new app never
  > opened. Re-read `simctl get_app_container … data` AFTER installing, every time.
  >
  > **`-uiPreview 1` is what made this safe to do at all**: both sync triggers guard on
  > `UIPreviewMode.isEnabled`, so a manual launch of the real app in preview mode cannot reach the
  > live project. A plain launch would have — the keychain session is still there. Same hazard as
  > the test host, one door over.
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

**Phases 3–4 — Phase 3 is next.** The real multi-user MCP server, then product.

---

## Deliberately deferred

These are not oversights. Each was cut with a reason, and the reason is the point.

| Deferred | Why |
|---|---|
| **Program UI** (rotation view, "what's next") | Post-launch. Not critical to the app succeeding, and with no plan to train on a half-built app, shipping it early teaches nothing. **The schema still landed in Phase 1** — see the note below. |
| **Personal records / PR counts** | Real feature (compare against all prior history, per exercise, per rep count). Nothing computes them, and a hardcoded "0 PRs" reads as *you set no records* rather than *not implemented*. |
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

> **The middle tab reads "Start", where the reference reads "Start Workout".** A deliberate
> divergence, and the reasoning is about the BAR rather than the word. The reference's tab bar
> (`Home screen/Home Screen.PNG`) is flat, full-width, and marks the selected tab with tint alone.
> This platform's bar floats and draws a capsule sized to the selected label, so the longest label
> sitting in the middle slot pushes that capsule out into its neighbours — "History" and
> "Exercises" end up pressed against it. Shortening the label reproduces what the reference
> actually shows, five evenly spaced tabs, rather than the string it uses to show it. The screen's
> own title is still "Start Workout", so the full name is never lost.
>
> **There is no API for this.** `tabBarMinimizeBehavior` only hides the bar on scroll, nothing
> exposes the selection capsule, and the transitional Info.plist opt-out from the previous release
> is not in this SDK — checked, not recalled. Label width is the only lever, which is why a
> one-word change is the whole fix. Revert it in one line if a future OS stops drawing the capsule.

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
