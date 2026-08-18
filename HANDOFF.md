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

The one-line state: **sync is proven end to end, and canonical units are DONE — storage is
kilograms, every screen converts, and the pounds that were already stored have been converted on
both sides.** Swift suite green, SQL suite green.

> **Every stored weight is now KILOGRAMS.** `WorkoutSet.weight`, `TemplateSet.weight` and
> `Workout.totalVolume`. Never print one without converting it — `PreviousText.weightText` or
> `WeightUnits.displayed` — and never write one without `WeightUnits.kilograms(from:in:)`.

> ⚠️ **Two things are outstanding on the live project. Run `supabase migration list` first.**
> `20260818120000_weights_to_kilograms.sql` is applied. `20260818140000_repair_double_converted_weights.sql`
> may not be — it repairs ten rows that the first one halved, because a client pushed already-
> converted rows into the five-minute window between the two. `04-status.md` has the full story, including the
> cause: **running the unit suite was syncing to the live project**, because the test bundle is
> hosted by the app, so `xcodebuild test` launched the real app signed in. Fixed in
> `Auth/AutomatedLaunch.swift` and pinned by a test.

## Next piece of work, in order

1. **Per-exercise Preferences.** Design decided and approved — read `docs/06-sync.md` §
   "Per-exercise preferences get their own local model" before writing any of it. The four fields
   move off `Exercise` into their own `ExercisePreference` model, which is how the server already
   stores them and dissolves three of the four sync problems rather than working around them. The
   sheet is two rows (Weight Unit, Bar Type), not four.
   > **The display half is already built.** Four call sites pass `exercise.weightUnitOverride` into
   > `WeightUnits.displayUnit(override:global:)`; `04-status.md` names all four. Changing what they
   > pass is the whole wiring job.
2. **The settings screen's units rows**, off the profile page. Until these exist the unit can never
   be changed, **so the kilogram display path has never been seen on a screen** — it is covered by
   tests and nothing else.
3. **Sync `AppSettings`** — no Postgres table yet, and one row per user means the key is `user_id`.
   Same per-entity conflict-target work `06-sync.md` already specifies for `exercise_preferences`.
   > **Do not sweep `StoreMigrations` into it.** It sits next to `AppSettings` and is the opposite
   > kind of thing: a device-local record of which data migrations this store has run.
4. **Apple Health.** Last thing in Phase 2, and no longer blocked — the developer account is live.
   Then Phase 3, the real MCP server, which Drake has confirmed is in scope for v1.

> **`Add Warm-up Sets` has been looked at and is done.** It found one real bug — the Previous
> column followed row position, so a generated ramp moved your last working set onto a warm-up.
> Fixed; the reasoning is in `04-status.md` § "What looking at the warm-up ramp found".

## Waiting on me

- **The bar on logging real workouts is LIFTED** — the units conversion has landed, which is the
  only thing it was ever waiting on. What still blocks the phone is the item below.
- **Apply the repair migration** (`20260818140000`) if `supabase migration list` says it is not
  there. It rewrites ten rows in `mcp-strength`, so ask me first. The values it restores are all
  round plate loads from the preview fixtures (95 / 135 / 155 / 185 / 35 lb), which is how they
  were identified in the first place.
- **Work out what pushed to the live project on 2026-08-18 at 13:35 CDT.** Nothing in the session
  was meant to sync. The leading hypothesis is that `xcodebuild test` launches the app as its own
  test host, signed in, with no preview flag. If that is right it needs fixing before anyone trains
  on this: running the tests would upload whatever is in the simulator.
- **The App Store Connect app record does not exist yet**, so nothing can be uploaded even though
  the build is ready. Only I can create it. Ask before running any upload; it is outward-facing.
- **The template editor has still never been looked at by anyone.** It is the last completely
  unseen screen — and it no longer needs your hands: point
  `MCPStrengthUITests/WarmupRampWalkthroughTests` at it and read the screenshots.
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
