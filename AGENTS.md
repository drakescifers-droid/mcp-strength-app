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
| `docs/07-compliance.md` | Anthropic / ChatGPT directory listing, privacy pages, when in the phases |
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

## DRAKE DOES THE UI TESTING. Build it, put it on his phone, stop there.

**Standing rule, set 2026-08-18 after an afternoon of XCUITest runs cost about
$10 and settled nothing.** Do not drive the simulator to verify how something
looks or feels. Build, install to the device, and hand it over — he has the app
in his hand and answers in seconds what a harness spent an hour failing to
answer.

```
xcodebuild build -project MCPStrength/MCPStrength.xcodeproj -scheme MCPStrength \
  -destination 'platform=iOS,id=6902E742-268A-53A7-98B9-C9A034110AC8' \
  -derivedDataPath DerivedData DEVELOPMENT_TEAM=ZD2SRFJUPS -allowProvisioningUpdates
xcrun devicectl device install app --device 6902E742-268A-53A7-98B9-C9A034110AC8 \
  DerivedData/Build/Products/Debug-iphoneos/MCPStrength.app
```

That loop takes about a minute and is now the verification path for anything
visual or gestural. **This does not weaken the unit suite** — pure rules still
get tests, and `xcodebuild test -only-testing:MCPStrengthTests` still has to be
green before anything ships. What is retired is using XCUITest as a camera or
as a way to prove an interaction works.

The evidence, so nobody re-runs the experiment: the runner refused to launch
across two simulators, a clean `derivedDataPath`, and a full CoreSimulator
restart. When it did launch, a drag test showed nothing moving — which cannot
distinguish a broken fix from a gesture XCUITest never started, because
SwiftUI `.draggable` rides on UIDragInteraction. A control test written to
separate those two readings could not get past app launch. See
`bug-triage/BUGS.md`.

## Look at the running app

Three bugs passed a green suite and were caught only by launching it. Sign-in blocks every screen,
so there is a debug-only preview mode — `#if DEBUG` plus an explicit launch argument, so it cannot
exist in a Release build:

```
xcrun simctl launch <device> us.aiagent4.MCPStrength \
  -uiPreview 1 -uiPreviewFixtures 1 -uiPreviewTab history|profile|start|exercises|measure
```

`-uiPreviewTab` exists because the simulator MCP's tap action crash-loops — **do not build a
workflow on coordinate taps.** Computer-use taps on the Simulator window no longer work either: the
clicks land on the window, but nothing becomes a touch.

**To reach a screen a launch argument cannot, drive it from an XCUITest and attach screenshots.**
`MCPStrengthUITests/WarmupRampWalkthroughTests` is the worked example — it walks into a live
workout, generates a warm-up ramp, and photographs each step. It asserts almost nothing on purpose:
it is a camera, so the judgement stays with whoever looks at the pictures. That is how the live
workout screen was finally verified, and it is how the template editor should be.

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
| **Claude Code** (terminal or desktop) | Build and run the full unit suite, **and photograph any screen by driving it from an XCUITest** — see `WarmupRampWalkthroughTests` | Tap the simulator directly: the clicks land on the window and never become touches |
| **Cursor** | Same as Claude Code | Same |
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
