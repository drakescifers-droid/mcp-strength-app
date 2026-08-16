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

The one-line state: **the transport is built, wired and tested — and it has never once talked to
the real project.** Every layer under it is green against a fake transport and a throwaway
Postgres. That is not the same as a row having travelled.

## Next piece of work: one real round trip

Sign in on a simulator, log a workout, and confirm the rows land in `mcp-strength`. Until that
happens the honest claim is "it should work", which is exactly the kind of claim `04-status.md`
exists to stop us making. Watch for the three things a fake cannot catch:

1. **The claim step** on a store that predates the sign-in gate — the store on this machine is one.
2. **RLS rejecting a row the client thought it owned.**
3. **Encodings Postgres refuses** that the fake happily accepted (enums, dates, nulls).

**Do not trust the Profile tab's backup state as evidence.** It reports what the engine believes.
Confirming a row exists means looking at the row, in the project.

After that: a settings model (unblocks the last two menu items — my warm-up decisions are already
recorded), then canonical units before there is real history.

## Waiting on me

- I still need to try the tappable rest divider, the per-exercise menu and the sticky notes on my
  actual phone. The live workout screen and the template editor have **never** been visually
  verified by anyone — preview mode lands on a tab and the tap tooling crash-loops.
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
- **The compile check does not use the project's build settings**, and that gap is not theoretical:
  the transport passed the swiftc check and then failed `xcodebuild` on eleven errors, because the
  Xcode target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and the standalone check does not.
  Always run the real suite before believing a patch.
- Workers CAN reach Docker, so `./supabase/tests/run.sh` is a real executable check for schema work
  — but the daemon has to already be running on this machine.
- Run areas from the sync work, with their manifests and checks, are worth copying rather than
  rewriting: `~/ringer/run-areas/mcpstrength-transport/` and `~/ringer/run-areas/mcpstrength-lww/`.
