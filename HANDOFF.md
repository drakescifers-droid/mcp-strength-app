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

The one-line state: **sync is proven end to end against the real project, and Phase 2 is down to
three things.** 370 Swift tests green, SQL suite green, all 8 migrations applied and verified
remote == local.

## Next piece of work, in order

1. **LOOK AT `Add Warm-up Sets` ON A REAL SCREEN.** It is built, wired into both the live workout
   screen and the template editor, and covered by tests — and nobody has ever watched it run. Two
   things a test cannot judge: whether the generated ramp *looks* right in the set list, and
   whether a second tap visibly REPLACES the warm-ups rather than piling more on. Every UI bug
   found in this project so far was found this way.
2. **Per-exercise Preferences.** The design is decided and approved — read
   `docs/06-sync.md` § "Per-exercise preferences get their own local model" before writing any of
   it. Short version: the four fields move off `Exercise` into their own `ExercisePreference`
   model, which is how the server already stores them and which dissolves three of the four sync
   problems rather than working around them. The sheet itself is only two rows (Weight Unit, Bar
   Type), not four.
3. **Canonical units**, before there is real history (`05`). Also unblocks the *Default* option in
   the weight-unit picker, and `BarType.weight` is where lb→kg has to happen — a kg user wants a
   20 kg Olympic bar, not 45 lb.
4. **Apple Health.** Last thing in Phase 2. Then Phase 3, the real MCP server, which Drake has
   confirmed is in scope for v1.

## Waiting on me

- **The template editor has still never been looked at by anyone.** It is the last completely
  unseen screen. The live workout screen HAS now been driven end to end (add exercise → weight and
  reps → tick → rest timer → Finish) and behaves.
- The tappable rest divider, the per-exercise menu and the sticky notes need a real thumb.
- **Hammer Strength exercises.** The category is live in the app and the database; the actual
  movements land with the bigger exercise-library refresh I'm doing separately. Don't seed them.
- **Signing out with unpushed changes** (`06-sync.md`, Open question) is still undecided. The
  engine takes the only safe reading — it refuses to push if a DIFFERENT account signs in on a
  device that already claimed one. That is a refusal, not an answer. Ask before building on it.

## Known loose end

**Create Superset writes the data and draws nothing.** Recorded in `04-status.md` with both possible
resolutions. I chose to leave it and note it.

## Driving the simulator — this cost real time, twice

- **The iOS Simulator MCP panel crash-loops and stays dead.** What works: `xcrun simctl` for
  boot / install / launch / screenshot, plus computer-use for taps.
- **Taps need the Simulator window frontmost and unobstructed.** They are blocked by any app owning
  an invisible full-screen overlay (Magnet and Wispr Flow both do — Drake turns them off), and by a
  fullscreen app on top (Chrome). `simctl io screenshot` still captures the device either way, so
  you can SEE without being able to TAP.
- **Type digits as individual `key` presses.** The `type` action is interpreted as press-and-hold
  and opens the accent picker.

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

## Two reading habits that would have saved a day

- **`0 passed, 1 failed` from xcodebuild is not one broken test.** It is the test host crashing
  before bootstrap, with nothing verified at all. It looks trivial and is the worst result there is.
- **A screenshot of the reference app cannot tell you whether you are looking at generated or
  hand-edited data.** The warm-up ramp was built twice because an edited ramp had persisted into a
  later session and looked exactly like the generator's output.
