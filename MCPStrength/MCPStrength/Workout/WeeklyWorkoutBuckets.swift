//
//  WeeklyWorkoutBuckets.swift
//  MCPStrength
//
//  Pure, side-effect-free weekly bucketing of completed workouts. Lifted out of
//  the view layer so the Profile tab's "Workouts Per Week" chart reads from a
//  testable function — never arithmetic inside a chart builder.
//
//  Semantics:
//  - Only COMPLETED workouts (completedAt != nil) count. An in-progress workout
//    was not performed and does not belong on a training-frequency chart.
//  - The result covers EXACTLY `weeks` consecutive weeks, ending with the week
//    containing `now`. A week with no workouts is present with a count of zero
//    — it is never omitted, because a missing bar and a zero bar mean
//    different things on a history chart.
//  - Two workouts in the same week produce a single bucket with a count of two,
//    not two entries.
//

import Foundation

/// One week's bucket: the calendar start of the week and how many completed
/// workouts fell in it. `Equatable`/`Sendable`/`Identifiable` so it is trivial
/// to assert against in tests and to feed directly to a Swift Charts `Chart`.
struct WeeklyBucket: Sendable, Equatable, Identifiable {
    let weekStart: Date
    let count: Int

    // Identifiable by weekStart — each week is unique in a bucket array.
    var id: Date { weekStart }
}

enum WeeklyWorkoutBuckets {

    /// Bucket `workouts` into `weeks` consecutive weeks ending with the week
    /// containing `now`. Oldest week first; the current week is last.
    ///
    /// - Parameters:
    ///   - workouts: Every workout under consideration (completed and not).
    ///     Only completed ones are counted.
    ///   - weeks: The number of weeks to cover. Must be positive; zero or
    ///     negative returns an empty array.
    ///   - now: The reference instant. The bucket window ends with the week
    ///     containing this date.
    ///   - calendar: The calendar used to resolve week boundaries. Defaults to
    ///     `.current`; tests pass a fixed calendar for determinism.
    /// - Returns: Exactly `weeks` buckets oldest-first, each present even when
    ///   its count is zero. Workouts outside the window are ignored.
    static func buckets(
        for workouts: [Workout],
        weeks: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> [WeeklyBucket] {
        guard weeks > 0 else { return [] }
        guard let currentWeekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return []
        }
        let currentWeekStart = currentWeekInterval.start

        // Build the N week-starts, oldest first. Subtraction goes through the
        // calendar (by: .day) rather than raw seconds so DST transitions do not
        // drift the boundary off the week start.
        var weekStarts: [Date] = []
        for i in stride(from: weeks - 1, through: 0, by: -1) {
            if let start = calendar.date(byAdding: .day, value: -7 * i, to: currentWeekStart) {
                weekStarts.append(start)
            }
        }
        guard weekStarts.count == weeks else { return [] }

        var counts = Array(repeating: 0, count: weeks)
        var indexByStart: [Date: Int] = [:]
        for (i, start) in weekStarts.enumerated() {
            indexByStart[start] = i
        }

        for workout in workouts {
            guard workout.completedAt != nil else { continue }
            let date = workout.completedAt ?? workout.startedAt
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { continue }
            if let i = indexByStart[interval.start] {
                counts[i] += 1
            }
        }

        return zip(weekStarts, counts).map { WeeklyBucket(weekStart: $0, count: $1) }
    }
}
