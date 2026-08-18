//
//  WarmupSets.swift
//  MCPStrength
//
//  The warm-up ramp that leads up to a working weight.
//
//  ## Why this is a plan, not a write
//
//  The live workout screen and the template editor both need these sets, and
//  both already know how to insert a WorkoutSet — order, rest, markEdited,
//  the relationship. This file computes WHAT to insert (weight, reps, type)
//  and stops there. WorkoutFinishing.discardSummary is the same split: the
//  rule describes the next action, the caller performs it. Building a @Model
//  here would pull SwiftData into a rule that is otherwise a few multiplies,
//  and it would hide the markEdited call the insert still owes.
//
//  ## Why the ramp is hard-coded
//
//  Drake asked for defaults rather than a settings screen. In the app this
//  one is modelled on, you generate the sets and then edit the SETS if you
//  want something different. A config struct the caller must supply, or a
//  UserDefaults read, would pretend that choice is still open. The two
//  knobs (percentages, reps) live in `Ramp` so a later change is a
//  five-second find, not a hunt through a loop.
//
//  ## Why this works in the DISPLAY unit, not in storage
//
//  Every other weight in the app is stored and reasoned about in kilograms.
//  This one is not, and the exception is the whole reason `plan` takes a unit.
//
//  A warm-up is a load the app INVENTS, so it has to land on plates that exist
//  in the user's gym — 5 lb jumps in a pounds gym, 2.5 kg in a metric one, and
//  neither is a conversion of the other (`WeightUnits.plateIncrement`). Ramp in
//  kilograms and convert at the end and a pounds lifter is told to load
//  49.6 lb: arithmetically faithful to the ramp and impossible to put on a bar.
//  So the whole calculation happens in the unit the user reads, and the CALLER
//  converts each step back to kilograms as it writes it.
//
//  The bar floor is the same argument one level down: `BarType.weight(in:)`
//  already returns a real bar per unit rather than one number converted, and
//  it is passed in already in that unit.
//
//  ## What this refuses to emit
//
//  A warm-up is a plate load strictly below the work. After rounding:
//
//    * No working weight, or a non-positive one, produces nothing. Three
//      0 lb warm-ups would read as "warm up with nothing" — a fabricated
//      zero (docs/04-status.md). A bodyweight or reps-only set, or a
//      working set the user has not typed into yet, is absence, not data.
//    * A step that rounds to zero is the same fabricated zero and is dropped.
//    * A step at or above the working weight is not a warm-up. At light
//      loads the 80% step can land on the work itself after rounding.
//    * Two steps that round to the same plate are the same set. The later
//      one is dropped so the ramp stays strictly increasing. Identical
//      warm-ups are silly; a heavier-than-work warm-up is wrong.
//    * A step below the bar cannot be loaded. It is raised to the bar
//      weight, not dropped. Dropping would throw away the empty-bar set —
//      the first honest warm-up at light working weights (65 lb on a 45 lb
//      bar would keep only 50). Raising two steps to the same bar
//      collapses via the duplicate rule above. A bar at or above the work
//      still produces nothing: the raised value fails
//      `rounded < workingWeight`, same as a step that landed on the work.
//      `nil` is no floor. A non-positive bar is treated as nil, because
//      `BarType.dumbbell` / `.other` carry weight 0 and that 0 must never
//      become a floor by accident.
//
//  Set type is `.warmup` on every step. SetNumbering only numbers `.normal`
//  sets; a generated warm-up typed `.normal` would steal 1, 2, 3 from the
//  working sets that follow.
//

import Foundation

enum WarmupSets {

