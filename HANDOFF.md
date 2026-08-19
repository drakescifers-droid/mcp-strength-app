# Handoff

A paste-into-a-new-chat prompt, kept in the repo so it can be pointed at instead of retyped:
*"Read HANDOFF.md and let's keep going."*

**This routes; it does not describe.** It deliberately carries no state of its own beyond the open
decisions, because two descriptions of the same project drift apart and then one of them is wrong.
If anything below disagrees with `docs/04-status.md`, **that file wins** — and this one is stale and
should be fixed.

---

Working on the MCP Workout App at `~/MCP Workout App`.

I'm not a developer — explain things in plain English. Code, commits and docs stay technical.

**Start by reading `AGENTS.md`, then `docs/04-status.md` in full.** Between them they carry the
state, the traps, the decisions and the reasoning behind them. Don't re-derive from the code what
those files already explain, and don't duplicate them into new files.

The one-line state: **the app is on Drake's phone, he is training on it, and Phase 2 is down to
Apple Health — workouts go out, calories now go with them, measurements do not.** Sync proven end
to end IN BOTH DIRECTIONS against the live project, canonical units done, a round of gym-found bugs
fixed, per-exercise Preferences — model and sheet — landed, the settings screen makes the global
weight unit changeable, **both settings and preferences SYNC**, and the workout calorie rate is
built on both sides. Swift suite green (546 tests), SQL suite green.

> **THE APP IS IN HIS HAND AND HE TESTS IT.** That changes how you work — see
> `AGENTS.md` § "DRAKE DOES THE UI TESTING". Build, install, hand over. Do not drive the simulator
> to judge how something looks or feels; an afternoon of XCUITest runs cost ~$10 and settled
> nothing. The install loop is two commands and takes about a minute.

> **Every stored weight is now KILOGRAMS.** `WorkoutSet.weight`, `TemplateSet.weight` and
> `Workout.totalVolume`. Never print one without converting it — `PreviousText.weightText` or
> `WeightUnits.displayed` — and never write one without `WeightUnits.kilograms(from:in:)`.

> ✅ **The live project is correct and both migrations are applied** — verified by reading the rows
> back out, not by trusting `db push`: all eleven weighted rows land on real plate loads
> (35 / 95 / 135 / 155 / 185 / 225 lb) and the three session volumes read 675, 675 and 6730 lb.
> `20260818140000` was needed because `20260818120000` halved ten rows that a client had already
> converted. `04-status.md` has the full story, including the
> cause: **running the unit suite was syncing to the live project**, because the test bundle is
> hosted by the app, so `xcodebuild test` launched the real app signed in. Fixed in
> `Auth/AutomatedLaunch.swift` and pinned by a test.

> **Seven bugs came out of one gym session, and all seven are fixed** —
> `bug-triage/BUGS.md` is the log, kept because the CAUSES are more useful than the fixes. Three of
> them were gestures silently swallowed by a wrapper (`Button` eating a long press, a `.clear`
> background that cannot be hit-tested, a `ZStack` centring a shrinking bar). None was catchable by
> a test; all were obvious in five seconds on a device.

## Next piece of work, in order

1. ✅ **APPLE HEALTH CALORIES ARE BUILT — both halves — AND THE NUMBER NEEDS A THUMB.**
   `WorkoutCalorieRate` (five cases matching `public.workout_calorie_rate`), the `AppSettings`
   field defaulting to `medium` like the column does, the wire row + mapper + apply + the explicit
   `encode` line, the picker under Settings → Apple Health, and an `activeEnergyBurned` sample on
   the `HKWorkoutBuilder`. A flat rate per hour the user picks: None / Low / Medium / High / Very
   High at 0 / 150 / 200 / 250 / 300 kcal.
   > ⚠️ **WHAT IS UNVERIFIED IS DOUBLE COUNTING, and it is a fact about Apple rather than about
   > this code — only a phone can answer it.** A worn Watch already writes `activeEnergyBurned`
   > continuously; our sample on top may count twice in the Activity rings. Finish a workout, then
   > look at the day's Move ring and at the workout's own calorie figure in Apple Fitness. If it
   > double-counts, `None` is the honest setting and item 2 below is the real answer.
   > **Two decisions worth knowing before touching it:** energy is a SECOND write permission,
   > authorized and revocable separately from workouts, so it is skipped rather than allowed to
   > throw (a permission about energy must not cost the whole workout); and `none` writes NO
   > SAMPLE rather than a zero one.

