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

The one-line state: **the app is on Drake's phone, he is training on it, Phase 2's remaining
build work is DONE, Phase 3 Connect is LIVE, and Claude can write templates, build and
delete programs, and read history.** Claude connects at `https://mcp.mcpstrength.com`. Tools in:
`list_exercises`, `create_exercise`, `get_templates`, `get_template`, `create_template`,
`update_template`, `delete_template`, `create_program`, `delete_program`,
`get_workout_history`, `get_exercise_progress`. **There is no `log_workout` and there
must not be one** — Drake, 2026-08-20: logging from chat defeats the purpose of the app.
After that connect landed, a later session added `secondaryBodyParts` (Deadlift is back + legs)
and unblocked `ExerciseCategory.hammerStrength` in Swift (`6066f49`, `a8a1207`). The exercise
library was rebuilt 2026-08-20 (25 → 302). Sync is proven both ways.
Apple Health writes workouts (Watch energy preferred, backfill for what permission missed)
and the four HealthKit measurement types travel both ways. The custom keypad is done. What
Phase 2 still needs is a gym check, not a build: Watch-attach on a real session. Canonical
units done, gym-found bugs fixed, Preferences and the units setting SYNC, calorie rate on
both sides, warm-up ramp corrected to 40 / 60 / 80. Swift suite green, SQL suite green.

> **GitHub is live:** `https://github.com/drakescifers-droid/mcp-strength-app`.
> Commits go to `master`. Push to `origin` after committing — do not force-push.

> ✅ **THE KEYPAD IS COMMITTED.** Visual work, so it stayed here and did not go to Ringer.

> 🎨 **THE APP HAS FOUR THEMES AND SLATE IS GONE.** Gunmetal (default), Bunker, Orchid, Blush —
> Settings → Appearance, stored per device, not synced. Call sites did not change: `Theme.accent`
> still, resolving through a `Palette` now. One new token, `onSolid`, and the dark-chrome lock is
> off. `docs/04-status.md` § Themes has the rules and the one open decision (white on the Finish
> green is 2.08:1 — the fix is one value, not yet taken). Visual work, so it stayed here too.

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

1. **Phase 3 MCP surface is complete.** Connect is done; do not re-do OAuth or
   the site. **Read `docs/03-mcp-tools.md` for the contract and
   `docs/02-architecture.md` § Auth for how OAuth is wired.** `spike/` is frozen
   and is not a starting point. The server still queries Postgres **as the
   user**; never `supabaseAdmin`.

   **Do not add `log_workout`.** Drake, 2026-08-20: logging a session from
   chat defeats the purpose of the app. The phone is how training is recorded;
   Claude plans (templates, programs) and coaches (history, progress). That is
   a deliberate exception to `02`'s "anything the app can do, AI can do."

   Already in: `list_exercises`, `create_exercise`, `get_templates`,
   `get_template`, `create_template`, `update_template`, `delete_template`,
   `create_program`, `delete_program`, `get_workout_history`,
   `get_exercise_progress`. History returns `note` (instructions in) and
   `summary` (how it went), plus per-exercise notes and sticky notes — a
   response without those cannot tell a bad night from a downward trend.
   Name lookup on progress returns candidates and no series when several
   library rows match (the rebuilt 302-exercise library makes `"Lat Pulldown"`
   two real options). Deletes are soft, UUID-only, and annotated
   destructive; a program delete keeps its templates. `create_program` days
   may repeat (A, B, A). Linear progression is accepted as prose and
   **not executed** — the response says `executed: false`. `set_type`
   includes `restPause` (myo-reps use this; `rest_pause` / `myoRep` are
   rejected). Matcher and
   `list_exercises` return `secondary_body_parts`; `create_exercise` still
   only *creates* a primary body part. **The `mcp` Edge Function was
   redeployed 2026-08-20** with rest-pause as a set type.

   Deno tests for this folder need
   `deno test --allow-read --allow-net --allow-env supabase/functions/mcp`.
   A bare `deno test` reports five failures that are missing permissions,
   not a regression.

