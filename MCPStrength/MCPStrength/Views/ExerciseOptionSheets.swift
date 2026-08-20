//
//  ExerciseOptionSheets.swift
//  MCPStrength
//
//  The small editors the options menu opens: a note, a sticky note, and the
//  default rest timer.
//
//  Shared for the same reason the menu is: the template editor and the live
//  workout ask the identical question, and two copies would drift the moment
//  one gained a field.
//

import SwiftUI

// MARK: - Note editor

/// A sheet for editing a note or a sticky note.
///
/// One view for both, because the only difference is the wording. A separate
/// `StickyNoteSheet` would be the same file with two strings changed, which is
/// how `BodyPart.displayName` ended up defined twice.
struct ExerciseNoteSheet: View {
    /// A sticky note stays pinned under the exercise while logging; a plain
    /// note lives behind the menu. Only the copy differs.
    let isSticky: Bool
    let exerciseName: String
    @State private var text: String
    let onSave: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        isSticky: Bool,
        exerciseName: String,
        initialText: String?,
        onSave: @escaping (String?) -> Void
    ) {
        self.isSticky = isSticky
        self.exerciseName = exerciseName
        self._text = State(initialValue: initialText ?? "")
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.comfortable) {
                Text(exerciseName)
                    .font(Typography.secondary)
                    .foregroundStyle(Theme.textSecondary)

                TextEditor(text: $text)
                    .font(Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.compact)
                    .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.chip))
                    .frame(minHeight: 140)

                if isSticky {
                    Text("A sticky note stays visible under the exercise while you log.")
                        .font(Typography.secondary)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()
            }
            .padding(Spacing.screenMargin)
            .background(Theme.surface)
            .navigationTitle(isSticky ? "Sticky Note" : "Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        // Empty means REMOVED, not an empty string. An empty
                        // note that still counts as "has a note" would leave the
                        // menu reading "Edit Note" forever with nothing to edit.
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? nil : trimmed)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        // Follows the palette, not a hard-coded dark. A sheet inherits the
        // window's scheme, but saying it here keeps this screen right when it
        // is presented from somewhere that does not.
        .preferredColorScheme(Theme.palette.colorScheme)
    }
}

// MARK: - Rest timer editor

/// Picks a rest duration, for either of the two things rest can mean.
///
/// Deliberately a list of common values rather than a free-text field. Rest is
/// chosen from a handful of habits — 60, 90, two minutes — and a keyboard for a
/// number you pick from six options is friction mid-session, which is precisely
/// when this gets used.
struct RestTimerSheet: View {
    /// WHICH rest is being set. The two are different values on different rows
    /// and the sheet must say which one it is about: `defaultRestSeconds` is
    /// what new sets inherit, `restSeconds` is one set's own rest. The menu
    /// edits the first, tapping a divider edits the second, and telling a user
    /// "new sets will use this" while editing an existing set is simply false.
    enum Scope {
        /// Every set in the exercise — the ones already there and the ones
        /// added later.
        ///
        /// > **This used to mean NEW SETS ONLY, and the change was Drake's
        /// > call after using it.** The old split was defensible on paper —
        /// > the menu set what new sets inherit, tapping a divider set one
        /// > set's own rest — and in the gym it read as broken: you change the
        /// > exercise's rest timer, look at the sets you already have, and
        /// > nothing moved. Nobody adds an exercise, sets three sets, and then
        /// > wants the rest they just chose to apply only to a fourth.
        /// >
        /// > The per-set override survives untouched: tapping a divider still
        /// > edits that one set. This is the broad brush, that is the fine one.
        case wholeExercise(exerciseName: String)
        case oneSet

        var explanation: String {
            switch self {
            case .wholeExercise(let name):
                "Every set in \(name) will use this."
            case .oneSet:
                "Sets the rest after this set. Other sets keep theirs."
            }
        }
    }

