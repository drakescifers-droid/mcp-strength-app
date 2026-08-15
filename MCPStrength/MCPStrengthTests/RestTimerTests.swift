//
//  RestTimerTests.swift
//  MCPStrengthTests
//
//  Asserts the rest-timer model against FIXED dates. No sleeping, no wall
//  clock — the model never reads `Date()`, so every value is exact.
//

import Testing
import Foundation
@testable import MCPStrength

struct RestTimerTests {

    // A fixed epoch to anchor all the "now" instants. The model never reads
    // the clock, so the absolute value is irrelevant; only the deltas matter.
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // (a) remaining(at:) counts down correctly for a given start and duration.
    @Test func remainingCountsDownCorrectly() {
        var timer = RestTimer()
        timer.start(duration: 60, at: t0)

        #expect(timer.remaining(at: t0) == 60)
        #expect(timer.remaining(at: t0.addingTimeInterval(10)) == 50)
        #expect(timer.remaining(at: t0.addingTimeInterval(30)) == 30)
        #expect(timer.remaining(at: t0.addingTimeInterval(59)) == 1)
    }

    // (b) pausing freezes remaining: it is the same at two different later
    // instants (rather than continuing to deplete).
    @Test func pausingFreezesRemaining() {
        var timer = RestTimer()
        timer.start(duration: 90, at: t0)

        let pauseAt = t0.addingTimeInterval(20)
        timer.pause(at: pauseAt)
        let frozen = timer.remaining(at: pauseAt)

        // Two strictly later instants must report the same frozen value.
        let later1 = t0.addingTimeInterval(100)
        let later2 = t0.addingTimeInterval(3_600)
        #expect(timer.remaining(at: later1) == frozen)
        #expect(timer.remaining(at: later2) == frozen)
        // And the frozen value is what was left at pause time.
        #expect(frozen == 70)
    }

    // (c) resuming continues from where it paused, not from the original
    // start. After resuming, remaining depletes relative to the resume
    // instant, not t0.
    @Test func resumingContinuesFromPausePoint() {
        var timer = RestTimer()
        timer.start(duration: 90, at: t0)

        let pauseAt = t0.addingTimeInterval(30)
        timer.pause(at: pauseAt) // frozen at 60

        let resumeAt = t0.addingTimeInterval(120) // 90s after it would have ended
        timer.resume(at: resumeAt)

        // Just after resume, ~60s remain.
        #expect(timer.remaining(at: resumeAt) == 60)
        // 15s later, ~45s remain.
        #expect(timer.remaining(at: resumeAt.addingTimeInterval(15)) == 45)
        // It would NOT be 45 if resume had re-armed from the original start.
    }

    // (d) adjust(by: +15) and (by: -15) change remaining time, and remaining
    // never goes negative.
    @Test func adjustChangesRemainingAndNeverGoesNegative() {
        var timer = RestTimer()
        timer.start(duration: 60, at: t0)

        timer.adjust(by: 15, at: t0)
        #expect(timer.remaining(at: t0) == 75)

        timer.adjust(by: -15, at: t0)
        #expect(timer.remaining(at: t0) == 60)

        // Over-subtract: clamps at zero, never negative.
        timer.adjust(by: -10_000, at: t0)
        #expect(timer.remaining(at: t0) == 0)
        #expect(timer.remaining(at: t0.addingTimeInterval(5)) == 0)
    }

    @Test func adjustWorksWhilePaused() {
        var timer = RestTimer()
        timer.start(duration: 60, at: t0)
        timer.pause(at: t0.addingTimeInterval(10)) // frozen at 50

        timer.adjust(by: 15, at: t0.addingTimeInterval(999))
        #expect(timer.remaining(at: t0.addingTimeInterval(999)) == 65)

        timer.adjust(by: -100, at: t0.addingTimeInterval(1000))
        #expect(timer.remaining(at: t0.addingTimeInterval(1000)) == 0)
    }

    // (e) skip immediately reports finished.
    @Test func skipImmediatelyReportsFinished() {
        var timer = RestTimer()
        timer.start(duration: 120, at: t0)

        timer.skip()

        #expect(timer.remaining(at: t0) == 0)
        #expect(timer.remaining(at: t0.addingTimeInterval(999)) == 0)
        #expect(timer.isFinished(at: t0) == true)
        #expect(timer.state == .skipped)
    }

    // (f) a timer that has run past its duration reports zero remaining, not a
    // negative number.
    @Test func runningPastDurationReportsZeroNotNegative() {
        var timer = RestTimer()
        timer.start(duration: 60, at: t0)

        let past = t0.addingTimeInterval(120)
        #expect(timer.remaining(at: past) == 0)
        #expect(timer.remaining(at: past) >= 0)
        #expect(timer.isFinished(at: past) == true)
        #expect(timer.status(at: past) == .finished)
        #expect(timer.progress(at: past) == 0)
    }

    // The progress bar fills fully at the start and depletes to zero at the
    // end, clamped to [0, 1].
    @Test func progressFractionIsBoundedAndDepletes() {
        var timer = RestTimer()
        timer.start(duration: 100, at: t0)

        #expect(timer.progress(at: t0) == 1.0)
        #expect(timer.progress(at: t0.addingTimeInterval(50)) == 0.5)
        #expect(timer.progress(at: t0.addingTimeInterval(100)) == 0.0)
        #expect(timer.progress(at: t0.addingTimeInterval(200)) == 0.0)
    }

    // reset(at:) restarts the full original duration from the reset instant,
    // regardless of how much had elapsed or whether it was paused.
    @Test func resetRestartsFullDuration() {
        var timer = RestTimer()
        timer.start(duration: 90, at: t0)

        timer.pause(at: t0.addingTimeInterval(20)) // frozen at 70
        let resetAt = t0.addingTimeInterval(1000)
        timer.reset(at: resetAt)

        #expect(timer.remaining(at: resetAt) == 90)
        #expect(timer.remaining(at: resetAt.addingTimeInterval(30)) == 60)
        #expect(timer.state == .running)
    }

    // pause/resume are no-ops outside their valid states (do not corrupt state).
    @Test func pauseAndResumeAreNoOpsInWrongState() {
        var timer = RestTimer()
        // Pausing before start does nothing.
        timer.pause(at: t0)
        #expect(timer.state == .idle)

        timer.start(duration: 60, at: t0)
        // Resuming while running does nothing harmful.
        timer.resume(at: t0.addingTimeInterval(5))
        #expect(timer.state == .running)
        #expect(timer.remaining(at: t0.addingTimeInterval(5)) == 55)

        // Double-pause: second pause is a no-op (already paused).
        timer.pause(at: t0.addingTimeInterval(10))
        let frozen = timer.remaining(at: t0.addingTimeInterval(10))
        timer.pause(at: t0.addingTimeInterval(20))
        #expect(timer.remaining(at: t0.addingTimeInterval(20)) == frozen)
    }
}
