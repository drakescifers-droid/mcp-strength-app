//
//  SyncState.swift
//  MCPStrength
//
//  What the app says about whether your training has actually left this phone.
//
//  `02-architecture.md` § Observability: *"Local-first makes this invisible by
//  construction. The user logs a workout, SwiftData accepts it, the UI says
//  done — and the push to Postgres fails. Nothing in the experience
//  distinguishes that from success. They find out weeks later on another
//  device, or never."*
//
//  This file exists so that sentence stops being true. It is deliberately
//  written before the transport it describes, because a sync state retrofitted
//  onto a layer built assuming success only ever reports success.
//
//  ## The three rules, all versions of "never display a fabricated zero"
//
//  1. `.never` IS NOT `.upToDate`. A fresh install that has not once reached
//     the server must not show a reassuring state. This is the fabricated-zero
//     mistake with the highest stakes in the app: it is a green tick over an
//     empty backup.
//  2. `.pending` IS NOT A FAILURE. Being in a gym with no signal is the case
//     this app was designed for. It reports a count, calmly.
//  3. `.failed` SAYS WHAT IS SAFE. Every failure message says the workouts are
//     still on the phone, because they are, and because that is the user's
//     first fear.
//

import Foundation

/// Where sync has actually got to. Ordered roughly by how much attention it
/// deserves, and `Equatable` so a view can diff it without prodding the engine.
enum SyncState: Equatable {
    /// Signed in, but no sync has ever completed. The launch state.
    case never
    /// A run is in flight.
    case syncing
    /// Everything local is confirmed on the server, as of this moment.
    case upToDate(at: Date)
    /// Changes are waiting. Usually offline — NOT an error.
    case pending(count: Int)
    /// Retried and still failing.
    case failed(count: Int, reason: String)
}

extension SyncState {

    /// Whether this state should interrupt the user.
    ///
    /// Only `.failed`. A permanent badge on the logging screen would be noise
    /// almost always, and a signal people learn to ignore is worse than no
    /// signal — it fails on precisely the day it matters.
    var demandsAttention: Bool {
        if case .failed = self { return true }
        return false
    }

    /// The headline, for the account card.
    var title: String {
        switch self {
        case .never:            "Not backed up yet"
        case .syncing:          "Backing up…"
        case .upToDate:         "Backed up"
        case .pending(let n):   n == 1 ? "1 change waiting" : "\(n) changes waiting"
        case .failed:           "Backup failed"
        }
    }

    /// The line underneath. Every branch is either actionable or reassuring;
    /// none of them is a diagnosis.
    func detail(now: Date = .now) -> String {
        switch self {
        case .never:
            // Deliberately blunt. The whole point of the account is backup, so
            // "not yet" is the single most important thing to be honest about.
            return "Your workouts are only on this phone."
        case .syncing:
            return "Sending your latest changes."
        case .upToDate(let at):
            return "Last backed up \(Self.relative(at, from: now))."
        case .pending:
            return "They will go up next time you have a connection. Nothing is lost."
        case .failed(_, let reason):
            return "\(reason) Your workouts are still saved on this phone."
        }
    }

    /// What the sign-out confirmation says underneath "Sign out?".
    ///
    /// Signing out never touches the local store, so the old flat wording —
    /// "Your workouts stay on this phone." — was always TRUE. It was still the
    /// wrong thing to say, and for the reason this whole file exists: it is a
    /// reassurance that quietly omits whether anything is still waiting to go
    /// up. "Your workouts are safe here" reads as "and also safe there". That
    /// is rule 1 at the top of this file, one screen further along.
    ///
    /// So the count is stated when there is one, and `.never` gets its own
    /// branch because it is the highest-stakes case in the app: nothing has
    /// ever reached the server, and sign-out is exactly the moment somebody
    /// would want to know that.
    ///
    /// Lives here rather than in ProfileTab so all the user-facing sync copy is
    /// in one file and can be tested — a computed property inside a View
    /// cannot be. It reads the same state the account card above the button
    /// reads, deliberately: a second source of truth that disagreed with the
    /// card would be worse than the omission this replaced.
    var signOutMessage: String {
        let tail = "They will stay on this phone."
        switch self {
        case .never:
            return "None of your workouts have been backed up yet. \(tail)"
        case .pending(let n), .failed(let n, _):
            let changes = n == 1 ? "1 change has" : "\(n) changes have"
            return "\(changes) not been backed up yet. \(tail)"
        case .syncing, .upToDate:
            return "Your workouts stay on this phone."
        }
    }

    /// How many local changes are waiting, if that is a meaningful question.
    ///
    /// `nil` rather than `0` for the states where the count is unknown. A
    /// literal zero here would render as "0 changes waiting", which reads as a
    /// fact about the data rather than an absence of information.
    var pendingCount: Int? {
        switch self {
        case .pending(let n), .failed(let n, _): n
        case .never, .syncing, .upToDate: nil
        }
    }

    // MARK: - Relative time

    /// Coarse on purpose. "Last backed up 3 minutes ago" is what the user
    /// wants; a timestamp to the second invites them to do arithmetic.
    static func relative(_ date: Date, from now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        switch seconds {
        case ..<0:      return "just now"   // clock skew; never say "in 3 minutes"
        case ..<60:     return "just now"
        case ..<3_600:
            let m = Int(seconds / 60)
            return m == 1 ? "1 minute ago" : "\(m) minutes ago"
        case ..<86_400:
            let h = Int(seconds / 3_600)
            return h == 1 ? "1 hour ago" : "\(h) hours ago"
        default:
            let d = Int(seconds / 86_400)
            return d == 1 ? "1 day ago" : "\(d) days ago"
        }
    }
}
