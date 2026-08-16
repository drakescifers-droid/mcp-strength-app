# Working in this repo

Read this before changing anything. It is short on purpose — it routes you to the real
documentation and lists only the rules that are expensive to get wrong.

**Read `docs/04-status.md` first.** It says what is built, what is half-built, and what was skipped
deliberately, and it opens with the current state in one line. Do not re-derive from the code what
these files already explain, and do not duplicate them into new files:

| Doc | Answers |
|---|---|
| `docs/01-data-model.md` | Why the schema is shaped this way |
| `docs/02-architecture.md` | Why Supabase, how sync works, observability |
| `docs/03-mcp-tools.md` | The MCP tool contract |
| `docs/04-status.md` | **What is built, what is half-built, what was skipped on purpose** |
| `docs/05-database.md` | Why the Postgres schema differs from the SwiftData one |
| `docs/06-sync.md` | How sync works on the client, and how it is made visible |
| `~/ringer/docs/MODEL-NOTES.md` | Which worker models are good at what |

The app is `MCPStrength/` — a native iOS workout logger, SwiftData locally, syncing to Supabase.
Phase 2 is in progress: everything around sync exists, but **no row has ever travelled**.

## The design reference

Five folders of screenshots at the repo root — `Home screen/`, `Workout screen/`, `Edit Template/`,
`Other main screens/`, `Settings accessed from profile page/` — are the visual spec, and they are
tracked in git. The docs refer to them as "the reference". **Look at them before designing any
screen**, particularly if you can display images; most agents working here cannot reach the running
app, and this is the closest thing to seeing it.

They are a reference, **not a specification to match pixel for pixel.** Several divergences are
deliberate and reasoned in `docs/04-status.md` — Archive and Share are absent from the template menu
because their behaviour was never designed, the "enable Health" hint is absent because it would
point at a setting that does not exist, and PR counts are absent because a hardcoded zero reads as
*you set no records*. **Check the docs before adding something because the reference has it.**

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

**Work out which one you are, because the capabilities genuinely differ:**

| If you are… | You can | You cannot |
|---|---|---|
| A **Ringer worker** | Typecheck via `verify_compile.sh` | Run `xcodebuild` **at all** — the sandbox forbids it — so you can never run a test or see the app. Green means it compiles. |
| **Claude Code** (terminal or desktop) | Build and run the full unit suite with `xcodebuild` | Reach the live workout screen or the template editor — preview mode lands on a tab and the tap tooling crash-loops |
| **Cursor** | Same as Claude Code | Same blind spot |
| **Xcode's agent** | Build, run the tests, **and run the app on a simulator and look at it** | — |

If you are the agent inside Xcode, that last row is the point. Two screens — the live workout screen
and the template editor — have never been visually verified by anyone, and every UI bug found in this
project so far was found by looking at the running app rather than by a passing test. Checking a
screen against `docs/04-status.md`'s "Not verified" list is worth more here than another green suite.

- **One agent at a time, and commit before switching.** There are no branches; whoever saves last
  wins, silently.
- **Builds collide.** Everything shares `DerivedData`, so concurrent builds slow each other down —
  watch for Xcode building in the background. Ringer tasks whose check compiles need
  `check_timeout_s` set (~300) in the manifest, or a slow check is killed and scored as the model
  failing.
- **A green Ringer check means it COMPILES, not that it works.** `xcodebuild` cannot run inside a
  Ringer worker's sandbox at all, so the check is a two-stage `swiftc` typecheck that never executes
  a test. Run the real suite outside the sandbox before trusting a worker's output.
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