    let scope: Scope
    let current: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Seconds. Includes 0 because "no rest timer" is a real preference, not an
    /// absence of one — a superset accessory does not want a countdown.
    private let options = [0, 30, 45, 60, 90, 120, 150, 180, 240, 300]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(options, id: \.self) { seconds in
                        Button {
                            onSelect(seconds)
                            dismiss()
                        } label: {
                            HStack {
                                Text(seconds == 0 ? "No rest timer" : formatMinutesSeconds(seconds))
                                    .font(Typography.body)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if seconds == current {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(.vertical, Spacing.comfortable)
                            .padding(.horizontal, Spacing.screenMargin)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if seconds != options.last {
                            Rectangle()
                                .fill(Theme.fieldFill)
                                .frame(height: 1)
                                .padding(.leading, Spacing.screenMargin)
                        }
                    }
                }
            }
            .background(Theme.surface)
            .navigationTitle("Rest Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top) {
                Text(scope.explanation)
                    .font(Typography.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.vertical, Spacing.compact)
                    .background(Theme.surface)
            }
        }
        // Follows the palette, not a hard-coded dark. A sheet inherits the
        // window's scheme, but saying it here keeps this screen right when it
        // is presented from somewhere that does not.
        .preferredColorScheme(Theme.palette.colorScheme)
    }
}

// MARK: - Preferences

/// Weight Unit and Bar Type, for one exercise. The eighth and last item of the
/// reference app's per-exercise menu.
///
/// ## Two rows, not four
///
/// `ExercisePreference` carries four fields; this sheet edits two. `notes` has
/// its own menu item already and `focusMetric` has no UI anywhere — putting
/// them here because the model has them would invent a screen the reference
/// does not have, which is the mistake `docs/04-status.md` records about the
/// warm-up percentages settings model that turned out not to be a requirement.
///
/// ## Save, rather than committing on tap
///
/// `RestTimerSheet` commits the moment you tap a row, because it edits ONE
/// value and tapping it is the whole interaction. This edits two, so a tap is
/// only half an answer — and more importantly, committing on tap would have to
/// resolve the preference row on the first tap, which is exactly the write
/// this screen is supposed to be careful about. Holding the choice in `@State`
/// and asking `ExercisePreferenceEditing.write` at Save means opening the
/// sheet, looking, and tapping Save creates nothing.
///
/// ## The bar weights are shown in the unit chosen ABOVE them, live
///
/// A picker listing bar types without their weights is most of the way to
/// useless — you pick "Short Bar" and still have to know what the app thinks
/// that weighs. And the unit those weights are in is the one being chosen in
/// the row above, so switching Weight Unit to Metric re-labels the bars in the
/// same breath: 45 lb becomes 20 kg, which is a DIFFERENT BAR rather than a
/// conversion (`BarType.weight(in:)` argues that at length).
///
/// > **This is the first screen in the app where the kilogram display path is
/// > visible at all.** Every weight has been stored in kilograms since the
/// > units conversion, and every screen renders pounds because nothing can
/// > change the global setting yet — so the kg path has only ever been
/// > exercised by tests (`docs/04-status.md`, item 2). Flipping this row to
/// > Metric is the first time a human can see it.
struct ExercisePreferencesSheet: View {
    let exerciseName: String
    /// What *Default* defers to, so the row can say which unit that is rather
    /// than making the user remember.
    let globalUnit: WeightUnit
    let current: ExercisePreferenceEdit
    /// Called ONLY when something actually changed. A Save that changed
    /// nothing must not reach the store — see `ExercisePreferenceEditing`.
    let onSave: (ExercisePreferenceEdit) -> Void

    @State private var chosen: ExercisePreferenceEdit
    @Environment(\.dismiss) private var dismiss

    init(
        exerciseName: String,
        globalUnit: WeightUnit,
        current: ExercisePreferenceEdit,
        onSave: @escaping (ExercisePreferenceEdit) -> Void
    ) {
        self.exerciseName = exerciseName
        self.globalUnit = globalUnit
        self.current = current
        self.onSave = onSave
        self._chosen = State(initialValue: current)
    }

    /// The unit the bar weights below are quoted in — resolved through the
    /// same function every other screen uses, with the PENDING choice as the
    /// override. Reading `chosen` rather than `current` is what makes the list
    /// re-label as soon as the unit row is tapped.
    private var barUnit: WeightUnit {
        WeightUnits.displayUnit(override: chosen.weightUnitOverride, global: globalUnit)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.spacious) {
                    Text(exerciseName)
                        .font(Typography.secondary)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, Spacing.screenMargin)