2. **Prove Watch-attach on a real session — a gym check, not a build.** Wired
   2026-08-19. Do not block Phase 3 on it. Decision is `HealthEnergyAction` /
   `energyAction`; HealthStore queries `[start, end]`, attaches, falls back to
   the estimate if attach throws.
   **Unverified:** whether HealthKit lets this app attach samples the Watch
   owns, and whether a Watch-on session in Apple Fitness now shows one energy
   number rather than two.

   Intended behaviour, still the contract:
   - Rate **none** → no energy sample, no attach.
   - Watch/Health already has `activeEnergyBurned` in `[start, end]` → attach
     those and **do not** write our estimate.
   - No existing samples → keep the flat-rate estimate.
   - If attaching **throws** → fall back to the estimate.

~~**Apple Health — import measurements FROM Health.**~~ **COMMITTED 2026-08-19**
(`e82f764`). Write, read toggle, both yellow banners. Still unverified on the
phone — see Waiting on me.

> ✅ **THE CUSTOM NUMBER KEYPAD IS DONE (2026-08-19), on the phone, Drake approved it after two
> layout fixes.** Do not rebuild it. Chip + pinned keypad, not
> `ToolbarItemGroup(placement: .keyboard)` and not a `UITextField` `inputView`. Writes still go
> through `commitWeight` / `commitReps`. Hosted on `ActiveWorkoutScreen`, `TemplateEditorScreen`,
> `RecordMeasurementSheet` via `.environment(keypad)` + `safeAreaInset`. Per-set rest **sheet
> removed**; divider tap focuses the keypad. `⋯` menu still uses `RestTimerSheet` for
> whole-exercise rest.
>
> **Reference facts, answered 2026-08-19:** weight has a decimal; rest and reps do not. − / + is
> **2.5 lb / 1 rep / 10 s**; metric weight step is **1.25 kg** (`WeightUnits.keypadStep`,
> separate from `plateIncrement` which is 5 lb / 2.5 kg and warm-up rounding only). Next on
> weight → same set's reps (no tick). Next on reps (not last set of exercise) → tick, start rest,
> focus rest bar. Next on rest → skip running rest, next set's weight (crosses into the next
> exercise). Next on last set of an exercise → tick, jump to **next exercise's first weight**
> (do not focus that exercise's rest). Last set of last exercise → complete and dismiss.
> Template: no ticks, no rest start; reps has a hyphen for ranges (`6-8`). First input after
> focus **replaces**.
>
> **Two bugs Drake caught, both fixed, do not re-introduce:**
> 1. Keypad filled the screen — Next had `maxHeight: .infinity` and `safeAreaInset` offered the
>    leftover height. Next is now two key-heights; keypad uses
>    `.fixedSize(horizontal: false, vertical: true)`.
> 2. Blue ring on the empty end of the rest bar — focused `RestProgressBar` stroked a
>    `Rectangle` with `Theme.accent` (same blue as the fill). Clip the fill first; focus ring is
>    **white** (`Theme.textPrimary`) via `RoundedRectangle.strokeBorder`.
>
> Pure rules: `Workout/NumberKeypadEditing.swift`. UI: `Views/NumberKeypad.swift`. Tests:
> `MCPStrengthTests/NumberKeypadEditingTests.swift`. Walkthrough UITests type via `keypad-N`
> buttons. Visual work, so it stayed here and did not go to Ringer.

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

- 🆕 **DEADLIFT NOW SHOWS UNDER BOTH LEGS AND BACK — check it on the phone.** Exercises tab →
  filter by Legs, then by Back; Deadlift should appear in both, and its row should read
  "Back, Legs". This is a new feature (`secondaryBodyParts`), asked for directly and built
  2026-08-19 — an exercise can train more than one body part now. Postgres migration applied and
  verified against the live project.
- ✅ **THE EXERCISE LIBRARY IS REBUILT AND ON YOUR PHONE — 25 exercises became 301** (2026-08-20,
  `20260820120000_library_rebuild.sql`). Your spreadsheet review is merged and the review file has
  done its job; `exercise-library-refresh/exercise-review.xlsx` is kept only as the record of what
  was decided. Applied to the live project and verified by reading rows back: 311 rows, 301 live,
  10 tombstoned.
  > **What to check on the phone:** Exercises tab. Everything should be there, named consistently
  > (`Bench Press (Hammer Strength)`, not `HS Bench Press`), with no generic leftovers — searching
  > "Lat Pulldown" should offer Cable and Machine rather than one bare entry. **Chin Up and Pull Up
  > are now separate exercises** and neither is an alias of the other.
  > **Two I would still like your eyes on**, both flagged during the review and both kept as you
  > left them: `Row (Hammer Strength)` may be the same machine as `Seated Low Row (Hammer
  > Strength)` or `Single Arm Row (Hammer Strength)` under a third name; and `Cable Curl` /
  > `Bicep Curl (Cable)` are both in the library as separate exercises. Say the word and either
  > gets merged.
  > **Names I could not identify and left exactly as written**: `Baby Shark`, `Baby Shark Ab
  > Circuit`. They are in the library with guessed body parts; tell me what they are and I will
  > fix them properly.
  > ✅ **`Massbuilder Back` is confirmed** (Drake, 2026-08-20): a back machine at his gym. Already
  > filed Back / Machine, so nothing changed — the guess was right. Kept as `Massbuilder Back`
  > rather than forced into the `Movement (Equipment)` convention, because the MOVEMENT is still
  > unknown; `Row (Massbuilder)` or `Pulldown (Massbuilder)` would be the convention-consistent
  > name IF he says which it is. Not a Hammer-Strength-style category: that one earned its own
  > category because the loading style spans brands, where this is one machine.
  > ✅ **`Lat Wide Prayer` is resolved** — renamed to `Lat Prayer Wide Grip` and joined by a new
  > `Lat Prayer Narrow Grip` (2026-08-20, `20260820130000_lat_prayer_grips.sql`, library now 302).
  > The rename kept the exercise's original id, verified in place on the live project by checking
  > the row kept its original `created_at`. Both are Back / Machine — say so if the narrow-grip one
  > should be anything else.
- ✅ **OAUTH ON THE LIVE PROJECT, dashboard 2026-08-19.** OAuth 2.1 on, dynamic
  registration on. MCP function deployed. Allow page is the site in `web/`.
- ✅ **MCPSTRENGTH.COM LIVE, 2026-08-19.** Pages on Cloudflare, nameservers
  at Namecheap, Site URL `https://mcpstrength.com`, Authorization Path
  `/oauth/consent`, redirect URLs for apex and www. Allow page preview is
  `https://mcpstrength.com/oauth/consent`. Claude's connector URL is
  **https://mcp.mcpstrength.com**. Tools so far: `list_exercises`,
  `create_exercise`, `get_templates`, `get_template`, `create_template`,
  `update_template`, `delete_template`, `create_program`, `delete_program`,
  `get_workout_history`, `get_exercise_progress`. GitHub:
  `https://github.com/drakescifers-droid/mcp-strength-app`.
- 🆕 **WATCH-ATTACH ON A REAL SESSION.** Wear the Watch, finish a real-length
  session, look at Apple Fitness: one energy number, not our estimate sitting
  on top of the Watch's. Does not block Phase 3.
- 🆕 **MEASUREMENTS FROM APPLE HEALTH, a couch check.** Profile → gear → Apple
  Health. Allow the new **read** prompt (Weight, Body Fat, calories, Waist).
  Add from Health should land a Weight on the Measure tab, and a Weight logged
  here should not come back as a second copy.
- ✅ **FOUR QUESTIONS ABOUT THE KEYPAD, answered 2026-08-19 from the reference
  app, AND THE KEYPAD IS ON THE PHONE.** Weight has a decimal; rest and reps do
  not. − / + steps **2.5 lb / 1 rep / 10 seconds**. Next on reps of a non-last
  set ticks the set, starts rest, and focuses the timer; Next on the timer skips
  rest and moves to the next set's weight; Next on the last set of an exercise
  ticks it and jumps to the next exercise's weight. Metric keypad step is 1.25 kg
  (matching smallest change plate), not a conversion of 2.5 lb. Drake: “That
  works great” after the Next-height and rest-bar outline fixes.
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
- **The template editor has still never been looked at by anyone.** It is the last
  completely unseen screen. Build, install, open a template on the phone, and
  tell me. Do not drive XCUITest or the simulator as a camera — see
  `AGENTS.md` § "DRAKE DOES THE UI TESTING".
- ✅ **SYNC IS PROVEN IN BOTH DIRECTIONS against the live project** (2026-08-19). A settings
  change uploaded — `POST /rest/v1/app_settings → 200` — and a full pull of all thirteen tables
  came back 200. Read out of the project's own request logs, not inferred from the UI.
- ✅ **APPLE HEALTH WROTE A WORKOUT** (2026-08-19), **and it wrote energy.** A sub-minute test
  session appeared in Apple Fitness with **0.25 kcal** — the flat rate scaled by duration, not a
  fabricated zero. What is still unverified:
  1. **double counting against a worn Watch** on a real-length session. `None` is the honest
     setting until that is answered;
  2. finishing the SAME workout twice must produce ONE entry — the external-uuid lookup has
     never been watched on a device.
- **The calorie rate picker may still never have been tapped** (Settings → Apple Health → Workout
  Active Calories Rate). Default Medium is what wrote the 0.25 kcal. Worth saying whether the row
  title reads as too long on the phone; it is the reference app's own wording and it wraps to two
  lines. It only appears once Health is allowed — deliberate.
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
- ~~**Hammer Strength exercises.**~~ **UNBLOCKED 2026-08-19** — the category is live everywhere
  now (app, database, AI server) and the 11 real Hammer Strength rows in the review spreadsheet
  are retagged and renamed. The actual seed-file merge still lands with the bigger
  exercise-library refresh, once your review pass on the spreadsheet is done.
- **Signing out with unpushed changes** (`06-sync.md`, Open question) is still undecided. The
  engine takes the only safe reading — it refuses to push if a DIFFERENT account signs in on a
  device that already claimed one. That is a refusal, not an answer. Ask before building on it.

## Known loose end

**Create Superset writes the data and draws nothing.** Recorded in `04-status.md` with both possible
resolutions. I chose to leave it and note it.

## Driving the simulator — retired as a way to see the app

**Drake tests on the phone.** Build, install, hand over. Do not drive the
simulator or write XCUITest to judge how something looks or feels — see
`AGENTS.md` § "DRAKE DOES THE UI TESTING". An afternoon of XCUITest runs
cost ~$10 and settled nothing; the install loop is about a minute.

What is still true if you ever *do* touch the simulator:

- **The iOS Simulator MCP panel crash-loops and stays dead.** `xcrun simctl`
  still works for boot / install / launch.
- **Computer-use taps do not become touches.** The click reaches the Simulator
  window and never lands in the device. Do not diagnose this; install to the
  phone instead.
- **Type digits as individual `key` presses** if you ever type into it. The
  `type` action is interpreted as press-and-hold and opens the accent picker.

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
  `mcpstrength-lww/`, `mcpstrength-warmup/`, `mcpstrength-equipment/`,
  **`mcpstrength-preferences/`** (the compile check to copy for Watch energy).

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
