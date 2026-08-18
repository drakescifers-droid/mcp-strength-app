//
//  BarTypeTests.swift
//  MCPStrengthTests
//
//  Pins the empty-bar weights. These six cases are values of the live
//  Postgres enum `public.bar_type`; the numbers are what the reference
//  app uses for the plate and warm-up calculators.
//

import Testing
@testable import MCPStrength

struct BarTypeTests {

    @Test func referenceWeightsArePinnedByCase() {
        #expect(BarType.olympicBar.weight == 45)
        #expect(BarType.standardBar.weight == 33)
        #expect(BarType.ezBar.weight == 20)
        #expect(BarType.trapBar.weight == 75)
        #expect(BarType.dumbbell.weight == 0)
        #expect(BarType.other.weight == 0)
    }

    @Test func theSixLivePostgresCasesAreUnchanged() {
        // Postgres can ADD a value; it cannot drop one without recreating
        // the type, which a live column makes impossible. A rename here
        // would decode as unknown on every existing row.
        #expect(BarType.allCases.map(\.rawValue) == [
            "olympicBar", "standardBar", "ezBar", "trapBar", "dumbbell", "other",
        ])
    }

    @Test func hammerStrengthRawValueMatchesThePostgresEnum() {
        // docs/05-database.md § Naming: the Swift raw value IS the
        // column value. A mapping table between the two is how Phase 0
        // silently rewrote an unknown set_type. The ninth *case* is
        // blocked by OneRepMax.supportsEstimate (owned-path limit);
        // the spelling is still pinned so the companion cannot drift.
        #expect(ExerciseCategory.hammerStrength == "hammerStrength")
    }
}