                    section("Weight Unit") {
                        // nil FIRST, and it is the default rather than an
                        // "or leave it blank" afterthought — almost nobody
                        // sets a per-exercise unit, so the value most users
                        // want is the one at the top.
                        row(
                            title: "Default",
                            detail: globalUnit.displayName,
                            isSelected: chosen.weightUnitOverride == nil
                        ) { chosen.weightUnitOverride = nil }

                        // `settingsLabel`, the same string the settings screen's
                        // Weight Unit row offers and displays. Two screens that
                        // choose the same setting and name it differently read
                        // as two different settings.
                        row(
                            title: WeightUnit.kg.settingsLabel,
                            detail: nil,
                            isSelected: chosen.weightUnitOverride == .kg
                        ) { chosen.weightUnitOverride = .kg }

                        row(
                            title: WeightUnit.lbs.settingsLabel,
                            detail: nil,
                            isSelected: chosen.weightUnitOverride == .lbs,
                            isLast: true
                        ) { chosen.weightUnitOverride = .lbs }
                    }

                    section("Bar Type") {
                        row(
                            title: "Not set",
                            detail: nil,
                            isSelected: chosen.barType == nil
                        ) { chosen.barType = nil }

                        ForEach(Array(BarType.allCases.enumerated()), id: \.element) { index, bar in
                            row(
                                title: bar.displayName,
                                detail: barWeightLabel(for: bar),
                                isSelected: chosen.barType == bar,
                                isLast: index == BarType.allCases.count - 1
                            ) { chosen.barType = bar }
                        }
                    }
                }
                .padding(.vertical, Spacing.comfortable)
            }
            .background(Theme.surface)
            .navigationTitle("Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if let write = ExercisePreferenceEditing.write(
                            current: current, chosen: chosen
                        ) {
                            onSave(write)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        // Follows the palette, not a hard-coded dark. A sheet inherits the
        // window's scheme, but saying it here keeps this screen right when it
        // is presented from somewhere that does not.
        .preferredColorScheme(Theme.palette.colorScheme)
    }

    /// A bar's empty weight, or nothing at all for the two that have no bar.
    ///
    /// `dumbbell` and `other` weigh 0 in every unit because there is no bar,
    /// and "0 lb" on those rows is the fabricated zero AGENTS.md rule 4
    /// forbids — it reads as *this bar weighs nothing* rather than *there is
    /// no bar to weigh*. Show nothing instead.
    /// `formatWeight`, NOT `weightText`, and the difference matters here more
    /// than anywhere else in the app. `weightText` converts from stored
    /// kilograms; `bar.weight(in:)` is already in `barUnit` and is a
    /// real-world constant that must never be converted — 45 lb and 20 kg are
    /// different bars, not two spellings of one. Converting here would tell a
    /// metric lifter to load a 20.41 kg bar.
    private func barWeightLabel(for bar: BarType) -> String? {
        let weight = bar.weight(in: barUnit)
        guard weight > 0 else { return nil }
        return "\(PreviousText.formatWeight(weight)) \(barUnit.abbreviation)"
    }

    @ViewBuilder
    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text(title)
                .font(Typography.cardTitle)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Spacing.screenMargin)

            VStack(spacing: 0) { content() }
                .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.card))
                .padding(.horizontal, Spacing.screenMargin)
        }
    }

    @ViewBuilder
    private func row(
        title: String,
        detail: String?,
        isSelected: Bool,
        isLast: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.compact) {
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                if let detail {
                    Text(detail)
                        .font(Typography.secondary)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.vertical, Spacing.comfortable)
            .padding(.horizontal, Spacing.screenMargin)
            // The row is a Button, so the whole strip has to be hit-testable
            // rather than just the glyphs on it — a tap in the empty middle
            // landing on nothing is the same class of bug as the .clear
            // folder background in docs/04-status.md.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if !isLast {
            Rectangle()
                .fill(Theme.surface)
                .frame(height: 1)
                .padding(.leading, Spacing.screenMargin)
        }
    }
}

#Preview("Note") {
    ExerciseNoteSheet(
        isSticky: true,
        exerciseName: "Bench Press (Barbell)",
        initialText: "Elbows tucked",
        onSave: { _ in }
    )
}

#Preview("Rest — new sets") {
    RestTimerSheet(
        scope: .wholeExercise(exerciseName: "Bench Press (Barbell)"),
        current: 90,
        onSelect: { _ in }
    )
}

#Preview("Rest — one set") {
    RestTimerSheet(scope: .oneSet, current: 120, onSelect: { _ in })
}
