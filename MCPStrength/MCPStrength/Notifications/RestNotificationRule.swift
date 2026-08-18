//
//  RestNotificationRule.swift
//  MCPStrength
//
//  What the pending rest notification should be, for a given timer state.
//
//  ## Why this is a rule and not a set of calls
//
//  A rest can change in six ways — start, pause, resume, adjust, reset, skip —
//  and it would be entirely natural to schedule a notification in `start` and
//  cancel it in `skip` and remember to reschedule in `adjust`. That is the
//  shape this project has already been bitten by twice: `markEdited` at every
//  mutation site, and `PushFilter`. The lesson written down both times is that
//  **a rule that cannot be violated beats one you have to remember**, and the
//  failure mode here is the worst kind — a notification that fires during your
//  next set because somebody added a seventh way to change a timer and did not
//  know there was a list.
//
//  So nothing calls "schedule". The caller watches the timer VALUE, hands it to
//  this function whenever it changes, and does what it says. A seventh
//  operation is covered the moment it changes the timer, because every one of
//  them changes the same two facts: is it running, and when does it end.
//
//  Pure, and takes `now` as an input for the same reason `RestTimer` does — so
//  it can be tested at fixed instants instead of by sleeping.
//

import Foundation

/// What should be pending after this state change.
enum RestNotificationPlan: Equatable, Sendable {
    /// Fire at this instant. Always in the future when produced.
    case schedule(at: Date)
    /// Nothing should be pending; remove anything that is.
    case cancel
}

enum RestNotificationRule {

    /// The notification that should exist for `timer`, observed at `now`.
    ///
    /// `.schedule` only for a rest that is RUNNING and still has time left.
    /// Everything else cancels, and the cases are worth spelling out because
    /// they are the ones that would otherwise fire at the wrong moment:
    ///
    ///   * **Paused** — a paused rest has no end instant. Leaving the old one
    ///     pending would fire while the user is still resting on purpose.
    ///   * **Skipped** — the user said they are done resting. Firing after
    ///     that is telling them to do what they already did.
    ///   * **Already elapsed** — a rest whose time ran out while the app was
    ///     closed must not produce a notification "now". It is late, and a late
    ///     alert about a finished rest is indistinguishable from an alert about
    ///     the rest the user is in the middle of.
    ///   * **Idle** — nothing has started.
    ///
    /// A zero-second rest is `.cancel` rather than an immediate fire: "no rest
    /// timer" is a real preference (`RestTimerSheet` offers it), and honouring
    /// it by immediately buzzing would be the opposite of what was asked.
    static func plan(for timer: RestTimer, at now: Date) -> RestNotificationPlan {
        guard timer.status(at: now) == .running else { return .cancel }
        guard let end = timer.endInstant, end > now else { return .cancel }
        return .schedule(at: end)
    }
}
