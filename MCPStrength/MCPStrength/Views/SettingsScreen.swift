//
//  SettingsScreen.swift
//  MCPStrength
//
//  The settings sheet, reached from the gear on the Profile tab.
//
//  ## Why this screen exists, and why it is one row
//
//  Storage has been canonical KILOGRAMS since the units conversion, which means
//  a stored number means nothing on its own — 61.23 is 135 lb to one lifter and
//  61.2 kg to another. `AppSettings.weightUnit` holds the answer, every screen
//  resolves through `WeightUnits.displayUnit(override:global:)`, and **until
//  this screen existed nothing could change it.** The kilogram half of the
//  conversion was therefore exercised by tests and by one per-exercise
//  override, and by nothing else. This is what makes it reachable.
//
//  ## Why the other three unit rows are ABSENT rather than present
//
//  The reference app's UNITS AND LOCALIZATION section has six rows: Language,
//  Measurement Weight Unit, Weight Unit, Distance Unit, Size Unit, Start Week
//  On. `AppSettings` carries a field for every one of them. Only `weightUnit`
//  has a READER.
//
//  Shipping the other rows would mean controls that change a stored value no
//  screen consults — you tap Metric, nothing anywhere looks different, and the
//  setting has silently done nothing. That is not a hypothetical failure mode
//  in this project: it is the rest-timer bug from the 2026-08-18 gym session,
//  where a menu wrote `defaultRestSeconds` and the screen read a hardcoded 90.
//  Drake reported it as the control doing nothing, because that is exactly what
//  it was.
//
//  So the same call as Archive, Share and (until it was built) Preferences: a
//  shorter screen that is honest beats a complete-looking one that lies. Each
//  row arrives with its reader.
//
//    * **Measurement Weight Unit** and **Size Unit** need the measurement
//      screens first, and those carry a real undecided question — measurements
//      are NOT stored canonically the way weights are (`MeasurementEntry.unit`
//      is a string on each row), so changing the setting either converts the
//      history or leaves a mixed list, and nobody has decided which.
//    * **Distance Unit** has nothing to affect at all: there is no cardio
//      logging screen.
//    * **Language** is `String?` with its case list deliberately undecided, and
//      the app is not localised (`Models/Settings.swift`).
//    * **Start Week On** is settled and has a reader (the profile chart), but it
//      is not a unit and this screen is scoped to units.
//
//  ## Every change commits immediately
//
//  No Save button, and the dismiss control is an X rather than "Cancel". Both
//  follow from the same fact: picking a unit writes it, so there is nothing
//  pending to confirm and nothing to revert. "Cancel" would promise a rollback
//  that does not happen. `RestTimerSheet` commits on tap for the same reason;
//  `ExercisePreferencesSheet` has a Save because it edits two values at once
//  and must not create a row for a trip that changed nothing.
//

import SwiftUI
import SwiftData

struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// The settings row itself, so this screen re-renders when the value
    /// changes. Reading `@Environment(\.weightUnit)` would work for display,
    /// but this screen also WRITES, and it needs the object to write to.
    ///
    /// Same resolution rule as `AppSettings.current(in:)` — oldest live row
    /// wins, deterministically — expressed as a query so the view updates.
    @Query(
        filter: #Predicate<AppSettings> { $0.deletedAt == nil },
        sort: \AppSettings.createdAt,
        order: .forward
    )
    private var settings: [AppSettings]

    /// The unit to SHOW. Falls back to the same default as
    /// `AppSettings.weightUnit` and the environment key, because three places
    /// disagreeing about what a bare number means is the failure canonical
    /// storage exists to remove.
    private var weightUnit: WeightUnit {
        settings.first?.weightUnit ?? .lbs
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.spacious) {
                    section("Units") {
                        NavigationLink {
                            WeightUnitPickerScreen(current: weightUnit) { picked in
                                choose(picked)
                            }
                        } label: {
                            SettingsValueRow(
                                title: "Weight Unit",
                                value: weightUnit.settingsLabel
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Says what the one row actually reaches, because "Weight
                    // Unit" alone does not distinguish training loads from body
                    // weight — and the reference app has a SEPARATE row for the
                    // second one, which this app does not yet.
                    Text("Applies to training loads. Body measurements keep their own units.")
                        .font(Typography.secondary)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, Spacing.screenMargin)
                }
                .padding(.vertical, Spacing.comfortable)
            }
            .background(Theme.surface)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    // "Close", not "Cancel". Nothing is pending — see the file
                    // comment — and a screen reader announcing "Cancel" would
                    // promise a rollback that does not happen.
                    .accessibilityLabel("Close")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Write the chosen unit, creating the settings row if this is somehow the
    /// first thing to ask for it (`MCPStrengthApp` makes it at launch, so this
    /// is a fallback rather than the normal path).
    ///
    /// The guard against a no-op write lives on the MODEL, not here — see
    /// `AppSettings.setWeightUnit`. A view cannot be tested and that rule is
    /// the part worth pinning.
    private func choose(_ unit: WeightUnit) {
        AppSettings.current(in: context).setWeightUnit(unit)
    }

    @ViewBuilder
    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text(title.uppercased())
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Spacing.screenMargin)

            VStack(spacing: 0) { content() }
                .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.card))
                .padding(.horizontal, Spacing.screenMargin)
        }
    }
}

// MARK: - Rows

/// A settings row that shows its current value and drills in — the reference
/// app's grammar for this screen: label left, value in the accent colour, a
/// chevron.
///
/// The VALUE ON THE ROW is the part worth keeping. A row reading only
/// "Weight Unit >" makes you open the screen to find out what it is set to,
/// which is the one question a settings list should answer without being tapped.
private struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: Spacing.compact) {
            Text(title)
                .font(Typography.body)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value)
                .font(Typography.body)
                .foregroundStyle(Theme.accent)
            Image(systemName: "chevron.right")
                .font(Typography.secondary.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.vertical, Spacing.comfortable)
        .padding(.horizontal, Spacing.screenMargin)
        // The whole strip, not just the glyphs on it. A tap landing in the
        // empty middle and doing nothing is the same class of bug as the
        // `.clear` folder background in docs/04-status.md.
        .contentShape(Rectangle())
    }
}

// MARK: - Picker

/// Picks the global weight unit. Two options, and picking one applies it and
/// goes back — there is nothing else on this screen to do.
struct WeightUnitPickerScreen: View {
    let current: WeightUnit
    let onSelect: (WeightUnit) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(WeightUnit.allCases.enumerated()), id: \.element) { index, unit in
                    Button {
                        onSelect(unit)
                        dismiss()
                    } label: {
                        HStack {
                            Text(unit.settingsLabel)
                                .font(Typography.body)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if unit == current {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.vertical, Spacing.comfortable)
                        .padding(.horizontal, Spacing.screenMargin)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index != WeightUnit.allCases.count - 1 {
                        Rectangle()
                            .fill(Theme.fieldFill)
                            .frame(height: 1)
                            .padding(.leading, Spacing.screenMargin)
                    }
                }
            }
            .padding(.top, Spacing.comfortable)
        }
        .background(Theme.surface)
        .navigationTitle("Weight Unit")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            // WHAT CHANGING THIS DOES, said before it is changed rather than
            // discovered afterwards. Every stored weight is kilograms already;
            // this only decides how they are RENDERED, so nothing is converted,
            // rounded or lost by switching — which is the reasonable fear
            // somebody has before touching a units setting on a training log.
            Text("Changes how weights are shown. Nothing already logged is altered.")
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.comfortable)
                .background(Theme.surface)
        }
    }
}

#Preview {
    SettingsScreen()
        .modelContainer(for: AppSettings.self, inMemory: true)
}

#Preview("Picker") {
    NavigationStack {
        WeightUnitPickerScreen(current: .lbs) { _ in }
    }
    .preferredColorScheme(.dark)
}
