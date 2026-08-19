//
//  WarmupSetsTests.swift
//  MCPStrengthTests
//
//  Covers WarmupSets.plan — the percentage ramp, plate rounding, and the
//  cases that collapse the ramp to fewer sets or to nothing. Lives in
//  Workout/ (no SwiftUI / SwiftData) so it can be tested in isolation.
//
//  THE RAMP IS MEASURED, NOT INVENTED, AND IT IS PINNED BY **TWO** OBSERVED
//  RAMPS RATHER THAN ONE. That is the whole lesson of this file: it ran on the
//  wrong percentages for three days while a single test reproduced a single
//  screenshot perfectly. 90 lb cannot tell 0.5/0.6/0.75 from the reference's
//  0.4/0.6/0.8 — both land on 45/55/70, one by arithmetic and one via the bar
//  floor. 135 lb separates them (55/80/110 versus 70/80/100) and is what the
//  reference actually produces. **Never delete either case; either one alone
//  is satisfiable by a wrong ramp.**
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

    // REFERENCE CASE ONE. Generated in the reference app, 135 lb working set:
    // 55×5, 80×5, 110×3.
    //
    //   0.40 × 135 = 54    -> 55    (rounds up)
    //   0.60 × 135 = 81    -> 80    (rounds down)
    //   0.80 × 135 = 108   -> 110   (rounds up)
    //
    // **THIS IS THE CASE THAT DISCRIMINATES.** The ramp this file used to
    // assert (0.5 / 0.6 / 0.75) produces 70 / 80 / 100 here — same middle step,
    // both ends wrong by 10 lb — and passed every test in this file, because
    // the only observed ramp it was checked against was one both formulas fit.
    @Test func aHundredAndThirtyFiveReproducesTheReferenceRamp() {
        let plan = WarmupSets.plan(forWorkingWeight: 135, in: .lbs)
        #expect(plan.map(\.weight) == [55, 80, 110])
        #expect(plan.map(\.reps) == [5, 5, 3])
        #expect(plan.map(\.setType) == [.warmup, .warmup, .warmup])
    }

    // REFERENCE CASE TWO, and it only reproduces WITH THE BAR. Generated in the
    // reference app, 90 lb working set: 45×5, 55×5, 70×3.
    //
    //   0.40 × 90 = 36    -> 35   -> raised to the 45 lb bar
    //   0.60 × 90 = 54    -> 55
    //   0.80 × 90 = 72    -> 70
    //
    // So the reference floors at the bar too, which is the fact that made the
    // old fit look right: 0.5 × 90 = 45 reaches the same number without ever
    // needing a floor. Keep this case AND the 135 one — either alone is
    // satisfiable by a formula that is wrong everywhere else.
    @Test func ninetyOnTheBarReproducesTheReferenceRamp() {
        let plan = WarmupSets.plan(forWorkingWeight: 90, barWeight: 45, in: .lbs)
        #expect(plan.map(\.weight) == [45, 55, 70])
        #expect(plan.map(\.reps) == [5, 5, 3])
    }

    // The same working weight with NO bar known. 35 is what the percentages
    // actually produce; the reference's 45 is the floor's doing, not the
    // ramp's. Pinned so the two are never conflated again.
    @Test func ninetyWithNoBarKeepsTheUnflooredFirstStep() {
        let plan = WarmupSets.plan(forWorkingWeight: 90, in: .lbs)
        #expect(plan.map(\.weight) == [35, 55, 70])
    }

    // 170 rounds DOWN in the middle, 140 rounds UP — both directions pinned,
    // neither relying on a midpoint.
    //   170: 68 -> 70 (up)   / 102 -> 100 (down) / 136 -> 135 (down)
    //   140: 56 -> 55 (down) /  84 ->  85 (up)   / 112 -> 110 (down)
    @Test func roundingGoesUpAndDown() {
        let heavy = WarmupSets.plan(forWorkingWeight: 170, in: .lbs)
        #expect(heavy[1].weight == 100, "102 must round down to 100, not up to 105")
        #expect(heavy.map(\.weight) == [70, 100, 135])

        let lighter = WarmupSets.plan(forWorkingWeight: 140, in: .lbs)
        #expect(lighter[1].weight == 85, "84 must round up to 85, not down to 80")
        #expect(lighter.map(\.weight) == [55, 85, 110])
    }

    // 137.5 × 0.60 = 82.5, the exact midpoint of 80 and 85. Half-up (away from
    // zero) is 85; half-to-even is 80. OneRepMax deliberately uses the OTHER
    // rule, so leaving this implicit would inherit whichever default the next
    // editor assumed.
    //
    // A decimal working weight because with 40 / 60 / 80 no whole number of
    // pounds lands a step on a midpoint — a small sign that the percentages
    // moved, and the reason this test had to be re-derived rather than renumbered.
    @Test func midpointRoundsToTheHeavierPlate() {
        let plan = WarmupSets.plan(forWorkingWeight: 137.5, in: .lbs)
        #expect(plan[1].weight == 85, "82.5 must become 85, not 80")
        #expect(plan.map(\.weight) == [55, 85, 110])
    }

    // 20 × 0.40 / 0.60 / 0.80 = 8 / 12 / 16 → 10 / 10 / 15. The second 10 is
    // the same plate as the first; keep the first and drop the duplicate.
    @Test func lightWeightDropsDuplicatePlates() {
        let plan = WarmupSets.plan(forWorkingWeight: 20, in: .lbs)
        #expect(plan.map(\.weight) == [10, 15])
        #expect(plan.map(\.reps) == [5, 3])
    }

    // 10 × 0.40 / 0.60 / 0.80 = 4 / 6 / 8 → 5 / 5 / 10. The duplicate 5
    // collapses, and 10 is the working weight itself — not a warm-up.
    @Test func stepsAtOrAboveTheWorkingWeightAreDropped() {
        let plan = WarmupSets.plan(forWorkingWeight: 10, in: .lbs)
        #expect(plan.map(\.weight) == [5])
        #expect(plan.map(\.reps) == [5])
        #expect(plan[0].setType == .warmup)
    }

    // 5 lb: 2 / 3 / 4 → 0 / 5 / 5. The first is not a plate at all and the
    // other two are the working weight. Nothing honest remains, which is
    // different from "no working weight" — a weight WAS supplied, the ramp just
    // has nowhere to stand.
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
        // 18 -> 20 (up), 27 -> 25 (down), 36 -> 35 (down).
        let plan = WarmupSets.plan(forWorkingWeight: 45, in: .lbs)
        #expect(plan.map(\.weight) == [20, 25, 35])
        #expect(plan.allSatisfy { $0.weight < 45 })
    }

    @Test func repsFollowTheRampInOrder() {
        let plan = WarmupSets.plan(forWorkingWeight: 225, in: .lbs)
        #expect(plan.map(\.reps) == [5, 5, 3])
        #expect(plan.map(\.weight) == [90, 135, 180])
    }

    // MARK: - Bar-weight floor

    // 65 × 0.40 / 0.60 / 0.80 = 26 / 39 / 52 → 25 / 40 / 50. On a
    // 45 lb bar the first two cannot be loaded. Raised: 25→45, 40→45
    // (duplicate, dropped by the existing strictly-increasing rule), 50
    // stays. Empty bar + 50, then work at 65.
    @Test func stepsBelowTheBarAreRaisedToTheBar() {
        let plan = WarmupSets.plan(forWorkingWeight: 65, barWeight: 45, in: .lbs)
        #expect(plan.map(\.weight) == [45, 50])
        #expect(plan.map(\.reps) == [5, 3])
        #expect(plan.allSatisfy { $0.setType == .warmup })
    }

    // A step that lands EXACTLY on the bar is kept, not swallowed. 112.5 ×
    // 0.40 = 45, equal to the bar rather than below it, so the floor must
    // leave it alone — `rounded < floor` and not `<=`. An off-by-one here
    // would silently delete the empty-bar set from every ramp that starts
    // on the bar exactly.
    @Test func aStepEqualToTheBarIsKept() {
        let plan = WarmupSets.plan(forWorkingWeight: 112.5, barWeight: 45, in: .lbs)
        #expect(plan.map(\.weight) == [45, 70, 90])
        #expect(plan.map(\.reps) == [5, 5, 3])
    }

    @Test func aNilBarWeightIsIdenticalToOmittingTheFloor() {
        let omitted = WarmupSets.plan(forWorkingWeight: 90, in: .lbs)
        let explicitNil = WarmupSets.plan(forWorkingWeight: 90, barWeight: nil, in: .lbs)
        #expect(explicitNil == omitted)
        #expect(explicitNil.map(\.weight) == [35, 55, 70])

        // 65 is the case the floor actually changes. nil must reproduce
        // today's unfloored 25 / 40 / 50, including the unloadable steps
        // — "no floor" is not "a floor of zero".
        let unfloored = WarmupSets.plan(forWorkingWeight: 65, barWeight: nil, in: .lbs)
        #expect(unfloored.map(\.weight) == [25, 40, 50])
        #expect(unfloored == WarmupSets.plan(forWorkingWeight: 65, in: .lbs))
    }

    // BarType.dumbbell.weight and .other.weight are 0. A caller that
    // forwards `exercise.preference?.barType?.weight` will pass 0, not nil.
    // That 0 must not become a floor.
    @Test func aZeroBarWeightIsNotAFloor() {
        let plan = WarmupSets.plan(forWorkingWeight: 65, barWeight: 0, in: .lbs)
        #expect(plan.map(\.weight) == [25, 40, 50])
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

    // 100 kg: 40 / 60 / 80, every one already a multiple of 2.5, so this pins
    // the percentages in kg without the rounding having any say.
    @Test func kilogramsRampOnTheSamePercentages() {
        let plan = WarmupSets.plan(forWorkingWeight: 100, in: .kg)
        #expect(plan.map(\.weight) == [40, 60, 80])
        #expect(plan.map(\.reps) == [5, 5, 3])
    }

    // THE REASON `plan` TAKES A UNIT AT ALL. 61 kg × 0.6 = 36.6, which lands on
    // 37.5 in 2.5 kg jumps — a number the 5-unit pounds increment cannot
    // produce at all. On the wrong increment it becomes 35: near enough to look
    // right, and a plate you would have to invent.
    @Test func kilogramsRoundToKilogramPlates() {
        let plan = WarmupSets.plan(forWorkingWeight: 61, in: .kg)
        #expect(plan.map(\.weight) == [25, 37.5, 50])
        #expect(plan[1].weight == 37.5, "2.5 kg increments, not 5 of anything")

        // The same numbers on the pounds increment, to show the middle step is
        // the one the unit decides.
        #expect(WarmupSets.plan(forWorkingWeight: 61, in: .lbs).map(\.weight) == [25, 35, 50])
    }

    // The metric Olympic bar is 20 kg, not 45 lb converted (20.41). Both are
    // real bars; `BarType.weight(in:)` is where that argument lives. Here it
    // only has to hold as a floor.
    @Test func theMetricBarFloorsTheKilogramRamp() {
        // 30 kg: 12 / 18 / 24 -> 12.5 / 17.5 / 25, the first two under the
        // bar. Raised: 20, 20 (duplicate, dropped), 25.
        let plan = WarmupSets.plan(forWorkingWeight: 30, barWeight: 20, in: .kg)
        #expect(plan.map(\.weight) == [20, 25])
        #expect(plan.allSatisfy { $0.weight < 30 })
    }

    // A ramp is NOT the same set of loads in both units, and this is the test
    // that fails if somebody "simplifies" `plan` back to one increment. 100 kg
    // ramps to 40/60/80 kg; the same lift in pounds (220.46) ramps to values
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
