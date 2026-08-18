//
//  WarmupSetsTests.swift
//  MCPStrengthTests
//
//  Covers WarmupSets.plan — the percentage ramp, plate rounding, and the
//  cases that collapse the ramp to fewer sets or to nothing. Lives in
//  Workout/ (no SwiftUI / SwiftData) so it can be tested in isolation.
//
//  THE RAMP IS MEASURED, NOT INVENTED. The first test below reproduces the
//  reference app's own auto-generated output for a 90 lb working set. If a
//  percentage or a rep count is ever "tidied", that test is what says the
//  tidying was wrong.
//
//  **Every weight here is in the unit passed to `plan`, not stored kilograms.**
//  The pounds cases below are unchanged from before canonical storage landed,
//  which is the point: the ramp is a gym calculation and did not move. The
//  kilogram section at the bottom is the part that would otherwise be assumed
//  to be a conversion of it, and is not.
//

import Testing
import Foundation
@testable import MCPStrength

struct WarmupSetsTests {

    // THE REFERENCE CASE. Screenshot of the reference app, 90 lb working set,
    // auto-generated (not hand-edited): 45×5, 55×5, 70×3.
    //
    //   0.50 × 90 = 45      -> 45
    //   0.60 × 90 = 54      -> 55   (rounds up)
    //   0.75 × 90 = 67.5    -> 70   (exact midpoint, goes to the heavier plate)
    //
    // All three rounding behaviours in one case, against real observed output.
    @Test func ninetyReproducesTheReferenceRamp() {
        let plan = WarmupSets.plan(forWorkingWeight: 90, in: .lbs)
        #expect(plan.map(\.weight) == [45, 55, 70])
        #expect(plan.map(\.reps) == [5, 5, 3])
        #expect(plan.map(\.setType) == [.warmup, .warmup, .warmup])
    }

    // 170 rounds DOWN in the middle, 140 rounds UP — both directions pinned,
    // neither relying on a midpoint.
    //   170: 85 exact / 102 -> 100 (down) / 127.5 -> 130 (midpoint up)
    //   140: 70 exact /  84 ->  85 (up)   / 105 exact
    @Test func roundingGoesUpAndDown() {
        let heavy = WarmupSets.plan(forWorkingWeight: 170, in: .lbs)
        #expect(heavy[1].weight == 100, "102 must round down to 100, not up to 105")

        let lighter = WarmupSets.plan(forWorkingWeight: 140, in: .lbs)
        #expect(lighter[1].weight == 85, "84 must round up to 85, not down to 80")
        #expect(lighter.map(\.weight) == [70, 85, 105])
    }

    // 125 × 0.50 = 62.5, the exact midpoint of 60 and 65. Half-up (away from
    // zero) is 65; half-to-even is 60. OneRepMax deliberately uses the OTHER
    // rule, so leaving this implicit would inherit whichever default the next
    // editor assumed.
    @Test func midpointRoundsToTheHeavierPlate() {
        let plan = WarmupSets.plan(forWorkingWeight: 125, in: .lbs)
        #expect(plan[0].weight == 65, "62.5 must become 65, not 60")
        #expect(plan.map(\.weight) == [65, 75, 95])
    }

    // 20 × 0.50 / 0.60 / 0.75 = 10 / 12 / 15 → 10 / 10 / 15. The second 10 is
    // the same plate as the first; keep the first and drop the duplicate.
    @Test func lightWeightDropsDuplicatePlates() {
        let plan = WarmupSets.plan(forWorkingWeight: 20, in: .lbs)
        #expect(plan.map(\.weight) == [10, 15])
        #expect(plan.map(\.reps) == [5, 3])
    }

    // 10 × 0.50 / 0.60 / 0.75 = 5 / 6 / 7.5 → 5 / 5 / 10. The duplicate 5
    // collapses, and 10 is the working weight itself — not a warm-up.
    @Test func stepsAtOrAboveTheWorkingWeightAreDropped() {
        let plan = WarmupSets.plan(forWorkingWeight: 10, in: .lbs)
        #expect(plan.map(\.weight) == [5])
        #expect(plan.map(\.reps) == [5])
        #expect(plan[0].setType == .warmup)
    }

