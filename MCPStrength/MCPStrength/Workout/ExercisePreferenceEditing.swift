//
//  ExercisePreferenceEditing.swift
//  MCPStrength
//
//  What a trip through the Preferences sheet should actually WRITE.
//
//  ## Why this is a rule and not three lines in the sheet
//
//  `exercise_preferences` stays SPARSE BY CONSTRUCTION — a row exists only
//  where the user actually set something (docs/06-sync.md). The sheet is the
//  only thing in the app that can create one, so the sheet is the only place
//  that rule can be broken, and "open Preferences, look, tap Save" is a
//  completely ordinary thing to do. Saving that would insert a row of pure
//  defaults, mark it dirty, and — once the conformance lands — push it.
//
//  That is the shape of the 43 fabricated discard entries in `00faec1`: a
//  value meaning "never touched" being read as "the user did something". A
//  preference table full of rows nobody set is the same lie one table over,
//  and it is far harder to notice, because a row of defaults renders
//  identically to no row at all.
//
//  So the decision is a pure function with tests, and the view calls it.
//  Same division as `WorkoutFinishing.discardSummary` and `TemplateSaveDiff`:
//  compute what is about to happen, hand it to a caller that performs it.
//

import Foundation

/// The two fields the Preferences sheet edits.
///
/// `focusMetric` and `notes` also live on `ExercisePreference` but are NOT
/// edited here — the reference app's sheet is two rows, and this type is the
/// shape of that sheet rather than the shape of the model. Widening it later
/// is a deliberate change to both.
///
/// `nil` in either field is a real, chosen value, not a missing one:
/// `weightUnitOverride == nil` IS the *Default* option in the three-way Weight
/// Unit row, and `barType == nil` is "not set", which the warm-up floor reads
/// as no floor (`WarmupSets.plan`).
struct ExercisePreferenceEdit: Equatable, Sendable {
    var weightUnitOverride: WeightUnit?
    var barType: BarType?

    /// What an exercise with no preference row looks like. Both absences, and
    /// the reason this is named rather than written as `.init()` at call
    /// sites: "no row" and "a row where the user chose Default and no bar" are
    /// indistinguishable ON PURPOSE, which is what makes it safe never to
    /// create the row.
    static let unset = ExercisePreferenceEdit(weightUnitOverride: nil, barType: nil)
}

enum ExercisePreferenceEditing {

    /// What to write, or `nil` for "write nothing at all".
    ///
    /// `nil` means: do not resolve a row, do not insert one, do not mark
    /// anything edited. Not "write these unchanged values" — resolving the row
    /// is itself the side effect this guards, because `current(for:in:)`
    /// CREATES on a miss.
    ///
    /// The rule is just inequality, and it is stated once here rather than
    /// inferred at the call site, because the interesting case is the one that
    /// looks like a no-op and is not: an exercise with an existing row whose
    /// values are cleared back to Default/not-set. `chosen == .unset` is not
    /// the test — `chosen == current` is. Clearing a real preference is an
    /// edit, and it has to travel like any other.
    static func write(
        current: ExercisePreferenceEdit,
        chosen: ExercisePreferenceEdit
    ) -> ExercisePreferenceEdit? {
        chosen == current ? nil : chosen
    }
}
