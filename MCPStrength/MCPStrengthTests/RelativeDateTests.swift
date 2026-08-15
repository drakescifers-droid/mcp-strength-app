//
//  RelativeDateTests.swift
//  MCPStrengthTests
//
//  Covers RelativeDate.lastPerformed. Every case passes an explicit `now:`
//  so the strings do not depend on the wall clock — a suite that computes
//  expectations from Date() is how tests start failing at midnight.
//

import Testing
import Foundation
@testable import MCPStrength

struct RelativeDateTests {

    /// Mid-afternoon on a fixed calendar day so day-boundary math is stable
    /// under Calendar.current, including DST.
    private var now: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 15
        components.hour = 15
        components.minute = 0
        return Calendar.current.date(from: components)!
    }

    private func daysBefore(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: now)!
    }

    @Test func sameDayIsToday() {
        #expect(RelativeDate.lastPerformed(from: now, now: now) == "Today")
    }

    @Test func oneDayIsYesterday() {
        #expect(RelativeDate.lastPerformed(from: daysBefore(1), now: now) == "Yesterday")
    }

    @Test func fourDaysAgo() {
        #expect(RelativeDate.lastPerformed(from: daysBefore(4), now: now) == "4 days ago")
    }

    @Test func sevenDaysIsLastWeek() {
        #expect(RelativeDate.lastPerformed(from: daysBefore(7), now: now) == "Last week")
    }

    @Test func thirteenDaysIsStillLastWeek() {
        #expect(RelativeDate.lastPerformed(from: daysBefore(13), now: now) == "Last week")
    }

    @Test func exactlyFourteenDaysIsTwoWeeksAgo() {
        #expect(RelativeDate.lastPerformed(from: daysBefore(14), now: now) == "2 weeks ago")
    }
}
