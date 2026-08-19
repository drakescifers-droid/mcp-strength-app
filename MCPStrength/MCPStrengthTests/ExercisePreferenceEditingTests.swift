//
//  ExercisePreferenceEditingTests.swift
//  MCPStrengthTests
//
//  One rule, and every test here is about the case that must write NOTHING.
//
//  The Preferences sheet is the only thing in the app that can create a
//  preference row, so it is the only place the sparse-table guarantee can be
//  broken — and the way to break it is completely ordinary: open the sheet,
//  read it, tap Save. `ExercisePreference.current(for:in:)` creates on a miss,
//  so a Save that resolved the row unconditionally would insert a row of pure
//  defaults, mark it dirty, and eventually push it.
//
//  That failure is invisible by inspection: a preference row holding nothing
//  but defaults renders identically to no preference row at all. It shows up
//  much later, as a table of rows nobody set — the same shape as the 43
//  fabricated discard entries in `00faec1`.
//

import Testing
@testable import MCPStrength

struct ExercisePreferenceEditingTests {

    // MARK: - Writes nothing

    // The load-bearing one. Opening Preferences on an exercise that has never
    // had any, changing nothing, and tapping Save must not create a row.
    @Test func savingWithoutChangingAnythingOnAFreshExerciseWritesNothing() {
        #expect(
            ExercisePreferenceEditing.write(
                current: .unset,
                chosen: .unset
            ) == nil
        )
    }

    // Same, for an exercise that already HAS a preference. Save with no edit
    // must not restamp `updatedAt` — a row that dirties itself every time
    // somebody looks at it wins conflicts it has no business winning, and adds
    // a push per glance.
    @Test func savingWithoutChangingAnythingOnAnExistingRowWritesNothing() {
        let existing = ExercisePreferenceEdit(weightUnitOverride: .kg, barType: .olympicBar)
        #expect(ExercisePreferenceEditing.write(current: existing, chosen: existing) == nil)
    }

    // MARK: - Writes

    @Test func settingAUnitOnAFreshExerciseWrites() {
        let chosen = ExercisePreferenceEdit(weightUnitOverride: .kg, barType: nil)
        #expect(ExercisePreferenceEditing.write(current: .unset, chosen: chosen) == chosen)
    }

    @Test func settingABarOnAFreshExerciseWrites() {
        let chosen = ExercisePreferenceEdit(weightUnitOverride: nil, barType: .trapBar)
        #expect(ExercisePreferenceEditing.write(current: .unset, chosen: chosen) == chosen)
    }

    @Test func changingOneFieldAndLeavingTheOtherWrites() {
        let current = ExercisePreferenceEdit(weightUnitOverride: .kg, barType: .olympicBar)
        let chosen = ExercisePreferenceEdit(weightUnitOverride: .kg, barType: .ezBar)
        #expect(ExercisePreferenceEditing.write(current: current, chosen: chosen) == chosen)
    }

    // THE CASE THAT LOOKS LIKE A NO-OP AND IS NOT. Clearing a real preference
    // back to Default / not-set is an edit and must travel like any other. A
    // rule written as "write only when `chosen != .unset`" passes every test
    // above and silently drops this one — the user turns a per-exercise
    // kilogram override off, the row keeps saying kg, and on the next device
    // it still says kg.
    @Test func clearingAnExistingPreferenceBackToUnsetWrites() {
        let current = ExercisePreferenceEdit(weightUnitOverride: .kg, barType: .olympicBar)
        #expect(
            ExercisePreferenceEditing.write(current: current, chosen: .unset)
                == ExercisePreferenceEdit.unset
        )
    }

    // Clearing only one half is still a change to that half.
    @Test func clearingOnlyTheUnitWrites() {
        let current = ExercisePreferenceEdit(weightUnitOverride: .lbs, barType: .trapBar)
        let chosen = ExercisePreferenceEdit(weightUnitOverride: nil, barType: .trapBar)
        #expect(ExercisePreferenceEditing.write(current: current, chosen: chosen) == chosen)
    }

    // MARK: - The two absences are the same value

    // `.unset` must BE both nils, not merely behave like them. If these ever
    // diverge, "no row" and "a row where nothing is set" stop being
    // interchangeable and the sheet starts writing rows to say nothing.
    @Test func unsetIsBothAbsences() {
        #expect(ExercisePreferenceEdit.unset.weightUnitOverride == nil)
        #expect(ExercisePreferenceEdit.unset.barType == nil)
        #expect(
            ExercisePreferenceEdit(weightUnitOverride: nil, barType: nil)
                == ExercisePreferenceEdit.unset
        )
    }
}
