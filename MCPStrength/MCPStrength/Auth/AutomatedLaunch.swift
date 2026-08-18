//
//  AutomatedLaunch.swift
//  MCPStrength
//
//  Whether this process is a test run rather than a person using the app.
//
//  ## Why this exists — running the tests uploaded to the live project
//
//  `MCPStrengthTests` is APP-HOSTED (`TEST_HOST = MCPStrength.app` in the
//  project), which is the ordinary arrangement for a unit-test bundle and has
//  a consequence nobody had looked at: **`xcodebuild test` launches the real
//  app.** Not a stub, not a harness — `MCPStrengthApp`, with its scene, its
//  `.task` blocks, and the shared `ModelContainer` pointed at the simulator's
//  actual store. `auth.start()` then finds the session sitting in the keychain
//  from the last time anybody signed in, `AuthController` reports `.signedIn`,
//  and the launch trigger runs a full sync against `mcp-strength`.
//
//  So running the unit suite pushed a developer's simulator into the live
//  database, and would have pulled the live database back down into it. It is
//  how ten rows were double-converted on 2026-08-18: the client pushed
//  already-converted kilograms during a test run, and the SQL migration then
//  converted them again (`docs/04-status.md`).
//
//  **The tests themselves are not the problem and never touch the network.**
//  They use in-memory containers and a fake transport, exactly as designed. The
//  app around them is what syncs, and no test could ever have caught that,
//  because the damage happens *outside* the code under test — before the first
//  test case runs.
//
//  ## Why not a `#if DEBUG`
//
//  `DEBUG` is true for every ordinary development build, including the one
//  Drake looks at on a simulator and the one installed on his phone. Those
//  SHOULD sync. The distinction being drawn is not "debug build", it is "this
//  process was started by a test runner".
//
//  ## The environment variable is set to an EMPTY STRING
//
//  `XCTestConfigurationFilePath` is the usual way to ask this question, and the
//  trap is in its value rather than its presence: under this scheme it is
//  present and **empty**. So `!= nil` is the correct test and anything that
//  looks at the value is not — a reasonable-looking
//  `!(path ?? "").isEmpty` reports "not a test run" in the middle of a test
//  run, which is the exact direction that lets a sync through.
//
//  That cost a wrong diagnosis on the way in: the first version of the test
//  below asserted the value was non-empty, failed, and was read as "the
//  variable disappears by the time a test body runs". It does not. It is there
//  the whole time, empty the whole time. `AutomatedLaunchTests` now pins both
//  halves of that so the next reader does not have to re-derive it.
//
//  ## Why a second signal anyway
//
//  `NSClassFromString("XCTestCase")` asks the same question a different way:
//  XCTest is injected into the host process to run the bundle and stays loaded
//  for the life of the process, and a launch by a person never loads it. It is
//  kept because it depends on nothing about how a variable happens to be
//  spelled or populated, and this guard's failure mode is silent — nothing
//  anywhere reports "a test run just synced to production". Either signal alone
//  is sufficient, so they are OR-ed.
//

import Foundation

enum AutomatedLaunch {

    /// Whether an XCTest runner started this process.
    ///
    /// True inside `xcodebuild test` — for the unit suite, which is hosted by
    /// the app, and for the UI tests' target application. False for every
    /// launch by a person, in Debug and Release alike.
    ///
    /// > **This is a guard against side effects, not a feature flag.** Do not
    /// > branch app BEHAVIOUR on it. A screen that renders differently under
    /// > test is a screen the tests are not testing. The only legitimate use is
    /// > refusing to reach outside the process — network, notifications,
    /// > anything with an effect that outlives the run.
    static let isRunningTests: Bool = isSetInEnvironment || isXCTestLoaded

    /// Whether XCTest's configuration variable is PRESENT.
    ///
    /// Presence only. The value is an empty string under this scheme, so
    /// nothing may inspect it — see the file comment.
    static var isSetInEnvironment: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Durable for the life of the process once a test bundle is hosted.
    static var isXCTestLoaded: Bool {
        NSClassFromString("XCTestCase") != nil
    }
}
