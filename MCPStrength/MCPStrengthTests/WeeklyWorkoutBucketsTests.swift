//
//  WeeklyWorkoutBucketsTests.swift
//  MCPStrengthTests
//
//  Covers the pure weekly-bucketing function used by the Profile tab's
//  "Workouts Per Week" chart. Fixed dates and a fixed calendar — never Date()
//  in an assertion.
//

import Testing
import SwiftData
import Foundation
@testable import MCPStrength

struct WeeklyWorkoutBucketsTests {

    // A fixed Gregorian-UTC calendar with Monday as the first weekday, so week
    // boundaries are deterministic regardless of the machine running the tests.
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        return cal
    }

    // The reference instant. The exact wall-clock date is irrelevant — every
    // other date in these tests is derived from `now` via the fixed calendar,
    // so the assertions hold regardless of what `now` resolves to.
    private let now = Date(timeIntervalSince1970: 1_785_873_600)

    // The start of the current week, per the fixed calendar. Derived, not
    // assumed — so any date built from this is guaranteed to land in the
    // current week.
    private var currentWeekStart: Date {
        calendar.dateInterval(of: .weekOfYear, for: now)!.start
    }

    // A day in the middle of the current week (Wednesday for a Monday-start week).
    private var midWeek: Date {
        calendar.date(byAdding: .day, value: 2, to: currentWeekStart)!
    }

    // A later day in the same current week (Friday).
    private var lateWeek: Date {
        calendar.date(byAdding: .day, value: 4, to: currentWeekStart)!
    }

    private func makeContainer() throws -> ModelContext {
        let schema = Schema([
            Exercise.self,
            TemplateFolder.self,
            Template.self,
            TemplateExercise.self,
            TemplateSet.self,
            ProgramDay.self,
            Workout.self,
            WorkoutExercise.self,
            WorkoutSet.self,
            MeasurementType.self,
            MeasurementEntry.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    // MARK: - Correct-week bucketing

    // (a) A completed workout in the current week lands in the LAST bucket.
    @Test func workoutBucketsIntoCorrectWeek() throws {
        let context = try makeContainer()

        // Wednesday of the current week.
        let completedAt = midWeek
        let workout = Workout(name: "Leg Day", startedAt: completedAt, completedAt: completedAt)
        context.insert(workout)

        let all = try context.fetch(FetchDescriptor<Workout>())
        let buckets = WeeklyWorkoutBuckets.buckets(for: all, weeks: 8, now: now, calendar: calendar)

        #expect(buckets.count == 8)
        // Only the current week (last bucket) has a count of 1.
        #expect(buckets.last?.count == 1)
        #expect(buckets.dropLast().allSatisfy { $0.count == 0 } == true)
        // And that bucket's weekStart is the start of the current week.
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        #expect(buckets.last?.weekStart == currentWeekStart)
    }

    // MARK: - Empty weeks are present, not omitted

    // (b) A week with no workouts is present with a count of zero — never
    // dropped. With one workout in the current week and weeks = 8, all eight
    // buckets exist and seven of them are zero.
    @Test func emptyWeeksArePresentWithZeroCount() throws {
        let context = try makeContainer()

        let completedAt = midWeek
        let workout = Workout(name: "Leg Day", startedAt: completedAt, completedAt: completedAt)
        context.insert(workout)

        let all = try context.fetch(FetchDescriptor<Workout>())
        let buckets = WeeklyWorkoutBuckets.buckets(for: all, weeks: 8, now: now, calendar: calendar)

        #expect(buckets.count == 8)
        let zeroWeeks = buckets.filter { $0.count == 0 }
        #expect(zeroWeeks.count == 7)
    }

    // MARK: - Only completed workouts count

    // (c) An in-progress workout (completedAt == nil) does NOT count toward
    // the total or the chart. One completed + one in-progress in the same week
    // yields a count of 1, not 2.
    @Test func onlyCompletedWorkoutsCount() throws {
        let context = try makeContainer()

        let completedAt = midWeek
        let done = Workout(name: "Done", startedAt: completedAt, completedAt: completedAt)
        context.insert(done)

        let inProgress = Workout(name: "In Progress", startedAt: completedAt)
        context.insert(inProgress)

        let all = try context.fetch(FetchDescriptor<Workout>())
        let buckets = WeeklyWorkoutBuckets.buckets(for: all, weeks: 8, now: now, calendar: calendar)

        #expect(buckets.last?.count == 1)
        #expect(buckets.reduce(0) { $0 + $1.count } == 1)
    }

    // MARK: - Window size and ending

    // (d) The result covers exactly the requested number of weeks, ending with
    // the current one.
    @Test func coversExactlyRequestedWeeksEndingWithCurrent() {
        // No workouts at all — every bucket is zero, but the count and the
        // final weekStart are still exact.
        let buckets4 = WeeklyWorkoutBuckets.buckets(for: [], weeks: 4, now: now, calendar: calendar)
        #expect(buckets4.count == 4)
        #expect(buckets4.last?.weekStart == calendar.dateInterval(of: .weekOfYear, for: now)!.start)

        let buckets12 = WeeklyWorkoutBuckets.buckets(for: [], weeks: 12, now: now, calendar: calendar)
        #expect(buckets12.count == 12)
        #expect(buckets12.last?.weekStart == calendar.dateInterval(of: .weekOfYear, for: now)!.start)

        // Weeks <= 0 returns empty.
        #expect(WeeklyWorkoutBuckets.buckets(for: [], weeks: 0, now: now, calendar: calendar) == [])
        #expect(WeeklyWorkoutBuckets.buckets(for: [], weeks: -3, now: now, calendar: calendar) == [])
    }

    // The buckets are consecutive weeks oldest-first (each start is exactly
    // seven days after the previous).
    @Test func bucketsAreConsecutiveSevenDayWeeksOldestFirst() {
        let buckets = WeeklyWorkoutBuckets.buckets(for: [], weeks: 8, now: now, calendar: calendar)
        let weekSeconds = TimeInterval(7 * 24 * 60 * 60)
        for i in 1..<buckets.count {
            #expect(buckets[i].weekStart.timeIntervalSince(buckets[i - 1].weekStart) == weekSeconds)
        }
    }

    // MARK: - Same-week coalescing

    // (e) Two completed workouts in the SAME week produce a count of 2 in one
    // bucket, not two separate entries.
    @Test func twoWorkoutsSameWeekProduceCountOfTwo() throws {
        let context = try makeContainer()

        // Both in the current week: mid-week and late-week.
        let wed = midWeek
        let fri = lateWeek
        context.insert(Workout(name: "A", startedAt: wed, completedAt: wed))
        context.insert(Workout(name: "B", startedAt: fri, completedAt: fri))

        let all = try context.fetch(FetchDescriptor<Workout>())
        let buckets = WeeklyWorkoutBuckets.buckets(for: all, weeks: 8, now: now, calendar: calendar)

        #expect(buckets.count == 8)
        #expect(buckets.last?.count == 2)
        #expect(buckets.dropLast().allSatisfy { $0.count == 0 } == true)
        // Exactly one bucket is non-zero — not two entries.
        #expect(buckets.filter { $0.count > 0 }.count == 1)
    }

    // MARK: - Out-of-window workouts are ignored

    // A workout older than the window does not appear in any bucket.
    @Test func workoutsOutsideWindowAreIgnored() throws {
        let context = try makeContainer()

        // Ten weeks ago — outside the 8-week window.
        let old = calendar.date(byAdding: .weekOfYear, value: -10, to: now)!
        context.insert(Workout(name: "Ancient", startedAt: old, completedAt: old))

        // Inside the window (current week).
        let recent = midWeek
        context.insert(Workout(name: "Recent", startedAt: recent, completedAt: recent))

        let all = try context.fetch(FetchDescriptor<Workout>())
        let buckets = WeeklyWorkoutBuckets.buckets(for: all, weeks: 8, now: now, calendar: calendar)

        #expect(buckets.reduce(0) { $0 + $1.count } == 1)
        #expect(buckets.last?.count == 1)
    }
}
