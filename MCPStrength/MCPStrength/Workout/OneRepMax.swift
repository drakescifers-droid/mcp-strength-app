//
//  OneRepMax.swift
//  MCPStrength
//
//  Estimating a one-rep max from a set that was actually performed.
//
//  ## The formula, and how it was chosen
//
//      1RM = min( Brzycki, Epley )
//      Brzycki = weight × 36 / (37 − reps)
//      Epley   = weight × (1 + reps / 30)
//
//  Reverse-engineered from the reference app, and it took TWO passes — the
//  first one was wrong in an instructive way.
//
//  The first sample was thirteen (weight, reps, shown) triples off one
//  screenshot. Brzycki matched all thirteen and Epley only four, so Brzycki
//  looked settled. It was not: every sample in that batch was 10 reps or
//  fewer, and THE TWO FORMULAS CROSS OVER AT EXACTLY 10 REPS. Below that
//  Brzycki is the smaller; above it Epley is. A sample that stops at 10 cannot
//  tell "Brzycki" from "the smaller of the two".
//
//  A second screenshot with 11-15 rep sets settled it: across 43 samples,
//  min() matched 41 and Brzycki alone matched 33, missing EVERY high-rep case.
//
//  The last two were dismissed as float noise and were not. Both were exact .5
//  values — 102.5 and 202.5 — and the reference rounded BOTH DOWN, to 102 and
//  202. Both targets are even. That is round-half-to-EVEN (banker's rounding),
//  the IEEE default, and switching to it takes the match to 43/43. "Close
//  enough, must be noise" was the wrong call twice in one afternoon: the first
//  time it hid a whole second formula, the second time a rounding rule.
//
//  The lesson is about the evidence, not the arithmetic: a formula fitted on a
//  range that never exercises the thing that distinguishes the candidates will
//  fit perfectly and still be wrong.
//
//  ## Where it deliberately returns nothing
//
//  An estimate is a claim about what the user could lift. A wrong one is worse
//  than a blank, because a blank is obviously an absence and a wrong number
//  reads as information — the same reasoning as never displaying a fabricated
//  zero (docs/04-status.md).
//
//  So this returns nil rather than a number when:
//
//    * **Nothing, on rep count alone.** An earlier version capped at 12 reps,
//      which would have shown a blank everywhere the reference app shows a
//      number (its screenshots go to 15). Taking the MINIMUM keeps the estimate
//      conservative at high reps by construction, which is what the cap was
//      really trying to buy. Brzycki's own blow-up is still guarded: it is
//      undefined at 37 reps and NEGATIVE past that, so above 36 only Epley is
//      considered — otherwise min() would faithfully return the negative one.
//    * **The category has no meaningful total load.** Weighted bodyweight
//      stores ADDED weight, so "+230 lb × 9" is not 230 lb of load and an
//      estimate from it is meaningless without the user's bodyweight, which
//      this app does not use for it. Assisted bodyweight stores NEGATIVE
//      assistance. Reps-only, cardio and duration have no weight at all. The
//      reference app blanks these too.
//    * **Weight or reps are missing**, or the weight is not positive.
//

import Foundation

enum OneRepMax {

    /// The rep count at which Brzycki's denominator reaches zero. At or above
    /// this it is undefined, then negative, so it is dropped from the
    /// comparison entirely.
    private static let brzyckiBreaksDownAt = 37

    /// Whether an exercise of this category has a total load a 1RM can be
    /// estimated from.
    static func supportsEstimate(_ category: ExerciseCategory) -> Bool {
        switch category {
        case .barbell, .dumbbell, .machineOther:
            true
        case .weightedBodyweight, .assistedBodyweight, .repsOnly, .cardio, .duration:
            false
        }
    }

    /// Estimated one-rep max in the same unit as `weight`, or nil when no
    /// honest estimate exists.
    ///
    /// Rounded to the nearest whole unit — the input is a rough model, and
    /// decimals on it would imply a precision that is not there.
    ///
    /// `.toNearestOrEven`, NOT the default `.rounded()`. They differ only on
    /// exact .5 values, which is why this looks like a detail and is not: the
    /// reference app rounds 102.5 to 102 and 202.5 to 202, and matching it went
    /// from 41/43 samples to 43/43 on this one change.
    static func estimate(weight: Double?, reps: Int?) -> Double? {
        guard let weight, let reps, weight > 0, reps >= 1 else { return nil }

        let epley = weight * (1.0 + Double(reps) / 30.0)
        guard reps < brzyckiBreaksDownAt else { return epley.rounded(.toNearestOrEven) }

        let brzycki = weight * 36.0 / Double(brzyckiBreaksDownAt - reps)
        return min(brzycki, epley).rounded(.toNearestOrEven)
    }

    /// Convenience for a performed set, applying the category rule as well.
    static func estimate(for set: WorkoutSet, category: ExerciseCategory?) -> Double? {
        guard let category, supportsEstimate(category) else { return nil }
        return estimate(weight: set.weight, reps: set.reps)
    }
}
