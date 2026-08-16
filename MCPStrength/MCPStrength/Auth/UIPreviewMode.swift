//
//  UIPreviewMode.swift
//  MCPStrength
//
//  A debug-only way to see the app's screens without signing in.
//
//  ## The problem this solves
//
//  Sign-in is required up front, which is correct: every row the backend
//  accepts must be stamped with an owner. But it also means nobody can LOOK at
//  the app without an account — and this project's own hardest-won lesson is
//  that a green test suite does not catch layout, and three real bugs were
//  found only by launching the thing (docs/04-status.md).
//
//  The alternatives were worse. A shared test account is a permanent hole in
//  authentication traded for a temporary convenience, and it has to live
//  somewhere — a password in a repo, a note, a message. Handing credentials
//  around to look at a screen is not a workflow, it is a leak with a schedule.
//
//  ## Why this cannot reach a user
//
//  Two independent gates, either of which alone would be sufficient:
//
//    1. **`#if DEBUG`.** The code does not exist in a Release build. App Store
//       and TestFlight builds are Release, so there is nothing to disable,
//       misconfigure, or forget.
//    2. **An explicit launch argument.** Even in Debug it is off unless the
//       app is started with `-uiPreview`. Running from Xcode or installing a
//       debug build by hand does not enable it.
//
//  It grants no access to anything real: there is no session, no token, and
//  every request to Supabase would be rejected by row-level security. It skips
//  the GATE, not the authentication.
//
//  ## Usage
//
//      xcrun simctl launch <device> us.aiagent4.MCPStrength -uiPreview 1
//
//  Add `-uiPreviewFixtures 1` to also insert a demo workout with notes, warm-up
//  and drop sets, and RPE, so screens have realistic content to be judged on.
//  An empty screen tells you almost nothing about whether a layout works.
//

import Foundation

enum UIPreviewMode {

    /// Whether the sign-in gate should be skipped for this launch.
    ///
    /// Always `false` in a Release build — the check is compiled out entirely.
    static var isEnabled: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "uiPreview")
        #else
        return false
        #endif
    }

    /// Whether to insert demo content so screens are worth looking at.
    static var wantsFixtures: Bool {
        #if DEBUG
        return isEnabled && UserDefaults.standard.bool(forKey: "uiPreviewFixtures")
        #else
        return false
        #endif
    }

    /// Which tab to open on, so a screenshot of any screen needs no taps.
    ///
    /// Driving the simulator by coordinate is the least reliable part of this
    /// loop — the tap tooling has crashed out mid-session more than once — and
    /// a launch argument does not depend on it at all.
    ///
    /// `-uiPreviewTab profile|history|start|exercises|measure`
    static var initialTab: Int? {
        #if DEBUG
        guard isEnabled,
              let name = UserDefaults.standard.string(forKey: "uiPreviewTab")
        else { return nil }
        switch name.lowercased() {
        case "profile":   return 0
        case "history":   return 1
        case "start":     return 2
        case "exercises": return 3
        case "measure":   return 4
        default:          return nil
        }
        #else
        return nil
        #endif
    }

    /// A stand-in user id, so anything keyed by user (the sync status cursor)
    /// behaves consistently across preview launches instead of picking a new
    /// identity each time.
    static let previewUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!
}
