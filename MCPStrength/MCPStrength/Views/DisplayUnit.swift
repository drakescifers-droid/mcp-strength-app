//
//  DisplayUnit.swift
//  MCPStrength
//
//  How a screen finds out which unit to render a weight in.
//
//  Storage is canonical kilograms (docs/01-data-model.md § Units decision), so
//  a screen can no longer read `set.weight` and print it. It needs a second
//  fact — the user's unit — and that fact lives in ONE `AppSettings` row that
//  is nowhere near the six screens that need it.
//
//  ## Why the environment, and not a @Query per screen
//
//  A `@Query<AppSettings>` on every screen that shows a weight would work and
//  is the obvious thing. It is rejected because it makes the unit a fact each
//  screen looks up for itself, and the failure mode is a screen that forgets:
//  it does not crash, it does not fail a test, it silently renders kilograms
//  labelled `lb`. One publisher at the root and `@Environment` everywhere else
//  means a screen that forgets gets the DEFAULT rather than a wrong answer, and
//  the default is the same value a fresh install carries.
//
//  It also keeps `SetRow` — shared by the workout screen and the template
//  editor — free of a SwiftData query, which is the whole reason that file has
//  no `@Query` in it today.
//
//  ## Why this is only the GLOBAL unit
//
//  A weight is rendered in `WeightUnits.displayUnit(override:global:)`, and
//  this is only the `global` half. The override is per-exercise and belongs to
//  whatever exercise the row is showing, so it cannot come from the
//  environment — the same environment value is in scope for every exercise on
//  the screen. Call sites pass `exercise.weightUnitOverride` alongside; that
//  argument becomes `preference.weightUnit` when the four fields move off
//  `Exercise` (docs/06-sync.md).
//

import SwiftUI

private struct WeightUnitKey: EnvironmentKey {
    /// Pounds, matching `AppSettings.weightUnit`'s own default.
    ///
    /// The two defaults have to agree. A screen rendered outside the provider —
    /// an Xcode preview, a test host, the moment before the settings row is
    /// read — otherwise disagrees with the app about what the numbers mean.
    static let defaultValue: WeightUnit = .lbs
}

extension EnvironmentValues {

    /// The user's global weight unit, published once by `ContentView`.
    ///
    /// Display only. Nothing stored anywhere is in this unit.
    var weightUnit: WeightUnit {
        get { self[WeightUnitKey.self] }
        set { self[WeightUnitKey.self] = newValue }
    }
}
