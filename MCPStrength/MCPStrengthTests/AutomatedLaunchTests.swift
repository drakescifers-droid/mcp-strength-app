//
//  AutomatedLaunchTests.swift
//  MCPStrengthTests
//
//  The guard that stops a test run from syncing to the live project.
//
//  **This file can prove its own subject, which almost no test can.** The
//  question is "is this process a test run", and this process IS a test run —
//  so the assertion is not a stand-in for the real condition, it is the real
//  condition, observed from inside it. If `isRunningTests` is ever false here,
//  it is false everywhere it matters, and running the suite goes back to
//  uploading a developer's simulator into `mcp-strength`.
//
//  That is worth stating because of how the bug got in. `MCPStrengthTests` is
//  app-hosted, so `xcodebuild test` launches the whole app — real store, real
//  keychain session, real sync triggers — and then runs the tests inside it.
//  The tests themselves never touched the network and never could have caught
//  it: the damage happened before the first test case ran. See
//  Auth/AutomatedLaunch.swift and docs/04-status.md.
//

import Testing
import Foundation
@testable import MCPStrength

struct AutomatedLaunchTests {

    // The whole point. Running is the precondition.
    @Test func aTestRunKnowsItIsATestRun() {
        // The comment must be a single string LITERAL — `Comment` is
        // ExpressibleByStringLiteral, so a `+` concatenation is an expression
        // and will not convert.
        #expect(
            AutomatedLaunch.isRunningTests,
            "Running inside XCTest, so a failure here means the sync guard is dead and the suite will push to the live project."
        )
    }

    // Both signals, asserted where they are actually read: inside a test body.
    //
    // `isRunningTests` is cached in a `static let`, so asserting only that
    // would pass on a stale true long after a signal had stopped working.
    // These recompute.
    @Test func bothSignalsAreReadableInsideATestBody() {
        #expect(AutomatedLaunch.isSetInEnvironment)
        #expect(AutomatedLaunch.isXCTestLoaded)
        #expect(AutomatedLaunch.isRunningTests)
    }

    // THE TRAP, pinned. The variable is present and its value is EMPTY, so
    // presence is the signal and the value is not.
    //
    // This is not hypothetical: the first version of this test asserted the
    // value was non-empty, failed, and was misread as "the variable disappears
    // once tests are running". It never disappears. A guard written as
    // `!(path ?? "").isEmpty` would report "not a test run" throughout a test
    // run — false in the one direction that lets a sync reach the live project.
    @Test func theVariableIsPresentButItsValueIsEmpty() {
        let path = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]
        #expect(path != nil, "Presence is the signal. If this fails, only NSClassFromString is holding the guard up.")
        #expect(path?.isEmpty == true, "The value is no longer empty. Harmless, but the trap documented in AutomatedLaunch is out of date.")
    }

    // Not a `#if DEBUG` check, and this pins why. Debug is true for the build
    // Drake runs on a simulator and the one on his phone, and BOTH should sync.
    // The distinction is "started by a test runner", not "built for debugging".
    @Test func itIsNarrowerThanADebugBuildCheck() {
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        // Both are true right now — this suite is a Debug test run. The point
        // is that they are different questions, and a Debug build that is NOT
        // a test run must still sync.
        #expect(isDebugBuild)
        #expect(AutomatedLaunch.isRunningTests)
    }

    // Preview mode and a test run are independent reasons not to sync, and the
    // guards are written as two separate lines for that reason. A test run has
    // no launch arguments, so preview mode alone would not have stopped it —
    // which is exactly why the live project got written to.
    @Test func previewModeWouldNotHaveCaughtThis() {
        #expect(!UIPreviewMode.isEnabled,
                "A test run carries no -uiPreview argument, so this is the gap AutomatedLaunch fills.")
        #expect(AutomatedLaunch.isRunningTests)
    }
}
