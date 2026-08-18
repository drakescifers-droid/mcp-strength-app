//
//  WeightUnits.swift
//  MCPStrength
//
//  Converting between stored kilograms and the unit the user reads.
//
//  Storage is canonical KILOGRAMS (docs/01-data-model.md § Units decision).
//  A stored `WorkoutSet.weight` is therefore not a number anybody typed, and
//  every read and write of one has to pass through here.
//
//  Pure arithmetic, no SwiftData and no views, for the same reason
//  `WorkoutHistory` and `WarmupSets` are: this is the easiest thing in the app
//  to get silently wrong, and a wrong answer here is not a crash, it is a
//  training log that quietly disagrees with itself.
//
//  ## Two kinds of rounding, and conflating them is the trap
//
//  **Display precision** exists so a number survives the round trip. A pounds
//  lifter types 135, which is stored as 61.23496995 kg, and converting back
//  lands on 135.00000000000003. That must read as `135`, so display rounds — to
//  `displayPrecision`, which is deliberately FINE (0.01). It is not a plate
//  size and must never be one: rounding display to the nearest 2.5 lb would
//  turn a typed 138 into 137.5, silently editing what the user entered.
//
//  **Plate increments** are the opposite job: they exist so a load the APP
//  invents is loadable. The warm-up ramp generating 67.5 lb should propose 70,
//  because a gym has 5 lb jumps. This applies only to generated values, never
//  to typed ones.
//
//  `plateIncrement` is a per-unit constant for the same reason `BarType.weight`
//  is: 5 lb and 2.5 kg are what the two kinds of gym actually stock, and
//  2.5 kg is 5.51 lb, so neither is a conversion of the other. Converting one
//  into the other produces increments that exist in no gym anywhere.
//

import Foundation

enum WeightUnits {

    /// One pound in kilograms, exactly.
    ///
    /// The international avoirdupois pound has been defined as exactly
    /// 0.45359237 kg since 1959, so this is a definition rather than a
    /// measurement and there is no more precision to be had.
    static let kilogramsPerPound: Double = 0.45359237

    /// How finely a displayed weight is rounded, in the display unit.
    ///
    /// 0.01 — fine enough to preserve anything a human types (2.5 lb jumps,
    /// 1.25 kg jumps, a 183.4 lb bodyweight) and coarse enough to absorb the
    /// float error a conversion round trip leaves behind. See the file comment
    /// for why this is not a plate size.
    static let displayPrecision: Double = 0.01

    // MARK: - Conversion

    /// Stored kilograms from a value the user typed in `unit`.
    static func kilograms(from displayed: Double, in unit: WeightUnit) -> Double {
        switch unit {
        case .kg:  displayed
        case .lbs: displayed * kilogramsPerPound
        }
    }

    /// The value to show in `unit`, from stored kilograms.
    ///
    /// Rounded to `displayPrecision`, because the caller wants something to
    /// show a person, not the raw quotient. An unrounded value reaches the
    /// screen as `135.00000000000003`.
    static func displayed(from kilograms: Double, in unit: WeightUnit) -> Double {
        let raw: Double = switch unit {
        case .kg:  kilograms
        case .lbs: kilograms / kilogramsPerPound
        }
        return round(raw, toNearest: displayPrecision)
    }

    // MARK: - Plate increments, for loads the app invents

    /// The smallest jump a gym in this unit can actually load.
    ///
    /// 5 lb is a pair of 2.5 lb plates; 2.5 kg is a pair of 1.25 kg plates.
    /// These are stocking conventions, not conversions of one another — see the
    /// file comment, and `BarType.weight(in:)` for the same argument about bars.
    ///
    /// Only for values the APP generates. Never round a typed weight to this.
    static func plateIncrement(for unit: WeightUnit) -> Double {
        switch unit {
        case .lbs: 5
        case .kg:  2.5
        }
    }

    /// Nearest `increment`, ties to the heavier plate.
    ///
    /// `.toNearestOrAwayFromZero` is named on purpose, exactly as it is in
    /// `WarmupSets`: `.toNearestOrEven` would send 62.5 down to 60, and a load
    /// on the fence should take the extra plate rather than apply banker's
    /// rounding to a barbell.
    static func round(_ value: Double, toNearest increment: Double) -> Double {
        guard increment > 0 else { return value }
        return (value / increment).rounded(.toNearestOrAwayFromZero) * increment
    }
}
