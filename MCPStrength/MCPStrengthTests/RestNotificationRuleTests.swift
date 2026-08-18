//
//  RestNotificationRuleTests.swift
//  MCPStrengthTests
//
//  The rule that decides whether a rest alert should be pending.
//
//  Every case here is a way to get a notification firing at the WRONG moment,
//  which is the only real failure this feature has. A missing alert is a
//  disappointment; one that buzzes in the middle of your next set is worse than
//  not having built it, because it trains you to ignore the thing you asked
//  for.
//
//  Fixed instants throughout — `RestTimer` takes `now` as an input precisely so
//  this can be tested without sleeping, and the rule inherits that.
//

import Testing
import Foundation
@testable import MCPStrength

struct RestNotificationRuleTests {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Scheduling

    @Test func aRunningRestSchedulesAtItsEndInstant() {
        var timer = RestTimer()
        timer.start(duration: 90, at: t0)

        #expect(RestNotificationRule.plan(for: timer, at: t0)
                == .schedule(at: t0.addingTimeInterval(90)))
    }

    // Mid-rest, the answer must not drift. The fire instant is absolute, so
    // asking again later gives the same date rather than "90 seconds from now"
    // a second time — which would push the alert back on every re-evaluation
    // and, since the view re-evaluates on every timer change, could postpone it
    // forever.
    @Test func askingAgainLaterDoesNotMoveTheFireInstant() {
        var timer = RestTimer()
        timer.start(duration: 90, at: t0)
        let expected = RestNotificationPlan.schedule(at: t0.addingTimeInterval(90))

        #expect(RestNotificationRule.plan(for: timer, at: t0.addingTimeInterval(30)) == expected)
        #expect(RestNotificationRule.plan(for: timer, at: t0.addingTimeInterval(89)) == expected)
    }

    @Test func adjustingTheRestMovesTheAlertWithIt() {
        var timer = RestTimer()
        timer.start(duration: 90, at: t0)
        timer.adjust(by: 15, at: t0)

        #expect(RestNotificationRule.plan(for: timer, at: t0)
                == .schedule(at: t0.addingTimeInterval(105)))
    }

    @Test func resettingRearmsTheFullDuration() {
        var timer = RestTimer()
        timer.start(duration: 90, at: t0)
        let later = t0.addingTimeInterval(60)
        timer.reset(at: later)

        #expect(RestNotificationRule.plan(for: timer, at: later)
                == .schedule(at: later.addingTimeInterval(90)))
    }

    // MARK: - Cancelling

    @Test func anIdleTimerHasNothingPending() {
        #expect(RestNotificationRule.plan(for: RestTimer(), at: t0) == .cancel)
    }

    // Pausing is the case that would fire WHILE the user is deliberately still
    // resting.
    @Test func pausingCancels() {
        var timer = RestTimer()
        timer.start(duration: 90, at: t0)
        timer.pause(at: t0.addingTimeInterval(30))

        #expect(RestNotificationRule.plan(for: timer, at: t0.addingTimeInterval(30)) == .cancel)
    }

    @Test func resumingSchedulesAgainFromTheRemainingTime() {
        var timer = RestTimer()
        timer.start(duration: 90, at: t0)
        timer.pause(at: t0.addingTimeInterval(30))          // 60 left
        let resumeAt = t0.addingTimeInterval(300)           // paused a long while
        timer.resume(at: resumeAt)

        #expect(RestNotificationRule.plan(for: timer, at: resumeAt)
                == .schedule(at: resumeAt.addingTimeInterval(60)),
                "resuming must re-arm from what was LEFT, not from the original end")
    }

    // Skipping is the user saying they are done. An alert after that tells them
    // to do the thing they just did.
    @Test func skippingCancels() {
        var timer = RestTimer()
        timer.start(duration: 90, at: t0)
        timer.skip()

        #expect(RestNotificationRule.plan(for: timer, at: t0) == .cancel)
    }

    // A rest that ran out while the app was closed must not schedule anything
    // "now". A late alert about a finished rest is indistinguishable from an
    // alert about the rest you are actually in.
    @Test func anAlreadyElapsedRestDoesNotFireLate() {
        var timer = RestTimer()
        timer.start(duration: 90, at: t0)

        #expect(RestNotificationRule.plan(for: timer, at: t0.addingTimeInterval(90)) == .cancel)
        #expect(RestNotificationRule.plan(for: timer, at: t0.addingTimeInterval(9_000)) == .cancel)
    }

    // "No rest timer" is a real preference (RestTimerSheet offers 0), not an
    // absent one. Honouring it by buzzing immediately is the opposite of what
    // was asked for.
    @Test func aZeroLengthRestNeverSchedules() {
        var timer = RestTimer()
        timer.start(duration: 0, at: t0)

        #expect(RestNotificationRule.plan(for: timer, at: t0) == .cancel)
    }

    // Adjusting a rest down to nothing is the same as skipping it.
    @Test func adjustingBelowZeroCancels() {
        var timer = RestTimer()
        timer.start(duration: 30, at: t0)
        timer.adjust(by: -60, at: t0)

        #expect(RestNotificationRule.plan(for: timer, at: t0) == .cancel)
    }

    // MARK: - The property that makes it a rule

    // Whatever sequence of operations happened, the answer depends only on the
    // state that came out. That is the whole reason this is derived from the
    // value rather than called at each mutation site: a seventh way to change a
    // timer is covered for free.
    @Test func twoTimersInTheSameStateGetTheSamePlan() {
        var direct = RestTimer()
        direct.start(duration: 60, at: t0)

        var roundabout = RestTimer()
        roundabout.start(duration: 90, at: t0)
        roundabout.pause(at: t0)
        roundabout.resume(at: t0)
        roundabout.adjust(by: -30, at: t0)

        #expect(RestNotificationRule.plan(for: direct, at: t0)
                == RestNotificationRule.plan(for: roundabout, at: t0))
    }
}
