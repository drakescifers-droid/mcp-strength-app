//
//  OneRepMaxTests.swift
//  MCPStrengthTests
//
//  Covers the 1RM estimate.
//
//  The first block pins the FORMULA against real observed output, and it now
//  spans 1-15 reps ON PURPOSE. The original version of this file only had
//  samples up to 10 reps, which is exactly where Brzycki and Epley cross over —
//  so it passed against a Brzycki-only implementation that was wrong for every
//  set above 10. A fixture range that never exercises the thing distinguishing
//  the candidates will fit perfectly and prove nothing.
//

import Testing
import Foundation
@testable import MCPStrength

struct OneRepMaxTests {

    // MARK: - The formula, and the evidence for it

    /// (weight, reps, shown) triples read off the reference app, spanning
    /// 3-15 reps so BOTH sides of the Brzycki/Epley crossover are covered.
    @Test(arguments: [
        // Low reps — Brzycki is the smaller, so min() picks it.
        (60.0, 3, 64.0), (100.0, 3, 106.0), (180.0, 4, 196.0), (210.0, 4, 229.0),
        (90.0, 5, 101.0), (140.0, 5, 158.0), (160.0, 5, 180.0), (155.0, 5, 174.0),
        (160.0, 6, 186.0), (140.0, 6, 163.0), (180.0, 6, 209.0),
        (90.0, 7, 108.0), (135.0, 7, 162.0), (180.0, 7, 216.0),
        (230.0, 8, 286.0), (100.0, 8, 124.0), (90.0, 8, 112.0), (65.0, 8, 81.0),
        (130.0, 8, 161.0), (225.0, 8, 279.0), (75.0, 8, 93.0),
        (90.0, 9, 116.0), (35.0, 9, 45.0), (210.0, 9, 270.0), (145.0, 9, 186.0),
        (90.0, 10, 120.0), (135.0, 10, 180.0), (35.0, 10, 47.0), (200.0, 10, 267.0),
        (170.0, 10, 227.0), (270.0, 10, 360.0), (220.0, 10, 293.0), (50.0, 10, 67.0),
        // High reps — Epley is the smaller. A Brzycki-only build fails EVERY
        // one of these, and the original fixture had none of them.
        (75.0, 11, 102.0),   // exact 102.5 — rounds DOWN, to even
        (125.0, 12, 175.0), (380.0, 12, 532.0), (340.0, 12, 476.0), (225.0, 12, 315.0),
        (155.0, 13, 222.0), (130.0, 13, 186.0),
        (220.0, 14, 323.0),
        (220.0, 15, 330.0), (135.0, 15, 202.0),  // 202.5 — rounds DOWN, to even
    ])
    func matchesTheReferenceApp(weight: Double, reps: Int, expected: Double) {
        #expect(OneRepMax.estimate(weight: weight, reps: reps) == expected)
    }

    @Test func isNeitherFormulaOnItsOwn() {
        // The guard against "simplifying" to one formula. Each of these is
        // correct for min() and wrong for exactly one of the candidates.
        #expect(OneRepMax.estimate(weight: 90, reps: 7) == 108)    // Epley says 111
        #expect(OneRepMax.estimate(weight: 380, reps: 12) == 532)  // Brzycki says 547
    }

    @Test func theTwoFormulasCrossOverAtTenReps() {
        // The fact that made the first derivation wrong. Documented as a test
        // so the next person sampling data knows where to sample.
        let below = OneRepMax.estimate(weight: 100, reps: 9)!
        let above = OneRepMax.estimate(weight: 100, reps: 11)!
        #expect(below == (100.0 * 36 / 28).rounded(), "below 10 reps should follow Brzycki")
        #expect(above == (100.0 * (1 + 11.0 / 30)).rounded(), "above 10 reps should follow Epley")
    }

    @Test func aSingleIsItsOwnMax() {
        // 36/(37−1) = 1. A formula that failed here would be wrong about the
        // one case the user can verify without arithmetic.
        #expect(OneRepMax.estimate(weight: 225, reps: 1) == 225)
    }

    // MARK: - Where it must refuse

    @Test func highRepSetsStillGetAnEstimate() {
        // No rep cap — the reference app shows these, and min() keeps the
        // number conservative by construction.
        #expect(OneRepMax.estimate(weight: 220, reps: 15) == 330)
        #expect(OneRepMax.estimate(weight: 100, reps: 20) != nil)
    }

    @Test func brzyckiNeverGetsToReturnANegativeNumber() {
        // Brzycki is undefined at 37 reps and negative beyond it. Since the
        // result is a MINIMUM, an unguarded version would faithfully pick that
        // negative value — a 50-rep set would report a negative 1RM.
        for reps in [36, 37, 38, 50, 100] {
            let value = OneRepMax.estimate(weight: 100, reps: reps)
            #expect(value != nil, "\(reps) reps returned nothing")
            #expect(value! > 0, "\(reps) reps produced a non-positive estimate: \(value!)")
        }
        // And it is still monotonic across the discontinuity.
        #expect(OneRepMax.estimate(weight: 100, reps: 38)! > OneRepMax.estimate(weight: 100, reps: 36)!)
    }

