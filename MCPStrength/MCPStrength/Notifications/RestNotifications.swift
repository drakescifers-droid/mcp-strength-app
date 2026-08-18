//
//  RestNotifications.swift
//  MCPStrength
//
//  Delivering the "rest is over" alert.
//
//  A LOCAL notification, not a push one, and the distinction is the whole
//  design. A push would need APNs, a device token, and something on the server
//  to send it — a network round trip to tell you about a countdown the phone in
//  your hand is already running. A local notification is scheduled by the app
//  for an absolute instant and fires with the phone in airplane mode in a
//  basement gym, which is exactly where it needs to work.
//
//  ## Behind a protocol, for the same reason the sync transport is
//
//  `docs/02-architecture.md` puts `SyncClient` behind a protocol because an
//  engine reachable only through a live project is an engine nobody tests. The
//  same is true here twice over: `UNUserNotificationCenter` cannot be driven in
//  a unit test, and asking for authorization inside one would block on a
//  system prompt that never appears. So the view depends on the protocol, the
//  rule that decides WHAT to schedule is pure (`RestNotificationRule`), and
//  this file is the thin part that cannot be tested and therefore contains as
//  little judgement as possible.
//
//  ## When permission is asked for
//
//  On the first rest that would actually schedule something — not at launch.
//  Asking at launch, before the user has seen a timer, is asking about a
//  feature they have no context for, and a denied prompt is not re-askable
//  from inside the app: iOS shows it once, and after that the only route is
//  Settings. Asking at the moment a countdown starts means the request arrives
//  when its purpose is on screen.
//

import Foundation
import UserNotifications

/// Schedules and cancels the single pending rest alert.
///
/// Single deliberately: only one rest runs at a time (`restingSetID` is one
/// value), so a fixed identifier makes "replace whatever was pending" the
/// natural operation rather than something requiring bookkeeping.
protocol RestNotificationScheduling: Sendable {
    /// Ensure exactly one notification is pending, firing at `date`.
    func schedule(at date: Date, exerciseName: String?) async
    /// Ensure nothing is pending.
    func cancel() async
}

// MARK: - The real one

/// `UNUserNotificationCenter` behind the protocol.
struct RestNotifications: RestNotificationScheduling {

    /// One id, replaced each time. `add` with an existing identifier replaces
    /// the pending request, so starting a new rest cannot leave the previous
    /// one armed.
    static let identifier = "rest.timer.finished"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func schedule(at date: Date, exerciseName: String?) async {
        guard await isAuthorized() else { return }

        let interval = date.timeIntervalSinceNow
        // `UNTimeIntervalNotificationTrigger` traps on a non-positive interval.
        // The rule already refuses to produce a past date, so this is the
        // belt-and-braces for the gap between deciding and arriving here.
        guard interval > 0 else {
            await cancel()
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = exerciseName.map { "Next set: \($0)" } ?? "Time for your next set."
        content.sound = .default
        // The phone is in a pocket and the user is waiting on this, so it
        // should survive the app being backgrounded — which a time-interval
        // trigger does. It deliberately does NOT ask for `.timeSensitive`:
        // that needs a capability this app has not been granted, and
        // requesting an entitlement the profile lacks fails the build rather
        // than degrading.
        content.interruptionLevel = .active

        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        try? await center.add(request)
    }

    func cancel() async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        // Also clears an alert already sitting in Notification Centre. Ending a
        // rest early and then finding a stale "Rest complete" banner is the
        // same lie as one firing at the wrong time.
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }

    /// Authorized, asking once if nobody has been asked yet.
    ///
    /// A denial is remembered by the system and asking again does nothing, so
    /// this quietly returns false forever after — the app keeps working, the
    /// on-screen countdown is unaffected, and nothing nags.
    private func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}

// MARK: - The one that does nothing

/// Used when notifications must not be scheduled at all: an XCTest run, or UI
/// preview mode.
///
/// A test host that scheduled real notifications would ask for authorization
/// and block on a prompt nobody can tap — the same class of problem as the
/// suite syncing to the live project (`AutomatedLaunch`), and worth blocking
/// for the same reason.
struct NoRestNotifications: RestNotificationScheduling {
    func schedule(at date: Date, exerciseName: String?) async {}
    func cancel() async {}
}

// MARK: - Foreground presentation

/// Shows the alert even when the app is open.
///
/// Without a delegate, iOS suppresses a local notification whose app is
/// frontmost — which is most of a workout. The whole point is that the user is
/// NOT looking at the screen: the phone is face down on a bench while they
/// stretch. Suppressing the one alert they are waiting for, precisely when the
/// app is open, would make the feature useless in its main case.
final class RestNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // `.list` as well as `.banner`: the banner slides away on its own, and
        // if it goes while the user is mid-set there is no trace that rest
        // ended. `.list` leaves it in Notification Centre to be found.
        [.banner, .list, .sound]
    }
}
