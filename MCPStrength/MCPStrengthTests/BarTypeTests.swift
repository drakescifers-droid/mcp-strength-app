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
        #expect(BarType.olympicBar.weight(in: .lbs) == 45)
        #expect(BarType.standardBar.weight(in: .lbs) == 33)
        #expect(BarType.ezBar.weight(in: .lbs) == 20)
        #expect(BarType.trapBar.weight(in: .lbs) == 75)
        #expect(BarType.dumbbell.weight(in: .lbs) == 0)
        #expect(BarType.other.weight(in: .lbs) == 0)
    }

    // The metric values are gym standards, NOT conversions of the pounds ones.
    // A bar is a physical object made to one standard or the other.
    @Test func metricWeightsAreStandardsRatherThanConversions() {
        #expect(BarType.olympicBar.weight(in: .kg) == 20)
        #expect(BarType.standardBar.weight(in: .kg) == 15)
        #expect(BarType.ezBar.weight(in: .kg) == 10)
        #expect(BarType.trapBar.weight(in: .kg) == 34)
    }

    // The load-bearing assertion of the pair: converting one into the other
    // gives the WRONG bar, which is why there are two constants and not one
    // number with a conversion in front of it. 45 lb is 20.41 kg and no gym
    // owns that bar.
    @Test func convertingPoundsToKilogramsWouldGiveTheWrongBar() {
        let converted = BarType.olympicBar.weight(in: .lbs) * 0.45359237
        #expect(converted != BarType.olympicBar.weight(in: .kg))
        #expect(abs(converted - 20.41) < 0.01)
    }

    // No bar means no bar in either unit — and 0 must stay 0 rather than
    // becoming a floor of zero by accident. `WarmupSets.plan` depends on it.
    @Test func barlessCasesAreZeroInEveryUnit() {
        for unit in WeightUnit.allCases {
            #expect(BarType.dumbbell.weight(in: unit) == 0)
            #expect(BarType.other.weight(in: unit) == 0)
        }
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