    @Test func missingOrNonsenseInputGetsNoEstimate() {
        #expect(OneRepMax.estimate(weight: nil, reps: 5) == nil)
        #expect(OneRepMax.estimate(weight: 100, reps: nil) == nil)
        #expect(OneRepMax.estimate(weight: 0, reps: 5) == nil)
        #expect(OneRepMax.estimate(weight: -40, reps: 5) == nil, "assistance weight is not a load")
        #expect(OneRepMax.estimate(weight: 100, reps: 0) == nil)
    }

    // MARK: - Category rules

    @Test func loadedCategoriesSupportAnEstimate() {
        for category in [ExerciseCategory.barbell, .dumbbell, .machineOther] {
            #expect(OneRepMax.supportsEstimate(category), "\(category) should support 1RM")
        }
    }

    @Test func bodyweightAndTimedCategoriesDoNot() {
        // Weighted bodyweight stores ADDED weight, so "+230 lb × 9" is not
        // 230 lb of load and an estimate from it is meaningless without the
        // user's bodyweight. Assisted stores negative assistance. The rest have
        // no weight at all. The reference app blanks these too.
        for category in [ExerciseCategory.weightedBodyweight, .assistedBodyweight,
                         .repsOnly, .cardio, .duration] {
            #expect(!OneRepMax.supportsEstimate(category), "\(category) should NOT support 1RM")
        }
    }

    @Test func everyCategoryHasAnAnswer() {
        // A category added later must be classified deliberately rather than
        // falling into whichever branch the compiler picked.
        for category in ExerciseCategory.allCases {
            _ = OneRepMax.supportsEstimate(category)
        }
        #expect(ExerciseCategory.allCases.count == 8)
    }

    // MARK: - The per-set convenience

    // A stored set carries KILOGRAMS, so these build one from the pounds it
    // represents and ask for the estimate back in pounds. The expected numbers
    // are unchanged from when storage was pounds, which is the assertion that
    // matters: the reference app's 1RM column did not move.
    private func poundsSet(_ pounds: Double, reps: Int) -> WorkoutSet {
        WorkoutSet(
            order: 0,
            weight: WeightUnits.kilograms(from: pounds, in: .lbs),
            reps: reps
        )
    }

    @Test func aWeightedBodyweightSetGetsNothingEvenWithGoodNumbers() {
        // The trap this exists for: the numbers alone look perfectly
        // estimable, and only the category knows they are not.
        let set = poundsSet(230, reps: 9)
        #expect(OneRepMax.estimate(weight: 230, reps: 9) != nil, "numbers alone would estimate")
        #expect(OneRepMax.estimate(for: set, category: .weightedBodyweight, in: .lbs) == nil)
    }

    @Test func aBarbellSetGetsAnEstimate() {
        let set = poundsSet(135, reps: 10)
        #expect(OneRepMax.estimate(for: set, category: .barbell, in: .lbs) == 180)
    }

    @Test func anUnknownExerciseGetsNothing() {
        // exercise is optional on WorkoutExercise; a nil category must not be
        // treated as "sure, estimate it".
        let set = poundsSet(135, reps: 10)
        #expect(OneRepMax.estimate(for: set, category: nil, in: .lbs) == nil)
    }

    // THE REASON THE ESTIMATE TAKES A UNIT. It rounds to a whole unit, so
    // rounding in kilograms and converting afterwards is not the same number as
    // rounding in pounds — and only the pounds one matches the reference app
    // the formula was fitted to.
    @Test func theEstimateIsRoundedInTheUnitItIsShownIn() {
        let set = poundsSet(135, reps: 10)

        let inPounds = OneRepMax.estimate(for: set, category: .barbell, in: .lbs)
        #expect(inPounds == 180)

        // The same set asked for in kilograms: estimated from 61.23 kg, so it
        // rounds to a whole KILOGRAM (82), not to 180 lb converted (81.65).
        let inKilograms = OneRepMax.estimate(for: set, category: .barbell, in: .kg)
        #expect(inKilograms == 82)
        #expect(inKilograms != WeightUnits.kilograms(from: 180, in: .lbs))
    }

    // MARK: - Presentation

    @Test func estimatesAreWholeNumbers() {
        // The input is a rough model. Decimals would imply precision that is
        // not there, and 157.5 lb is not a thing anyone racks.
        for reps in 1...20 {
            let value = try! #require(OneRepMax.estimate(weight: 137.5, reps: reps))
            #expect(value == value.rounded(), "\(reps) reps produced a fractional estimate")
        }
    }

    @Test func exactHalvesRoundToEven() {
        // The rule the reference actually uses, pinned directly. Swift's plain
        // `.rounded()` gets both of these wrong by one.
        #expect(OneRepMax.estimate(weight: 75, reps: 11) == 102)   // 102.5 -> 102
        #expect(OneRepMax.estimate(weight: 135, reps: 15) == 202)  // 202.5 -> 202
    }
}
