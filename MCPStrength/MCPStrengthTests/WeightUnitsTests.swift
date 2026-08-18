//
//  WeightUnitsTests.swift
//  MCPStrengthTests
//
//  The conversion layer between stored kilograms and what the user reads.
//
//  The load-bearing property is the ROUND TRIP: a weight the user typed has to
//  come back as the weight the user typed. Everything a lifter enters goes
//  through a conversion now, so a failure here is not a visible bug, it is a
//  training log that drifts by a fraction of a pound per set and never says so.
//

import Testing
import Foundation
@testable import MCPStrength

struct WeightUnitsTests {

    // MARK: - Round trip

    // Every load a pounds lifter plausibly types, through kg and back.
    @Test func poundsSurviveTheRoundTripToKilogramsAndBack() {
        let typed: [Double] = [
            2.5, 5, 20, 45,          // empty bars and the smallest plates
            65, 90, 135, 137.5, 138, // the ramp's own worked examples
            185, 225, 315, 405, 495, // plate math a lifter recognises
            183.4,                   // a bodyweight, not a plate load
        ]
        for weight in typed {
            let stored = WeightUnits.kilograms(from: weight, in: .lbs)
            let shown = WeightUnits.displayed(from: stored, in: .lbs)
            #expect(shown == weight, "\(weight) lb came back as \(shown)")
        }
    }

    // A metric lifter's numbers are stored with no conversion at all, so these
    // must be exact rather than merely close.
    @Test func kilogramsAreStoredUntouched() {
        let typed: [Double] = [1.25, 2.5, 10, 15, 20, 61.25, 100, 137.5, 180.5]
        for weight in typed {
            #expect(WeightUnits.kilograms(from: weight, in: .kg) == weight)
            let shown = WeightUnits.displayed(from: weight, in: .kg)
            #expect(shown == weight, "\(weight) kg came back as \(shown)")
        }
    }

    // 135 lb is 61.23496995 kg, and the way back happens to divide exactly.
    //
    // Written the other way round first, asserting the division overshoots —
    // and it does not, for this value. Which is the point: display rounding is
    // INSURANCE, not a correction applied to a known artefact. Whether any
    // given weight survives the division intact is a property of the binary
    // representation, not something to rely on, so the assertion is that the
    // value shown is right and never that the raw quotient is wrong.
    @Test func storedKilogramsAreExactAndDisplayIsWhatWasTyped() {
        let stored = WeightUnits.kilograms(from: 135, in: .lbs)
        #expect(abs(stored - 61.23496995) < 1e-9)
        #expect(WeightUnits.displayed(from: stored, in: .lbs) == 135)

        // Rounding to the display precision is what makes it safe for values
        // where the division does NOT land exactly.
        #expect(WeightUnits.round(134.99999999999997, toNearest: WeightUnits.displayPrecision) == 135)
        #expect(WeightUnits.round(135.00000000000003, toNearest: WeightUnits.displayPrecision) == 135)
    }

    // MARK: - Display precision is not a plate size

    // The trap the file comment names. Rounding display to a plate increment
    // would silently rewrite what the user entered — 138 is a real thing to
    // type on a machine with 1 lb jumps, and it must not become 137.5.
    @Test func displayPrecisionDoesNotRewriteWhatTheUserTyped() {
        for weight in [136.0, 137.0, 138.0, 139.0, 141.0] {
            let stored = WeightUnits.kilograms(from: weight, in: .lbs)
            #expect(WeightUnits.displayed(from: stored, in: .lbs) == weight)
        }
        // And it is genuinely finer than any plate.
        #expect(WeightUnits.displayPrecision < WeightUnits.plateIncrement(for: .kg))
        #expect(WeightUnits.displayPrecision < WeightUnits.plateIncrement(for: .lbs))
    }

    // MARK: - Plate increments

    // Stocking conventions, not conversions. If somebody "simplifies" these
    // into one constant with a conversion in front, this fails.
    @Test func plateIncrementsAreNotConversionsOfEachOther() {
        #expect(WeightUnits.plateIncrement(for: .lbs) == 5)
        #expect(WeightUnits.plateIncrement(for: .kg) == 2.5)

        let converted = WeightUnits.plateIncrement(for: .kg) / WeightUnits.kilogramsPerPound
        #expect(converted != WeightUnits.plateIncrement(for: .lbs))
        #expect(abs(converted - 5.51) < 0.01)
    }

    // MARK: - Rounding rule

    // Ties take the heavier plate. `.toNearestOrEven` would send 62.5 to 60,
    // which is banker's rounding applied to a barbell.
    @Test func roundingTiesTakeTheHeavierPlate() {
        #expect(WeightUnits.round(62.5, toNearest: 5) == 65)
        #expect(WeightUnits.round(67.5, toNearest: 5) == 70)
        #expect(WeightUnits.round(57.5, toNearest: 5) == 60)

        // The reference app's measured ramp for a 90 lb working set, which is
        // where this rule was originally pinned down.
        #expect(WeightUnits.round(45, toNearest: 5) == 45)
        #expect(WeightUnits.round(54, toNearest: 5) == 55)
        #expect(WeightUnits.round(67.5, toNearest: 5) == 70)
    }

    @Test func roundingIsSaneAtMetricIncrements() {
        // 61.25 is NOT a multiple of 2.5 — the multiples either side of 61.23
        // are 60 and 62.5, and 60 is nearer. Asserted the wrong way first,
        // which is a good argument for spelling out the neighbours.
        #expect(WeightUnits.round(61.23, toNearest: 2.5) == 60)
        #expect(WeightUnits.round(61.30, toNearest: 2.5) == 62.5)
        #expect(WeightUnits.round(20, toNearest: 2.5) == 20)
        // A tie, so it takes the heavier plate.
        #expect(WeightUnits.round(21.25, toNearest: 2.5) == 22.5)
    }

    // A zero or negative increment must pass the value through rather than
    // divide by zero and return NaN — a NaN weight would render as "nan lb".
    @Test func roundingWithNoIncrementReturnsTheValue() {
        #expect(WeightUnits.round(137.5, toNearest: 0) == 137.5)
        #expect(WeightUnits.round(137.5, toNearest: -5) == 137.5)
    }

    // MARK: - Zero and absence

    // Zero converts to zero in both directions. Bodyweight exercises store no
    // weight at all (nil), which never reaches this type — but a 0 that does
    // must not become something else.
    @Test func zeroStaysZero() {
        for unit in WeightUnit.allCases {
            #expect(WeightUnits.kilograms(from: 0, in: unit) == 0)
            #expect(WeightUnits.displayed(from: 0, in: unit) == 0)
        }
    }

    // The bar weights, through the layer they will be stored with. An lb
    // lifter's 45 lb bar and a kg lifter's 20 kg bar are different masses in
    // storage, and that is correct — see BarType.weight(in:).
    @Test func barWeightsStoreAsDifferentMassesPerUnit() {
        let poundsBar = WeightUnits.kilograms(from: BarType.olympicBar.weight(in: .lbs), in: .lbs)
        let metricBar = WeightUnits.kilograms(from: BarType.olympicBar.weight(in: .kg), in: .kg)

        #expect(abs(poundsBar - 20.41) < 0.01)
        #expect(metricBar == 20)
        #expect(poundsBar != metricBar)
    }
}
