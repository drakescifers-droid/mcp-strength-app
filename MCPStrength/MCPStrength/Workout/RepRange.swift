//
//  RepRange.swift
//  MCPStrength
//
//  A rep prescription is either a fixed target ("8") or a range ("6-8"). A
//  template carries one or the other (never both); a workout set carries a
//  single performed number and has no range. This file owns the parsing and
//  formatting of that prescription so it can be reasoned about and tested
//  independently of any view — a typo here becomes a wrong prescription, so
//  the parser must reject bad input rather than silently guess.
//

import Foundation

/// A rep prescription: a fixed target, or an inclusive range.
enum RepRange: Equatable, Sendable {
    /// A single target rep count, e.g. "8".
    case fixed(Int)
    /// An inclusive range, e.g. "6-8" (start...end).
    case range(start: Int, end: Int)
}

/// Outcome of parsing a reps text field.
enum RepRangeParseOutcome: Equatable, Sendable {
    /// Empty/whitespace input — valid, meaning "no prescription set".
    case unset
    /// Input parsed to a concrete prescription.
    case valid(RepRange)
    /// Input is malformed (e.g. "abc", "6-", "8-6", "0", negative). The field
    /// must NOT be silently coerced; the caller keeps the user's text and shows
    /// an invalid indication.
    case invalid
}

struct RepRangeParser {

    /// Parse `text` into a prescription.
    ///
    /// - Empty (or all-whitespace) input is `.unset`.
    /// - A single positive integer like `"8"` is `.valid(.fixed(8))`.
    /// - Two positive integers joined by `-` or en dash `–`, optionally
    ///   surrounded by spaces (`"6 - 8"`), is `.valid(.range(start:end:))`
    ///   when `allowRange` is true and start <= end. When `allowRange` is
    ///   false (the workout screen — a performance has a number, not a range),
    ///   a dashed form is `.invalid`.
    /// - Everything else (`"abc"`, `"6-"`, `"-8"`, `"8-6"`, `"0"`, `"-5"`) is
    ///   `.invalid`.
    static func parse(_ text: String, allowRange: Bool) -> RepRangeParseOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return .unset
        }

        // Accept both ASCII hyphen and Unicode en dash as the range separator.
        if allowRange, let separatorRange = trimmed.rangeOfCharacter(
            from: CharacterSet(charactersIn: "-–")
        ) {
            // Exactly one separator, and it is not at the very start or end
            // (so "6-" and "-8" are rejected, not silently repaired).
            let sep = trimmed[separatorRange]
            let parts = trimmed.components(separatedBy: sep)
            guard parts.count == 2 else { return .invalid }
            let lhs = parts[0].trimmingCharacters(in: .whitespaces)
            let rhs = parts[1].trimmingCharacters(in: .whitespaces)
            guard !lhs.isEmpty, !rhs.isEmpty,
                  let start = Int(lhs), let end = Int(rhs)
            else { return .invalid }
            guard start >= 1, end >= 1, start <= end else { return .invalid }
            return .valid(.range(start: start, end: end))
        }

        guard let value = Int(trimmed), value >= 1 else { return .invalid }
        return .valid(.fixed(value))
    }

    /// Format a prescription for display: `"8"` for a fixed target, `"6-8"`
    /// for a range. Always emits an ASCII hyphen so the canonical form round-trips.
    static func format(_ range: RepRange) -> String {
        switch range {
        case .fixed(let value):
            return "\(value)"
        case .range(let start, let end):
            return "\(start)-\(end)"
        }
    }
}

// MARK: - Model field bridging

extension RepRange {

    /// Build a prescription from a `TemplateSet`'s fields. A fixed `reps` wins
    /// over a range; if neither is present this returns `nil` (unset).
    static func fromTemplate(reps: Int?, start: Int?, end: Int?) -> RepRange? {
        if let reps {
            return .fixed(reps)
        }
        if let start, let end {
            return .range(start: start, end: end)
        }
        return nil
    }

    /// Split this prescription back into the mutually exclusive model fields:
    /// `.fixed` writes `reps` and clears the range; `.range` writes the range
    /// and clears `reps`. A set is either a fixed target or a range, never both.
    func templateFields() -> (reps: Int?, start: Int?, end: Int?) {
        switch self {
        case .fixed(let value):
            return (value, nil, nil)
        case .range(let start, let end):
            return (nil, start, end)
        }
    }

    /// Build a prescription from a `WorkoutSet`'s single `reps` number. A
    /// performance has no range — only a fixed target or nothing.
    static func fromWorkout(reps: Int?) -> RepRange? {
        reps.map { .fixed($0) }
    }
}
