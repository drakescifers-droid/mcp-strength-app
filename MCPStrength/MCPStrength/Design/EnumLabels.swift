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

extension WeightUnit {
    /// The full name, for a picker row. Not used yet — the settings screen that
    /// needs it is the next piece of work after canonical units.
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
