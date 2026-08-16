//
//  SyncStatus.swift
//  MCPStrength
//
//  Holds the sync state the UI reads, and the small amount of bookkeeping that
//  has to outlive a launch: the pull cursor, and when a run last succeeded.
//
//  ## Everything here is keyed by user id
//
//  A cursor is a claim about what a PARTICULAR account has already seen. Share
//  one between accounts on the same device and the second person to sign in
//  starts from the first person's position — skipping every row written before
//  it, permanently, with no error and no way to notice. Signing out and back in
//  as yourself is the common case; two accounts on one phone is rare but the
//  failure is silent and unrecoverable, so the key is per-user from the start.
//
//  docs/06-sync.md § "Rows that predate sign-in" makes the same argument about
//  claiming un-owned rows.
//

import Foundation
import Observation

@MainActor
@Observable
final class SyncStatus {

    /// What the UI shows. Starts at `.never` and is only ever moved by a run.
    private(set) var state: SyncState = .never

    private let defaults: UserDefaults
    private var userID: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Session

    /// Point the status at an account. Called when the session changes.
    ///
    /// Reloads the state from what that user has stored, so signing back in
    /// does not report `.never` for an account that has synced before.
    func adopt(userID: UUID?) {
        self.userID = userID
        guard userID != nil else {
            state = .never
            return
        }
        state = lastSyncedAt.map { SyncState.upToDate(at: $0) } ?? .never
    }

    // MARK: - Persisted bookkeeping

    /// The pull cursor, in SERVER time. `nil` means this account has never
    /// pulled on this device and must fetch everything.
    var cursor: Date? {
        get { date(for: "cursor") }
        set { setDate(newValue, for: "cursor") }
    }

    /// When a run last completed successfully. `nil` means never.
    var lastSyncedAt: Date? {
        get { date(for: "lastSyncedAt") }
        set { setDate(newValue, for: "lastSyncedAt") }
    }

    private func key(_ name: String) -> String? {
        guard let userID else { return nil }
        return "sync.\(userID.uuidString).\(name)"
    }

    private func date(for name: String) -> Date? {
        guard let key = key(name) else { return nil }
        // `object(forKey:)` rather than `double(forKey:)`: the latter returns 0
        // for a missing key, which is 1970 — a cursor that would silently claim
        // to have already seen everything.
        guard let seconds = defaults.object(forKey: key) as? Double else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private func setDate(_ date: Date?, for name: String) {
        guard let key = key(name) else { return }
        if let date {
            defaults.set(date.timeIntervalSince1970, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Transitions
    //
    // The engine calls these; nothing else sets `state`. One way in means the
    // UI cannot drift out of agreement with what actually happened.

    func beginRun() {
        state = .syncing
    }

    /// A run finished with everything sent.
    func finishRun(at date: Date = .now) {
        lastSyncedAt = date
        state = .upToDate(at: date)
    }

    /// A run finished, but changes are still waiting — usually offline.
    /// Not a failure; see SyncState.
    func finishRun(pending: Int) {
        state = pending > 0 ? .pending(count: pending) : .upToDate(at: .now)
    }

    /// A run failed. `reason` is a sentence for a human, never an error dump.
    func failRun(reason: String, pending: Int) {
        state = .failed(count: pending, reason: reason)
    }

    /// Signed out. Clears the in-memory state but NOT the stored cursor — the
    /// same account signing back in should resume, not re-pull its whole
    /// history.
    func clearSession() {
        userID = nil
        state = .never
    }
}
