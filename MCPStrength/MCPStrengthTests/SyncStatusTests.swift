//
//  SyncStatusTests.swift
//  MCPStrengthTests
//
//  Covers the per-user bookkeeping that outlives a launch.
//
//  The cursor is the dangerous thing in this file. It is a claim about what an
//  account has already seen, and every way of getting it slightly wrong loses
//  rows silently rather than loudly.
//

import Testing
import Foundation
@testable import MCPStrength

@MainActor
struct SyncStatusTests {

    /// An isolated UserDefaults per test, so these cannot see each other's keys
    /// or the simulator's real ones.
    private func makeDefaults() -> UserDefaults {
        let suite = "SyncStatusTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private let userA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let userB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    // MARK: - The missing cursor

    @Test func aFreshAccountHasNoCursor() {
        // MUST be nil, not 1970. A zero-valued cursor would claim the account
        // has already seen everything up to that point, and a first sync would
        // pull nothing at all — an empty device that never corrects itself.
        let status = SyncStatus(defaults: makeDefaults())
        status.adopt(userID: userA)
        #expect(status.cursor == nil)
        #expect(status.lastSyncedAt == nil)
    }

    @Test func aFreshAccountReportsNeverSynced() {
        let status = SyncStatus(defaults: makeDefaults())
        status.adopt(userID: userA)
        #expect(status.state == .never)
    }

    // MARK: - Per-user isolation

    @Test func twoAccountsOnOneDeviceDoNotShareACursor() {
        // The silent-loss case this keying exists for: user B resuming from
        // user A's position would skip every row written before it, forever.
        let defaults = makeDefaults()
        let status = SyncStatus(defaults: defaults)

        status.adopt(userID: userA)
        let aCursor = Date(timeIntervalSince1970: 1_800_000_000)
        status.cursor = aCursor
        #expect(status.cursor == aCursor)

        status.adopt(userID: userB)
        #expect(status.cursor == nil, "user B inherited user A's cursor")
    }

    @Test func signingBackInResumesRatherThanStartingOver() {
        let defaults = makeDefaults()
        let status = SyncStatus(defaults: defaults)
        status.adopt(userID: userA)
        let cursor = Date(timeIntervalSince1970: 1_800_000_000)
        status.cursor = cursor
        status.finishRun(at: cursor)

        status.clearSession()
        #expect(status.state == .never)

        status.adopt(userID: userA)
        #expect(status.cursor == cursor, "a re-sign-in threw away the cursor")
        #expect(status.state == .upToDate(at: cursor))
    }

    @Test func signingOutKeepsTheStoredCursor() {
        // Clearing it would make the same account re-pull its entire history on
        // every sign-in — slow, and pointless.
        let defaults = makeDefaults()
        let status = SyncStatus(defaults: defaults)
        status.adopt(userID: userA)
        status.cursor = Date(timeIntervalSince1970: 1_800_000_000)

        status.clearSession()

        let reopened = SyncStatus(defaults: defaults)
        reopened.adopt(userID: userA)
        #expect(reopened.cursor != nil)
    }

    @Test func theCursorSurvivesRelaunch() {
        let defaults = makeDefaults()
        let cursor = Date(timeIntervalSince1970: 1_800_000_000)

        let first = SyncStatus(defaults: defaults)
        first.adopt(userID: userA)
        first.cursor = cursor

        let second = SyncStatus(defaults: defaults)
        second.adopt(userID: userA)
        #expect(second.cursor == cursor)
    }

    // MARK: - No session

    @Test func nothingIsStoredWithoutAUser() {
        // A write with no user id must not land under some shared key that the
        // next account to sign in would read as its own.
        let defaults = makeDefaults()
        let status = SyncStatus(defaults: defaults)
        status.cursor = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(status.cursor == nil)

        status.adopt(userID: userA)
        #expect(status.cursor == nil, "a session-less write leaked into an account")
    }

    // MARK: - Transitions

    @Test func aRunInFlightReportsSyncing() {
        let status = SyncStatus(defaults: makeDefaults())
        status.adopt(userID: userA)
        status.beginRun()
        #expect(status.state == .syncing)
    }

    @Test func finishingRecordsWhenItHappened() {
        let status = SyncStatus(defaults: makeDefaults())
        status.adopt(userID: userA)
        let at = Date(timeIntervalSince1970: 1_800_000_000)

        status.finishRun(at: at)

        #expect(status.state == .upToDate(at: at))
        #expect(status.lastSyncedAt == at, "the timestamp was not persisted")
    }

    @Test func finishingWithWorkStillWaitingIsNotUpToDate() {
        let status = SyncStatus(defaults: makeDefaults())
        status.adopt(userID: userA)
        status.finishRun(pending: 3)
        #expect(status.state == .pending(count: 3))
    }

    @Test func finishingWithNothingWaitingIsUpToDate() {
        let status = SyncStatus(defaults: makeDefaults())
        status.adopt(userID: userA)
        status.finishRun(pending: 0)
        if case .upToDate = status.state {} else {
            Issue.record("expected .upToDate, got \(status.state)")
        }
    }

    @Test func failingDoesNotClaimAnythingWasBackedUp() {
        // The failure has to be sticky. A failed run that left `.upToDate`
        // showing would be the exact lie this whole design exists to prevent.
        let status = SyncStatus(defaults: makeDefaults())
        status.adopt(userID: userA)
        status.failRun(reason: "No connection.", pending: 2)

        #expect(status.state == .failed(count: 2, reason: "No connection."))
        #expect(status.lastSyncedAt == nil, "a failed run recorded a backup time")
    }

    @Test func aFailedRunAfterASuccessKeepsTheOldSuccessTime() {
        // "Last backed up 2 hours ago" stays true through a later failure —
        // that is exactly the information the user needs to judge how worried
        // to be.
        let status = SyncStatus(defaults: makeDefaults())
        status.adopt(userID: userA)
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        status.finishRun(at: at)

        status.failRun(reason: "No connection.", pending: 1)

        #expect(status.lastSyncedAt == at)
    }
}
