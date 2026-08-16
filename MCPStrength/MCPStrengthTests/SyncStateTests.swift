//
//  SyncStateTests.swift
//  MCPStrengthTests
//
//  Covers what the app TELLS the user about their backup.
//
//  Wording is not usually worth testing. It is here, because this is the one
//  screen whose job is to be believed: `02-architecture.md` § Observability
//  exists because a failed push is indistinguishable from a successful one, and
//  the entire remedy is a handful of sentences being accurate. A reassuring
//  string in the wrong branch is the bug, not a typo.
//

import Testing
import Foundation
@testable import MCPStrength

struct SyncStateTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - The fabricated zero

    @Test func neverSyncedIsNotDescribedAsBackedUp() {
        // The highest-stakes fabricated zero in the app: a green tick over an
        // empty backup. Anyone reading "backed up" here stops worrying about
        // exactly the thing they should be worried about.
        let state = SyncState.never
        #expect(state.title == "Not backed up yet")
        #expect(!state.title.lowercased().contains("up to date"))
        #expect(state.detail(now: now).contains("only on this phone"))
    }

    @Test func neverSyncedReportsNoCountRatherThanZero() {
        // `0` would render as "0 changes waiting", which reads as a fact about
        // the data instead of an absence of information.
        #expect(SyncState.never.pendingCount == nil)
        #expect(SyncState.syncing.pendingCount == nil)
        #expect(SyncState.upToDate(at: now).pendingCount == nil)
    }

    // MARK: - Pending is not a failure

    @Test func pendingReadsCalmly() {
        // Training in a basement with no signal is the case this app was
        // designed for, not an error condition.
        let state = SyncState.pending(count: 3)
        #expect(state.demandsAttention == false)
        #expect(state.title == "3 changes waiting")
        let detail = state.detail(now: now).lowercased()
        #expect(detail.contains("nothing is lost"))
        #expect(!detail.contains("error"))
        #expect(!detail.contains("failed"))
    }

    @Test func pendingCountIsSingularForOne() {
        #expect(SyncState.pending(count: 1).title == "1 change waiting")
    }

    // MARK: - Failure says what is safe

    @Test func failureAlwaysSaysTheDataIsStillOnThePhone() {
        // The user's first fear on seeing "backup failed" is that the workout
        // is gone. It is not, and saying so is the most useful sentence
        // available.
        let state = SyncState.failed(count: 2, reason: "No connection.")
        #expect(state.detail(now: now).contains("still saved on this phone"))
    }

    @Test func onlyFailureInterrupts() {
        // A permanent status badge on the logging screen is noise almost
        // always, and a signal people learn to ignore fails on the one day it
        // matters.
        #expect(SyncState.failed(count: 1, reason: "x").demandsAttention)
        #expect(!SyncState.never.demandsAttention)
        #expect(!SyncState.syncing.demandsAttention)
        #expect(!SyncState.pending(count: 9).demandsAttention)
        #expect(!SyncState.upToDate(at: now).demandsAttention)
    }

    @Test func failureStillReportsHowMuchIsWaiting() {
        #expect(SyncState.failed(count: 4, reason: "x").pendingCount == 4)
    }

    // MARK: - Relative time

    @Test func recentReadsAsJustNow() {
        #expect(SyncState.relative(now.addingTimeInterval(-5), from: now) == "just now")
    }

    @Test func minutesHoursAndDaysAreSingularAtOne() {
        #expect(SyncState.relative(now.addingTimeInterval(-60), from: now) == "1 minute ago")
        #expect(SyncState.relative(now.addingTimeInterval(-3_600), from: now) == "1 hour ago")
        #expect(SyncState.relative(now.addingTimeInterval(-86_400), from: now) == "1 day ago")
    }

    @Test func plurals() {
        #expect(SyncState.relative(now.addingTimeInterval(-180), from: now) == "3 minutes ago")
        #expect(SyncState.relative(now.addingTimeInterval(-7_200), from: now) == "2 hours ago")
        #expect(SyncState.relative(now.addingTimeInterval(-172_800), from: now) == "2 days ago")
    }

    @Test func aFutureTimestampNeverReadsAsTheFuture() {
        // Device clocks drift, and the server's timestamp can legitimately land
        // slightly ahead of the phone's. "Last backed up in 3 minutes" reads as
        // a broken app and undermines the one screen that has to be believed.
        #expect(SyncState.relative(now.addingTimeInterval(180), from: now) == "just now")
    }

    // MARK: - Every branch says something

    @Test func noStateIsSilentOrLeaksInternals() {
        let states: [SyncState] = [
            .never, .syncing, .upToDate(at: now.addingTimeInterval(-120)),
            .pending(count: 2), .failed(count: 1, reason: "No connection."),
        ]
        for state in states {
            #expect(!state.title.isEmpty, "\(state) has no title")
            let detail = state.detail(now: now)
            #expect(!detail.isEmpty, "\(state) has no detail")
            // Nothing a user reads should contain developer vocabulary.
            for leak in ["nil", "Optional", "Error(", "http", "postgrest"] {
                #expect(!detail.lowercased().contains(leak.lowercased()),
                        "\(state) leaked \(leak)")
            }
        }
    }
}
