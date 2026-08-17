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

The one-line state: **sync works end to end, proven against the real project** — a workout logged
on a simulator reached `mcp-strength` with its exercise and set, and 43 library rows came down the
other way. Read out of the database, not inferred from the app.

## Next piece of work: a settings model

It unblocks the last two per-exercise menu items. The decisions are already made and recorded in
`04-status.md` — single global auto-generated warm-up config the user can then edit, 3 sets at
percentages, rounded to the nearest 5 lb. `exercise_preferences` exists as a table with no
SwiftData model behind it. After that: canonical units, before there is real history. Then Apple
Health.

**Read `04-status.md` § "What running it for real found" first.** Running sync against the real
project turned up four bugs in about an hour that 350 green tests could not see, and the reasons
they were invisible will recur. The short version: tests build their database from the local
migration files, a fake transport accepts anything a real policy would refuse, and
`0 passed, 1 failed` means the test host crashed and NOTHING ran.

## Waiting on me

- I still need to try the tappable rest divider, the per-exercise menu and the sticky notes on my
  actual phone — with a thumb, which is the part no simulator settles.
- **The live workout screen HAS now been driven end to end** (add exercise → weight and reps →
  tick → rest timer starts → Finish) and it behaves. **The template editor still has not been seen
  by anyone.**
- **An open decision I have not made: signing out with unpushed changes** (`06-sync.md`, Open
  question). The engine currently takes the only safe reading — it refuses to push if a *different*
  account signs in on a device that already claimed one, rather than guessing whose data it is.
  That is a refusal, not an answer. **Ask me before building on it.**

## Known loose end

**Create Superset writes the data and draws nothing.** Recorded in `04-status.md` with both possible
resolutions. I chose to leave it and note it.

## If you route anything to Ringer

- A green Ringer check means it **compiles**, not that it passes — a worker cannot run `xcodebuild`
  at all. Set `check_timeout_s` (~300) on any task whose check compiles.
- **Driving the simulator: the iOS Simulator MCP panel crash-loops and stays dead.** What works is
  `xcrun simctl` for boot/install/launch/screenshot plus computer-use for taps — but taps are
  blocked by any app owning an invisible full-screen overlay (Magnet and Wispr Flow both do here;
  Drake turned them off). Type digits as individual `key` presses: the `type` action gets
  interpreted as a press-and-hold and opens the accent picker.
- **The compile check does not use the project's build settings**, and that gap is not theoretical:
  the transport passed the swiftc check and then failed `xcodebuild` on eleven errors, because the
  Xcode target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and the standalone check does not.
  Always run the real suite before believing a patch.
- Workers CAN reach Docker, so `./supabase/tests/run.sh` is a real executable check for schema work
  — but the daemon has to already be running on this machine.
- Run areas from the sync work, with their manifests and checks, are worth copying rather than
  rewriting: `~/ringer/run-areas/mcpstrength-transport/` and `~/ringer/run-areas/mcpstrength-lww/`.
