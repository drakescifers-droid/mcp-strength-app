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
two items.** Sync proven end to end, canonical units done, a round of gym-found bugs fixed,
per-exercise Preferences — model and sheet — landed, the settings screen makes the global weight
unit changeable, and **both settings and preferences now SYNC** (table live on the project, client
conformances on). Swift suite green, SQL suite green.

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

1. **A CLEARED FIELD DOES NOT TRAVEL — eleven row structs, and it is silent.** Swift's synthesised
   encoder omits nil optionals and an upsert only updates the columns its payload mentions, so
   clearing a value never reaches the server and the next pull puts it back. Unfiling a template,
   deleting a workout note, removing a template set's weight: all silent no-ops today.
   `docs/06-sync.md` § "A nil field must travel as an explicit `null`" has the argument and the
   worked fix.
   > **The two rows added on 2026-08-18 are already correct** (explicit `encode`), because the
   > Preferences sheet made clearing reachable immediately. The remaining eleven are mechanical but
   > change every payload the app sends, so they want their own change and their own tests.
   > **Found by the REAL suite after the Ringer check passed** — a compile cannot see it, and every
   > existing round-trip test builds rows with values present. The absence is the case nobody wrote.
2. **Apple Health.** Last thing in Phase 2, and no longer blocked — the developer account is live.
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
- ⚠️ **SYNC HAS RUN AGAINST THE LIVE PROJECT AND FAILED ONCE, 2026-08-19 — cause found and
  fixed, but the SUCCESS is still unwitnessed.** `permission denied for table app_settings`: a
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
