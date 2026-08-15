//
//  RepRangeTests.swift
//  MCPStrengthTests
//
//  Covers the rep-range parser/formatter and the RPE validator. These live in
//  Workout/ (not inside a view body) precisely so they can be tested in
//  isolation — a typo here becomes a wrong prescription, so the parser must
//  REJECT bad input rather than silently coerce it.
//

import Testing
import Foundation
@testable import MCPStrength

struct RepRangeTests {

    // MARK: - Parsing the good forms

    @Test func parsesFixedTarget() {
        #expect(RepRangeParser.parse("8", allowRange: true) == .valid(.fixed(8)))
    }

    @Test func parsesRangeWithHyphen() {
        #expect(RepRangeParser.parse("6-8", allowRange: true) == .valid(.range(start: 6, end: 8)))
    }

    @Test func parsesRangeWithEnDash() {
        #expect(RepRangeParser.parse("6–8", allowRange: true) == .valid(.range(start: 6, end: 8)))
    }

    @Test func parsesRangeWithSurroundingSpaces() {
        #expect(RepRangeParser.parse("6 - 8", allowRange: true) == .valid(.range(start: 6, end: 8)))
    }

    // MARK: - Rejecting the bad forms — assert invalid, never coerced

    @Test func rejectsLetters() {
        #expect(RepRangeParser.parse("abc", allowRange: true) == .invalid)
    }

    @Test func rejectsTrailingDash() {
        #expect(RepRangeParser.parse("6-", allowRange: true) == .invalid)
    }

    @Test func rejectsLeadingDash() {
        #expect(RepRangeParser.parse("-8", allowRange: true) == .invalid)
    }

    @Test func rejectsReversedRange() {
        #expect(RepRangeParser.parse("8-6", allowRange: true) == .invalid)
    }

    @Test func rejectsZero() {
        #expect(RepRangeParser.parse("0", allowRange: true) == .invalid)
    }

    @Test func rejectsNegative() {
        #expect(RepRangeParser.parse("-5", allowRange: true) == .invalid)
    }

    // MARK: - Empty is valid and means unset

    @Test func emptyIsUnset() {
        #expect(RepRangeParser.parse("", allowRange: true) == .unset)
    }

    @Test func whitespaceIsUnset() {
        #expect(RepRangeParser.parse("   ", allowRange: true) == .unset)
    }

    // MARK: - Formatting round-trips

    @Test func formatFixed() {
        #expect(RepRangeParser.format(.fixed(8)) == "8")
    }

    @Test func formatRange() {
        #expect(RepRangeParser.format(.range(start: 6, end: 8)) == "6-8")
    }

    @Test func roundTripFixed() {
        let outcome = RepRangeParser.parse("8", allowRange: true)
        guard case .valid(let range) = outcome else {
            Issue.record("expected .valid, got \(outcome)"); return
        }
        #expect(RepRangeParser.format(range) == "8")
    }

    @Test func roundTripRange() {
        let outcome = RepRangeParser.parse("6-8", allowRange: true)
        guard case .valid(let range) = outcome else {
            Issue.record("expected .valid, got \(outcome)"); return
        }
        #expect(RepRangeParser.format(range) == "6-8")
    }

    @Test func roundTripEnDashNormalizesToHyphen() {
        let outcome = RepRangeParser.parse("6–8", allowRange: true)
        guard case .valid(let range) = outcome else {
            Issue.record("expected .valid, got \(outcome)"); return
        }
        // Canonical format always uses an ASCII hyphen.
        #expect(RepRangeParser.format(range) == "6-8")
    }

    // MARK: - Mutual exclusivity: fixed clears range, range clears fixed

    @Test func fixedTargetClearsRangeFields() {
        let fields = RepRange.fixed(8).templateFields()
        #expect(fields.reps == 8)
        #expect(fields.start == nil)
        #expect(fields.end == nil)
    }

    @Test func rangeClearsFixedField() {
        let fields = RepRange.range(start: 6, end: 8).templateFields()
        #expect(fields.reps == nil)
        #expect(fields.start == 6)
        #expect(fields.end == 8)
    }

    @Test func fromTemplatePrefersFixedWhenBothPresent() {
        // A fixed reps wins over a range when bridging (defensive — the editor
        // never writes both, but read must be deterministic).
        let range = RepRange.fromTemplate(reps: 8, start: 6, end: 10)
        #expect(range == .fixed(8))
    }

    @Test func fromTemplateReturnsNilWhenUnset() {
        #expect(RepRange.fromTemplate(reps: nil, start: nil, end: nil) == nil)
    }

    @Test func fromWorkoutOnlyCarriesFixed() {
        #expect(RepRange.fromWorkout(reps: 8) == .fixed(8))
        #expect(RepRange.fromWorkout(reps: nil) == nil)
    }
}
