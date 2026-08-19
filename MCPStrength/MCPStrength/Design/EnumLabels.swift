//
//  EnumLabels.swift
//  MCPStrength
//

import Foundation

// MARK: - Display names for the filter enums
//
// The model enums carry camelCase raw values (e.g. `fullBody`, `machineOther`) that read poorly
// as UI labels. These extensions live in the view layer — they are presentation concerns, not
// model concerns — so the Models/ file stays untouched. Hand-written switches (not a generic
// camelCase splitter) keep this boring and explicit, matching the SetTypeBadge glyph style.
// Internal (not private) so every view can share one mapping instead of duplicating labels.
extension BodyPart {
    var displayName: String {
        switch self {
        case .arms:     "Arms"
        case .back:     "Back"
        case .cardio:   "Cardio"
        case .chest:    "Chest"
        case .core:     "Core"
        case .fullBody: "Full Body"
        case .legs:     "Legs"
        case .olympic:  "Olympic"
        case .other:    "Other"
        case .shoulders:"Shoulders"
        }
    }
}

extension Exercise {
    /// Primary body part, then any secondaries, comma-joined — "Back, Legs"
    /// for Deadlift. Presentation only: `bodyPart` stays the single value
    /// every model-layer comparison and filter reads.
    var bodyPartsDisplayName: String {
        ([bodyPart] + secondaryBodyParts).map(\.displayName).joined(separator: ", ")
    }
}

extension ExerciseCategory {
    var displayName: String {
        switch self {
        case .barbell:             "Barbell"
        case .dumbbell:            "Dumbbell"
        case .machineOther:        "Machine"
        case .weightedBodyweight:  "Weighted Bodyweight"
        case .assistedBodyweight:  "Assisted Bodyweight"
        case .repsOnly:            "Reps Only"
        case .cardio:              "Cardio"
        case .duration:            "Duration"
        }
    }

    /// Label for the Postgres `hammerStrength` value. Not a switch case:
    /// the Swift enum cannot grow that case until `OneRepMax.supportsEstimate`
    /// is updated (out of scope for this change).
    static var hammerStrengthDisplayName: String { "Hammer Strength" }
}

extension BarType {
    /// `standardBar` and `trapBar` stay as those raw values — they are
    /// `public.bar_type` on a live column, and Postgres cannot drop an enum
    /// value. The reference app calls them Short Bar and Hex Bar; that is
    /// what these labels are for, not a rename of the case.
    var displayName: String {
        switch self {
        case .olympicBar:  "Olympic Bar"
        case .standardBar: "Short Bar"
        case .ezBar:       "EZ Bar"
        case .trapBar:     "Hex Bar"
        case .dumbbell:    "Dumbbell"
        case .other:       "Other"
        }
    }
}

extension WorkoutCalorieRate {
    /// The bare name of the rate, for the list of choices.
    var displayName: String {
        switch self {
        case .none:     "None"
        case .low:      "Low"
        case .medium:   "Medium"
        case .high:     "High"
        case .veryHigh: "Very High"
        }
    }

    /// The name WITH the number it stands for — the settings row's value, and
    /// the reference app's own wording (`Medium (200 kcal per hour)`).
    ///
    /// **The number is on the label on purpose.** "Medium" alone is the app
    /// asserting an amount of energy without ever saying what it is, which is
    /// the fabricated-figure problem rule 4 is about wearing a different hat.
    /// Naming the rate at the point of choosing it is what makes a user-picked
    /// estimate honest rather than invented.
    ///
    /// `none` carries no number, because `None (0 kcal per hour)` reads as a
    /// measurement of zero rather than as "do not write energy at all" — the
    /// fabricated zero, exactly.
    var settingsLabel: String {
        switch self {
        case .none: displayName
        default:    "\(displayName) (\(Int(kilocaloriesPerHour)) kcal per hour)"
        }
    }
}

extension WeightUnit {
    /// How a unit is named where a unit is being CHOSEN — the settings screen's
    /// Weight Unit row and the per-exercise Preferences sheet.
    ///
    /// **One string for both screens, and the wording is the reference app's,
    /// not ours.** The reference offers exactly `Default`, `Metric (kg)` and
    /// `US/Imperial (lbs)` (docs/06-sync.md § "Per-exercise preferences"), and
    /// its settings row renders the chosen value with the same words it offered.
    /// Two screens that choose the same setting and name it differently read as
    /// two different settings — which is the whole reason this is here rather
    /// than spelled out at each call site.
    ///
    /// Deliberately NOT `abbreviation` or `columnHeader`. Those trail a number
    /// (`135 lb`) or head a column (`lbs`); this one names a system to a person
    /// who is picking between two of them, and "lb" alone does not say
    /// *US/Imperial*.
    var settingsLabel: String {
        switch self {
        case .lbs: "US/Imperial (lbs)"
        case .kg:  "Metric (kg)"
        }
    }

    /// The bare name of the unit, for prose. Used where the label sits next to
    /// something that already supplies the context — the Preferences sheet's
    /// *Default* row, which says which unit Default currently follows.
    var displayName: String {
        switch self {
        case .lbs: "Pounds"
        case .kg:  "Kilograms"
        }
    }

    /// The suffix on a rendered weight: `135 lb × 5`, `61.2 kg × 5`.
    ///
    /// Singular "lb" rather than "lbs" because it follows a number, which is
    /// what the reference app does and what every call site here already
    /// hard-coded before the unit became a variable.
    var abbreviation: String {
        switch self {
        case .lbs: "lb"
        case .kg:  "kg"
        }
    }

    /// The weight column's header on a set row.
    ///
    /// Deliberately NOT `abbreviation`: the reference labels that column "lbs",
    /// plural, because it heads a column rather than trailing a number. The two
    /// spellings are a real difference in the design, not an inconsistency to
    /// tidy away.
    var columnHeader: String {
        switch self {
        case .lbs: "lbs"
        case .kg:  "kg"
        }
    }
}