    /// Hard-coded ramp. There is no settings screen on purpose: generate
    /// these, then edit the SETS if you want something different. One named
    /// place so changing a percentage, a rep count, or the plate increment
    /// is a five-second find rather than a hunt through a loop.
    enum Ramp {
        /// Fractions of the working weight: 5 @ 0.5, 5 @ 0.6, 3 @ 0.75.
        ///
        /// **These are measured, not chosen.** They reproduce the reference
        /// app's auto-generated ramp exactly, from a screenshot of a 90 lb
        /// working set: 45×5, 55×5, 70×3.
        ///
        ///     0.50 × 90 = 45      -> 45
        ///     0.60 × 90 = 54      -> 55
        ///     0.75 × 90 = 67.5    -> 70   (the midpoint rule below matters here)
        ///
        /// An earlier guess of 0.4 / 0.6 / 0.8 at 10 / 5 / 3 was wrong on two
        /// percentages and two rep counts. It came from a screenshot of a ramp
        /// Drake had ALREADY EDITED and which persisted into the next session —
        /// so it showed his adjustments, not the generator. Worth remembering
        /// when reading any screenshot of this app: an edited warm-up looks
        /// exactly like a generated one.
        static let percentages: [Double] = [0.5, 0.6, 0.75]
        static let reps: [Int] = [5, 5, 3]
    }

    /// One generated warm-up. Weight is already a plate load.
    struct Step: Equatable, Sendable {
        var weight: Double
        var reps: Int
        var setType: SetType
    }

    /// Sets to insert in front of the working sets, lightest first.
    ///
    /// Empty means the caller should do nothing — there is no honest ramp
    /// for this working weight. Never a list of zeros.
    ///
    /// `barWeight` is a floor, not a default. `nil` means no floor: a
    /// machine, a cable, a dumbbell, and an exercise with no bar preference
    /// all pass nil. A non-positive value is treated the same as nil —
    /// `BarType.dumbbell.weight` is 0, and reading that must not become a
    /// floor of zero arrived at by accident.
    ///
    /// **`workingWeight`, `barWeight` and every returned step are all in
    /// `unit`, not in stored kilograms.** See the file comment for why the ramp
    /// is the one calculation in the app that leaves canonical storage: the
    /// plate increment is a fact about a gym, not a quantity to convert.
    static func plan(
        forWorkingWeight workingWeight: Double?,
        barWeight: Double? = nil,
        in unit: WeightUnit
    ) -> [Step] {
        guard let workingWeight, workingWeight > 0 else { return [] }

        // Only a positive bar is a floor. `barWeight ?? 0` would make
        // "no bar" and "floor of zero" the same value, and a caller that
        // forwarded `exercise.barType?.weight` would then floor every
        // dumbbell / other exercise without meaning to.
        let floor: Double? = {
            guard let barWeight, barWeight > 0 else { return nil }
            return barWeight
        }()

        var steps: [Step] = []
        var lastWeight: Double = 0

        for (percent, reps) in zip(Ramp.percentages, Ramp.reps) {
            let unrounded = workingWeight * percent
            var rounded = roundedToPlate(unrounded, in: unit)
            if let floor, rounded < floor {
                rounded = floor
            }
            // Strictly increasing, strictly below the work, and a real plate.
            // `lastWeight` starts at 0, so the first comparison also drops
            // a step that rounded to 0 lb. A raised-to-bar value that is
            // not below the work dies on the second comparison, which is
            // how a bar at or above the work collapses the whole ramp.
            guard rounded > lastWeight, rounded < workingWeight else { continue }
            steps.append(Step(weight: rounded, reps: reps, setType: .warmup))
            lastWeight = rounded
        }
        return steps
    }

    /// Nearest loadable plate in `unit`, ties to the heavier plate.
    ///
    /// The increment comes from `WeightUnits.plateIncrement` — 5 lb or 2.5 kg,
    /// two stocking conventions rather than two spellings of one number. It
    /// used to be a constant on `Ramp` because there was only one unit.
    ///
    /// `.toNearestOrAwayFromZero` is named on purpose. Swift's default
    /// `rounded()` happens to be the same rule, and `.toNearestOrEven`
    /// (what OneRepMax uses, to match the reference 1RM display) would
    /// send 62.5 to 60. A warm-up on the fence loads the heavier plate:
    /// 2.5 lb more still prepares you, and "nearest 5 lb" with a gym
    /// bar in mind means take the extra plate, not banker's rounding.
    private static func roundedToPlate(_ weight: Double, in unit: WeightUnit) -> Double {
        WeightUnits.round(weight, toNearest: WeightUnits.plateIncrement(for: unit))
    }
}
