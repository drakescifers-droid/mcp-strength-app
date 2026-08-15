//
//  RestTimer.swift
//  MCPStrength
//
//
//  The rest-timer model.
//
//  CRITICAL INVARIANT: time is an INPUT. This type never reads `Date()` itself.
//  Every operation that cares about "now" takes `at now: Date`; the only query,
//  `remaining(at:)`, is a pure function of the instant passed in. The view layer
//  supplies the clock (a Timer publisher / TimelineView); tests supply fixed
//  dates. A timer that reads the wall clock internally cannot be tested without
//  sleeping, so we do not.
//

import Foundation

/// A rest countdown. A value type: hold it in `@State`, mutate via the
/// operations, and read the live value through `remaining(at:)`.
///
/// States (stored `state`): `.idle` before a rest has begun, `.running` while the
/// countdown is active, `.paused` while frozen, `.skipped` once the user has
/// dismissed it. A countdown that has elapsed past zero is reported as finished
/// through `isFinished(at:)` (it does not require a mutation to observe).
struct RestTimer: Equatable, Sendable {

    /// The user-facing phases. `.finished` is reachable observationally — a
    /// running timer whose `remaining(at:)` has hit zero is finished — and is
    /// also returned by `status(at:)` without needing a stored transition.
    enum State: Equatable, Sendable {
        case idle
        case running
        case paused
        case finished
        case skipped
    }

    /// The configured duration. Remembered so `reset(at:)` can restart the full
    /// countdown without callers having to pass it again.
    private(set) var duration: TimeInterval = 0

    /// The absolute instant at which `remaining` reaches zero while running.
    /// `nil` unless `state == .running`.
    private(set) var endInstant: Date?

    /// The remaining seconds frozen at the moment of pause. `nil` unless
    /// `state == .paused`.
    private(set) var pausedRemaining: TimeInterval?

    /// The stored phase. See `status(at:)` for the observed phase, which folds
    /// in the natural "ran out" case.
    private(set) var state: State = .idle

    // MARK: - Queries

    /// Remaining seconds at `now`, clamped at zero. Pure; never mutates.
    func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .running:
            guard let end = endInstant else { return 0 }
            return max(0, end.timeIntervalSince(now))
        case .paused:
            return max(0, pausedRemaining ?? 0)
        case .idle, .finished, .skipped:
            return 0
        }
    }

    /// The observed phase. A running timer that has elapsed reports `.finished`
    /// here even though its stored `state` stays `.running` — so the UI can
    /// treat "ran out" uniformly without a mutating tick call.
    func status(at now: Date) -> State {
        switch state {
        case .running:
            return remaining(at: now) <= 0 ? .finished : .running
        default:
            return state
        }
    }

    /// True once the rest is over for any reason: elapsed naturally, skipped,
    /// or never started. The UI uses this to decide whether to keep showing the
    /// progress bar.
    func isFinished(at now: Date) -> Bool {
        status(at: now) == .finished || state == .skipped
    }

    /// Fraction (0...1) of the rest remaining — for the progress bar fill.
    func progress(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, remaining(at: now) / duration))
    }

    // MARK: - Operations

    /// Begin a fresh countdown of `duration` seconds from `now`.
    mutating func start(duration: TimeInterval, at now: Date) {
        self.duration = max(0, duration)
        self.endInstant = now.addingTimeInterval(self.duration)
        self.pausedRemaining = nil
        self.state = .running
    }

    /// Freeze the countdown. No-op unless currently running. Pausing captures
    /// `remaining(at: now)` so two later queries return the same value.
    mutating func pause(at now: Date) {
        guard state == .running else { return }
        self.pausedRemaining = remaining(at: now)
        self.endInstant = nil
        self.state = .paused
    }

    /// Resume from the frozen value. No-op unless currently paused. Resuming
    /// arms a new `endInstant` from `now`, so elapsed-while-paused time is not
    /// lost — the countdown continues from where it stopped.
    mutating func resume(at now: Date) {
        guard state == .paused, let remaining = pausedRemaining else { return }
        self.endInstant = now.addingTimeInterval(remaining)
        self.pausedRemaining = nil
        self.state = .running
    }

    /// Add or remove seconds from the remaining time (e.g. ±15). Works while
    /// running or paused. The remaining value is clamped at zero so an
    /// over-subtraction never reports a negative countdown.
    mutating func adjust(by delta: TimeInterval, at now: Date) {
        let current = remaining(at: now)
        let next = max(0, current + delta)
        switch state {
        case .running:
            self.endInstant = now.addingTimeInterval(next)
        case .paused:
            self.pausedRemaining = next
        default:
            break
        }
    }

    /// Restart the full original duration from `now`.
    mutating func reset(at now: Date) {
        guard state != .idle else { return }
        self.endInstant = now.addingTimeInterval(duration)
        self.pausedRemaining = nil
        self.state = .running
    }

    /// End the rest immediately. `remaining(at:)` reports zero and
    /// `isFinished(at:)` reports true for any subsequent instant.
    mutating func skip() {
        self.endInstant = nil
        self.pausedRemaining = nil
        self.state = .skipped
    }
}
