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

The one-line state: **Phase 2 — everything around sync is built and tested, and nothing calls any of
it.** No row has ever left my phone. Until the transport lands, don't log training I'd be upset to
lose.

## Next piece of work: the transport

The network calls and the run loop. Two things must land **with** it, not after:

1. **The missing `markEdited` calls.** See the trap list in `04-status.md` — set-level mutations on
   the workout screen (weight, reps, the completion tick) plus renames and reorders elsewhere. The
   transport is what arms that failure, so fixing it afterwards leaves a window where the app says
   my data is backed up when it isn't.
2. **An open decision I haven't made:** whether `TemplateEditorScreen.save()`'s diffing fix rides
   along. Today it replaces a template's whole subtree on every save, which would tell the server
   everything was deleted and recreated with new ids. **Ask me.**

After that: a settings model (unblocks the last two menu items — my warm-up decisions are already
recorded), then canonical units before there is real history.

## Waiting on me

I still need to try the tappable rest divider, the per-exercise menu and the sticky notes on my
actual phone. The live workout screen and the template editor have never been visually verified by
anyone — preview mode lands on a tab and the tap tooling crash-loops.

## Known loose end

**Create Superset writes the data and draws nothing.** Recorded in `04-status.md` with both possible
resolutions. I chose to leave it and note it.

## If you route anything to Ringer

A green Ringer check means it **compiles**, not that it passes — it cannot run tests. Set
`check_timeout_s` (~300) on any task whose check compiles. That field is new, and is currently
uncommitted in `~/ringer` alongside unrelated edits of mine.
