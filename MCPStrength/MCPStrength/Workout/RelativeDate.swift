//
//  RelativeDate.swift
//  MCPStrength
//
//  Coarse last-performed strings for the template card and the template
//  overview. Lives here (Foundation only) so the two call sites cannot drift
//  and so tests can inject `now` — a wall-clock default is how a suite
//  starts failing at midnight.
//

import Foundation

enum RelativeDate {
    /// "Today", "Yesterday", "4 days ago", "Last week", "2 weeks ago",
    /// "3 months ago", "1 years ago". Coarse on purpose — a hint, not a
    /// precise timestamp. `now` defaults to `Date()` for call sites; tests
    /// pass an explicit clock.
    static func lastPerformed(from date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let startOfDay = calendar.startOfDay(for: date)
        let dayDiff = calendar.dateComponents([.day], from: startOfDay, to: startOfToday).day ?? 0

        switch dayDiff {
        case 0:      return "Today"
        case 1:      return "Yesterday"
        case 2...6:  return "\(dayDiff) days ago"
        case 7...13: return "Last week"
        case 14...29: return "\(dayDiff / 7) weeks ago"
        case 30...364: return "\(dayDiff / 30) months ago"
        default:     return "\(dayDiff / 365) years ago"
        }
    }
}