2. **The better energy answer, and Drake's stated preference — attach the Watch's EXISTING
   samples.** `HKWorkoutBuilder.addSamples` documents that samples *"will be saved to the database
   if they have not already been saved"*, so already-recorded energy can be ASSOCIATED with our
   workout rather than duplicated: real measured numbers, no estimate, no Watch app. **Two things
   to settle before building it:** it needs READ permission (so `NSHealthShareUsageDescription` and
   a non-empty read set, widening today's deliberately write-only entitlement), and **it is NOT
   established that HealthKit lets an app attach samples ANOTHER SOURCE owns.** Test that on a
   device first. Drake said the flat rate "is fine for now" and this is where it should end up.

3. **Two more corrections the reference screens forced, and NEITHER IS BUILT** — both recorded in
   `02-architecture.md`: an explicit per-type **toggle** separate from the permission (so
   `HealthStore.swift`'s "authorization is the only switch" reasoning is wrong — iOS cannot revoke
   its own permission, so without a toggle there is no way to turn it off from inside the app), and
   **backfill** ("14 workouts without corresponding Health entries. Add?"), which is cheap because
   the external-uuid lookup that makes writing idempotent is the same query that finds what is
   missing.
   > The calorie rate made the toggle MORE pressing: somebody who dislikes the energy number can
   > now only stop it by picking `None` or by leaving the app for Health, and `None` turns off
   > energy, not workouts.

4. **Apple Health — the MEASUREMENTS half.** The genuinely bidirectional part, and the echo-loop
   trap: write a weight to Health, Health notifies observers, the app re-imports its own write as a
   new entry, duplicates forever. `MeasurementEntry.source` exists for that guard.
   > **Only 4 of the 18 measurement types exist in HealthKit** — Weight, Body Fat %, Caloric
   > Intake, Waist. The other fourteen are limb and torso circumferences with no HealthKit type, so
   > the screen must say which rows can travel rather than implying all of them do.

Then Phase 3, the real MCP server, which Drake has confirmed is in scope for v1.

> **Per-exercise Preferences is DONE, and it went through Ringer — which answers the question this
> file used to ask.** The model split ran as `mcpstrength-per-exercise-preferences` (grok-4.6,
> passed first attempt, 619s); the sheet was built here, because the routing rule sends mechanical
> checkable work out and keeps visual work in.
>
> **The property that made it routable is the reusable part.** `focusMetric` was a REQUIRED init
> argument, so deleting it turned all ~65 stale construction sites into compile errors — which let
> a sandbox that cannot run a test verify a 26-file sweep anyway. Look for that shape when deciding
> whether a refactor can be delegated at all.
>
> It also CORRECTED the design doc rather than implementing it as written: `06-sync.md` called for
> "an ordinary id" and there is no `id` column on the server to match one against, so the id is the
> exercise's. Both docs now say so.

> **`Add Warm-up Sets` has been looked at and is done.** It found one real bug — the Previous
> column followed row position, so a generated ramp moved your last working set onto a warm-up.
> Fixed; the reasoning is in `04-status.md` § "What looking at the warm-up ramp found".

## Waiting on me

- **The bar on logging real workouts is LIFTED** — the units conversion has landed, which is the
  only thing it was ever waiting on. What still blocks the phone is the item below.
- ✅ **SOLVED — the 13:35 push was `xcodebuild test`.** The test bundle is hosted by the app, so a
  test run launched the REAL app, signed in, and its launch trigger synced. Fixed in
  `Auth/AutomatedLaunch.swift` and pinned by a test; `04-status.md` has the full story. Nothing is
  waiting on this any more.
- **The app is ON my iPhone 14 and running** (installed 2026-08-18, direct install, no TestFlight
  needed). The units conversion is proven on a real pounds-era store — see `04-status.md`.
- **The App Store Connect app record does not exist yet**, so nothing can be uploaded even though
  the build is ready. Only I can create it. Ask before running any upload; it is outward-facing.
- **The template editor has still never been looked at by anyone.** It is the last completely
  unseen screen — and it no longer needs your hands: point
  `MCPStrengthUITests/WarmupRampWalkthroughTests` at it and read the screenshots.
- ✅ **SYNC IS PROVEN IN BOTH DIRECTIONS against the live project** (2026-08-19). A settings
  change uploaded — `POST /rest/v1/app_settings → 200` — and a full pull of all thirteen tables
  came back 200. Read out of the project's own request logs, not inferred from the UI.
- ⚠️ **APPLE HEALTH HAS NEVER WRITTEN A WORKOUT.** The rule is tested and the entitlement is
  verified in the SIGNED app, but no sample has reached Health — a unit test cannot grant a
  permission or write one. **Settings → Apple Health → Allow, finish a workout, look in Apple
  Fitness.** Three things to look at, in this order:
  1. the workout is there at all;
  2. **the calories.** The permission sheet now asks for Active Energy as well as Workouts —
     allow both. Then check the day's Move ring: if you were wearing the Watch, our estimate may
     be counted ON TOP of what the Watch already recorded. That is the one unverified thing in
     this feature, and `None` in Settings → Apple Health → Workout Active Calories Rate is the
     honest setting until it is answered;
  3. finishing the SAME workout twice must produce ONE entry, which is the whole point of the
     external-uuid lookup.
- **The calorie rate picker is new and has never been tapped.** Settings → Apple Health → Workout
  Active Calories Rate. It only appears once Health is allowed — deliberate, and the reasoning is
  in `04-status.md`. Worth saying whether the row title reads as too long on the phone; it is the
  reference app's own wording and it wraps to two lines.
- ~~SYNC HAS FAILED ONCE~~ — the 2026-08-19 outage is fixed and explained below. `permission denied for table app_settings`: a
  table created after `grant … on all tables` had never been granted, and because it is first in
  the push order the whole run aborted. Migration `20260819140000` fixes it and is applied.
  **What is still unproven is a run that WORKS** — tap `Back Up Now` on the Profile tab and the
  card should go to "Backed up". If it fails again it will now say what the server said.
- **THE SETTINGS SCREEN needs a thumb — gear, top-left of Profile.** One row: Weight Unit. The
  case worth trying is switching to Metric **with a workout open**, because `SetRow` reacts with
  `.onChange(of: unit)` and nothing has ever been able to produce that change before. Every entry
  chip on screen should re-render in kilograms, and nothing logged is altered.
  > The other three unit rows from the reference are deliberately absent — nothing reads them yet,
  > and a control that silently does nothing is the rest-timer bug again. Your call, made
  > 2026-08-18.
- **The PREFERENCES sheet needs a thumb, and it is the newest thing on the phone** (installed
  2026-08-18). `⋯` on any exercise → Preferences. Two questions worth answering by using it: do the
  bar weights re-label the moment you tap Metric, and does opening it and tapping Save with no
  change feel like it should have done something? The second is deliberate — a no-change Save
  writes nothing at all, so the table only ever holds preferences somebody actually set.
- The tappable rest divider, the per-exercise menu and the sticky notes need a real thumb.
- ✅ **THE WARM-UP PERCENTAGES WERE WRONG AND ARE FIXED** (2026-08-19). The reference's
  `Warm-up Calculator` screen was in the screenshots all along (`IMG_3002.PNG`) and its `Default`
  formula is **40 / 60 / 80** at 5 / 5 / 3; ours ran at 50 / 60 / 75, fitted to a single 90 lb
  observation that both formulas reproduce (one by arithmetic, one via the bar floor). Drake
  generated a 135 lb ramp in the reference: **55 × 5, 80 × 5, 110 × 3**, where ours said
  70 / 80 / 100. Corrected, both cases pinned in `WarmupSetsTests`, and the ramp on the phone will
  now start lighter and finish heavier than it did.
- ⚠️ **A CONSEQUENCE OF THE RAMP FIX THAT IS YOUR CALL: the bar floor only applies if the exercise
  has a BAR TYPE set in Preferences.** `ActiveWorkoutScreen` passes
  `preference?.barType?.weight(in:)`, so an exercise you have never opened the `⋯` → Preferences
  sheet for has NO floor — and at 40% a light working weight now proposes a load lighter than the
  bar. A 90 lb bench with no bar type set generates **35** as its first warm-up, which cannot be
  loaded on a 45 lb bar. The old (wrong) 50% hid this by landing on 45 exactly.
  **The reference app appears to always know the bar.** Two ways to match it: default barbell-category
  exercises to an Olympic bar, or floor at the bar whenever the category is a barbell one. Neither
  is built — tell me which you want, or whether you would rather set bar types by hand.
- **Hammer Strength exercises.** The category is live in the app and the database; the actual
  movements land with the bigger exercise-library refresh I'm doing separately. Don't seed them.
- **Signing out with unpushed changes** (`06-sync.md`, Open question) is still undecided. The
  engine takes the only safe reading — it refuses to push if a DIFFERENT account signs in on a
  device that already claimed one. That is a refusal, not an answer. Ask before building on it.

## Known loose end

**Create Superset writes the data and draws nothing.** Recorded in `04-status.md` with both possible
resolutions. I chose to leave it and note it.

## Driving the simulator — this cost real time, three times now

- **Do not spend a third session on taps. Write an XCUITest.** `WarmupRampWalkthroughTests` is the
  worked example: it drives the screen from inside the app and attaches a screenshot at each step,
  so the only thing left for a human is looking. `04-status.md` has the two commands.
- **The iOS Simulator MCP panel crash-loops and stays dead.** `xcrun simctl` still works for
  boot / install / launch / screenshot, so you can always SEE.
- **Computer-use taps no longer land, and quitting the overlay apps does not help.** The click
  reaches the Simulator WINDOW — macOS hit-testing agrees, the app is frontmost, and keyboard
  shortcuts to it still work — but it never becomes a touch in the device. Wispr Flow was quit and
  nothing changed. Diagnosing this is not the fastest route to seeing a screen; the walkthrough
  test is.
- **Type digits as individual `key` presses** if you do drive it by hand. The `type` action is
  interpreted as press-and-hold and opens the accent picker.

## If you route anything to Ringer

> ⚠️ **RUN `~/ringer/scripts/check_selftest.sh` BEFORE EVERY MANIFEST. This is the single most
> useful thing learned on 2026-08-19.** Three runs in a row were recorded as MODEL FAILURES when
> the model was right and the CHECK was wrong — including one that was UNSATISFIABLE, because it
> demanded a conformance on a line that a second script (which the same check ran) required to be
> unchanged. No implementation could have passed.
>
> The cause: self-testing a check by watching it go RED against master proves the gate FIRES. It
> does not prove the gate can be SATISFIED, and all three bad checks passed that test. The script
> runs both halves — GREEN first (must pass on a tree that HAS the work), then RED — and refuses to
> bless a check otherwise. It was verified against the actual bug: restoring the bad assertion makes
> it print `GREEN FAILED — THE CHECK REJECTS CORRECT CODE. Do not launch.`
>
> **Assert the PROPERTY, never the SPELLING.** All three bugs were syntax demands standing in for a
> behaviour — a parameter's name, a declaration's placement. And the cost is not just a wasted
> retry: in one run the worker CONTORTED correct code to satisfy the bad regex, because a model
> optimises against the check rather than the goal.


- A green Ringer check means it **compiles**, not that it passes. Set `check_timeout_s` (~300) on
  any task whose check compiles, ~700 if it runs the SQL suite.
- **The swiftc check does not use the Xcode target's build settings**, so it misses
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. The transport passed it and then failed `xcodebuild`
  on eleven errors. Always run the real suite before believing a patch.
- **Workers can sometimes reach Docker and sometimes not** — when they can, `./supabase/tests/run.sh`
  is a genuinely executable check; when they cannot, the check says so and the orchestrator runs it.
  Either way the daemon has to be running on this machine first.
- **Write checks that are strict on substance and tolerant of format.** A check of mine demanded the
  literal text `0.4` and failed a worker that had written `40 / 100` — same behaviour, wasted retry.
- Run areas worth copying rather than rewriting: `~/ringer/run-areas/mcpstrength-transport/`,
  `mcpstrength-lww/`, `mcpstrength-warmup/`, `mcpstrength-equipment/`.

## Reading Apple's signing output — wrong twice in one session

Full version in `04-status.md` § "Shipping to a device". The three that cost the time:

- **`security find-identity` shows the certificate's common name, and the value in parentheses on
  an Apple Development certificate is NOT the team.** Read `OU` via
  `openssl x509 -noout -subject`. I built a whole false diagnosis on the display name.
- **A 7-day provisioning profile does not mean a free account**; a year-long one is what proves the
  membership is live.
- **Certificates and profiles are different objects.** Every failure was a stale profile while the
  certificates were fine, and "doesn't include signing certificate" means exactly that — the
  profile predates the certificate.

Apple limits recalled from memory were wrong too. Check the portal.

## Two reading habits that would have saved a day

- **`0 passed, 1 failed` from xcodebuild is not one broken test.** It is the test host crashing
  before bootstrap, with nothing verified at all. It looks trivial and is the worst result there is.
- **A screenshot of the reference app cannot tell you whether you are looking at generated or
  hand-edited data.** The warm-up ramp was built twice because an edited ramp had persisted into a
  later session and looked exactly like the generator's output.
