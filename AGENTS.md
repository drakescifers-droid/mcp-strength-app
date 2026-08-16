# Working in this repo

Read this before changing anything. It is short on purpose — it routes you to the real
documentation and lists only the rules that are expensive to get wrong.

**Read `docs/04-status.md` first.** It says what is built, what is half-built, and what was skipped
deliberately, and it opens with the current state in one line. Its table points at the other six
docs — the data model, the architecture, the MCP tool contract, the database, and sync. Do not
re-derive from the code what those files already explain, and do not duplicate them into new files.

The app is `MCPStrength/` — a native iOS workout logger, SwiftData locally, syncing to Supabase.
Phase 2 is in progress: everything around sync exists, but **no row has ever travelled**.

---

## Rules that are expensive to get wrong

1. **Never `context.delete` a synced model. Use `SoftDelete`.** A real delete cannot reach a device
   that was offline when it happened, so the row comes back on the next pull. Tombstones carry the
   delete like any other edit. The one deliberate exception is discarding unticked sets at Finish,
   and it is safe only because unfinished workouts are ineligible to push — see `PushFilter`.

2. **Every `@Model` property needs a declaration-level default or optionality** — `var x: Int = 0`,
   never a default supplied in `init`. SwiftData's lightweight migration cannot see initializer
   defaults, and the app dies on launch when opening a store written before the property existed.
   **Unit tests cannot catch this**: they build in-memory containers from the current schema, so
   there is never an old store to migrate. The two UI tests exist for exactly this.

3. **Call `markEdited()` at every mutation site**, or the row silently stops syncing once the
   engine starts clearing flags. There is a known, deliberate gap here — read the trap list in
   `docs/04-status.md` before adding calls, so you extend the fix rather than half-repeat it. Do
   **not** call it when applying a row pulled from the server: that dirties everything a pull
   touches and the two ends never settle.

4. **Never display a fabricated zero.** "0 PRs", "0 inches" for an unmeasured body part, or a chart
   that drops empty weeks all read as data rather than absence. Show nothing instead.

5. **Never classify an error by `String(describing:)`.** Match on the type — `error as? URLError`,
   then the code. A `URLError` does not contain the word "network", so string matching produces
   branches that can never fire and messages that are both useless and false.

6. **Prefer `.sheet(item:)` over `.sheet(isPresented:)` whenever a sheet needs a value.** Companion
   `@State` written from inside a `Menu` action is lost, and the resulting bug passes a green test
   suite — a check can assert structure, not presentation-state timing.

7. **Do not run the test suite against the production Supabase project.** `supabase/tests/run.sh`
   exercises the schema against a throwaway container.

---

## Look at the running app

Three bugs passed a green suite and were caught only by launching it. Sign-in blocks every screen,
so there is a debug-only preview mode — `#if DEBUG` plus an explicit launch argument, so it cannot
exist in a Release build:

```
xcrun simctl launch <device> us.aiagent4.MCPStrength \
  -uiPreview 1 -uiPreviewFixtures 1 -uiPreviewTab history|profile|start|exercises|measure
```

`-uiPreviewTab` exists because the simulator MCP's tap action crash-loops — **do not build a
workflow on coordinate taps.** It also means the live workout screen and the template editor have
never been visually verified by an agent. If you are running inside Xcode with a simulator, you can
reach them, and that is the single most useful thing you can do here that other agents cannot.

## Build and test

```
xcodebuild build -project MCPStrength/MCPStrength.xcodeproj -scheme MCPStrength \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath DerivedData
```

Swap `build` for `test -only-testing:MCPStrengthTests` to run the unit suite. Check
`xcrun simctl list devices available` if that device name has moved on.

---

## Working alongside other agents

Claude Code, Cursor, and Xcode's agent all operate on this one working tree. They cannot see each
other's context — this file and `docs/` are the only things passing between them.

- **One agent at a time, and commit before switching.** There are no branches; whoever saves last
  wins, silently.
- **Builds collide.** Everything shares `DerivedData`. Do not run `xcodebuild` while a Ringer check
  is running — the compile check uses ~36s of a hard-coded 60s budget — and watch for Xcode
  building in the background.
- **Ringer routing is about cost, not capability** (`docs/04-status.md`). Mechanical, checkable work
  goes to a cheaper worker under supervision; **visual work does not** — a check cannot assert
  whether something looks right.

## Conventions

- Commits go to `master`; this is a solo repo with no branch workflow.
- **Commit messages carry the reasoning, not just the diff.** `docs/04-status.md` explicitly defers
  "what changed and why" to `git log`, which only works if the messages actually say why.
- Design questions that are genuinely open belong in the relevant doc's Open questions section, not
  in status.
- Drake is not a developer. Code, commits, and docs stay technical; **explanations in chat should be
  in plain language.**