    // 5 lb: 2.5 / 3 / 3.75 → 5 / 5 / 5, every one of them the working weight.
    // Nothing honest remains, which is different from "no working weight" — a
    // weight WAS supplied, the ramp just has nowhere to stand.
    @Test func fivePoundsCollapsesToNothing() {
        #expect(WarmupSets.plan(forWorkingWeight: 5, in: .lbs).isEmpty)
    }

    @Test func missingOrNonPositiveWeightReturnsNoSets() {
        #expect(WarmupSets.plan(forWorkingWeight: nil, in: .lbs).isEmpty)
        #expect(WarmupSets.plan(forWorkingWeight: 0, in: .lbs).isEmpty)
        #expect(WarmupSets.plan(forWorkingWeight: -40, in: .lbs).isEmpty)
    }

    @Test func everyGeneratedSetIsAWarmup() {
        for weight in [20.0, 45, 95, 135, 225, 315] {
            let plan = WarmupSets.plan(forWorkingWeight: weight, in: .lbs)
            #expect(!plan.isEmpty, "\(weight) lb produced no sets")
            #expect(plan.allSatisfy { $0.setType == .warmup },
                    "\(weight) lb produced a non-warmup set")
        }
    }

    // A 45 lb empty bar still ramps — the collapse cases above are a light
    // DUMBBELL problem, not a "the barbell is light" problem.
    @Test func anEmptyBarStillProducesARamp() {
        let plan = WarmupSets.plan(forWorkingWeight: 45, in: .lbs)
        #expect(plan.map(\.weight) == [25, 35])
        #expect(plan.allSatisfy { $0.weight < 45 })
    }

    @Test func repsFollowTheRampInOrder() {
        let plan = WarmupSets.plan(forWorkingWeight: 225, in: .lbs)
        #expect(plan.map(\.reps) == [5, 5, 3])
        #expect(plan.map(\.weight) == [115, 135, 170])
    }

    // MARK: - Bar-weight floor

    // 65 × 0.50 / 0.60 / 0.75 = 32.5 / 39 / 48.75 → 35 / 40 / 50. On a
    // 45 lb bar the first two cannot be loaded. Raised: 35→45, 40→45
    // (duplicate, dropped by the existing strictly-increasing rule), 50
    // stays. Empty bar + 50, then work at 65.
    @Test func stepsBelowTheBarAreRaisedToTheBar() {
        let plan = WarmupSets.plan(forWorkingWeight: 65, barWeight: 45, in: .lbs)
        #expect(plan.map(\.weight) == [45, 50])
        #expect(plan.map(\.reps) == [5, 3])
        #expect(plan.allSatisfy { $0.setType == .warmup })
    }

    // The 90 lb reference case with the Olympic bar supplied. 45 is equal
    // to the bar, not below it, so the floor does not touch the first
    // step. The measured ramp must not move just because a caller now
    // knows which bar is on the pins.
    @Test func aStepEqualToTheBarIsKept() {
        let plan = WarmupSets.plan(forWorkingWeight: 90, barWeight: 45, in: .lbs)
        #expect(plan.map(\.weight) == [45, 55, 70])
        #expect(plan.map(\.reps) == [5, 5, 3])
    }

    @Test func aNilBarWeightIsIdenticalToOmittingTheFloor() {
        let omitted = WarmupSets.plan(forWorkingWeight: 90, in: .lbs)
        let explicitNil = WarmupSets.plan(forWorkingWeight: 90, barWeight: nil, in: .lbs)
        #expect(explicitNil == omitted)
        #expect(explicitNil.map(\.weight) == [45, 55, 70])

        // 65 is the case the floor actually changes. nil must reproduce
        // today's unfloored 35 / 40 / 50, including the unloadable steps
        // — "no floor" is not "a floor of zero".
        let unfloored = WarmupSets.plan(forWorkingWeight: 65, barWeight: nil, in: .lbs)
        #expect(unfloored.map(\.weight) == [35, 40, 50])
        #expect(unfloored == WarmupSets.plan(forWorkingWeight: 65, in: .lbs))
    }

    // BarType.dumbbell.weight and .other.weight are 0. A caller that
    // forwards `exercise.barType?.weight` will pass 0, not nil. That 0
    // must not become a floor.
    @Test func aZeroBarWeightIsNotAFloor() {
        let plan = WarmupSets.plan(forWorkingWeight: 65, barWeight: 0, in: .lbs)
        #expect(plan.map(\.weight) == [35, 40, 50])
        #expect(plan == WarmupSets.plan(forWorkingWeight: 65, in: .lbs))
    }

    // Bar at or above the work: every raised step fails
    // `rounded < workingWeight`. Nothing honest remains — same shape as
    // fivePoundsCollapsesToNothing, and not a list of unloadable plates.
    @Test func aBarHeavierThanTheWorkCollapsesToNothing() {
        #expect(WarmupSets.plan(forWorkingWeight: 65, barWeight: 65, in: .lbs).isEmpty)
        #expect(WarmupSets.plan(forWorkingWeight: 65, barWeight: 70, in: .lbs).isEmpty)
        #expect(WarmupSets.plan(forWorkingWeight: 45, barWeight: 45, in: .lbs).isEmpty)
    }

    // MARK: - Kilograms

    // 100 kg: 50 / 60 / 75, every one already a multiple of 2.5, so this pins
    // the percentages in kg without the rounding having any say.
    @Test func kilogramsRampOnTheSamePercentages() {
        let plan = WarmupSets.plan(forWorkingWeight: 100, in: .kg)
        #expect(plan.map(\.weight) == [50, 60, 75])
        #expect(plan.map(\.reps) == [5, 5, 3])
    }

    // THE REASON `plan` TAKES A UNIT AT ALL. 61 kg × 0.6 = 36.6, which lands on
    // 37.5 in 2.5 kg jumps — a number the 5-unit pounds increment cannot
    // produce at all. On the wrong increment it becomes 35: near enough to look
    // right, and a plate you would have to invent.
    @Test func kilogramsRoundToKilogramPlates() {
        let plan = WarmupSets.plan(forWorkingWeight: 61, in: .kg)
        #expect(plan.map(\.weight) == [30, 37.5, 45])
        #expect(plan[1].weight == 37.5, "2.5 kg increments, not 5 of anything")

        // The same numbers on the pounds increment, to show the middle step is
        // the one the unit decides.
        #expect(WarmupSets.plan(forWorkingWeight: 61, in: .lbs).map(\.weight) == [30, 35, 45])
    }

    // The metric Olympic bar is 20 kg, not 45 lb converted (20.41). Both are
    // real bars; `BarType.weight(in:)` is where that argument lives. Here it
    // only has to hold as a floor.
    @Test func theMetricBarFloorsTheKilogramRamp() {
        // 30 kg: 15 / 18 / 22.5 -> 15 / 17.5 / 22.5, all under or at the bar
        // except the last. Raised: 20, 20 (duplicate, dropped), 22.5.
        let plan = WarmupSets.plan(forWorkingWeight: 30, barWeight: 20, in: .kg)
        #expect(plan.map(\.weight) == [20, 22.5])
        #expect(plan.allSatisfy { $0.weight < 30 })
    }

    // A ramp is NOT the same set of loads in both units, and this is the test
    // that fails if somebody "simplifies" `plan` back to one increment. 100 kg
    // ramps to 50/60/75 kg; the same lift in pounds (220.46) ramps to values
    // that convert to something else entirely.
    @Test func theTwoUnitsDoNotProduceConvertedVersionsOfEachOther() {
        let metric = WarmupSets.plan(forWorkingWeight: 100, in: .kg)
        let imperial = WarmupSets.plan(
            forWorkingWeight: WeightUnits.displayed(from: 100, in: .lbs),
            in: .lbs
        )
        let imperialAsKilograms = imperial.map {
            WeightUnits.kilograms(from: $0.weight, in: .lbs)
        }
        #expect(metric.map(\.weight) != imperialAsKilograms)
    }
}
