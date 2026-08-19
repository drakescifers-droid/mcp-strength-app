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
    @Environment(HealthStore.self) private var health: HealthStore?

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

    /// The rate to SHOW. Falls back to `.medium`, which is the model's
    /// declaration default AND the server column's default — the two have to
    /// agree or a device that never touched the setting disagrees with the row
    /// the server hands its next device.
    private var calorieRate: WorkoutCalorieRate {
        settings.first?.workoutCalorieRate ?? .medium
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

                    healthSection
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

    // MARK: - Apple Health
    //
    // TWO ROWS, and they are different kinds of thing. `Workouts` is a
    // PERMISSION: there is no stored "write workouts to Health" flag anywhere,
    // because HealthKit already keeps a per-device answer and iOS already owns
    // the UI for changing it, so a second flag would be a second source of
    // truth that can disagree with the first (see HealthStore.swift).
    // `Workout Active Calories Rate` is a PREFERENCE — a number the user
    // chooses — and it is stored, synced, and defaulted to match the server.
    //
    // The four states are genuinely different sentences with different next
    // steps, which is exactly why `.notDetermined` is not collapsed into
    // "denied": one is a button, the other is an instruction to go somewhere
    // else. Getting that wrong would be a control that looks tappable and
    // cannot work — the rest-timer bug's shape.
    //
    // **The rate row appears only once workouts are actually being written**,
    // and that is the same rule applied to a preference rather than a
    // permission. Until Health is allowed, nothing reads the rate, so a picker
    // for it would be a control that changes a value with no consumer — which
    // is precisely why the other three unit rows are absent from this screen.
    // The reference app shows its rate row unconditionally; this is a
    // deliberate divergence, and it costs nothing, because the row appears the
    // moment the permission it depends on is granted.

    @ViewBuilder
    private var healthSection: some View {
        let status = health?.workoutSharingStatus ?? .unavailable
        let energyStatus = health?.activeEnergySharingStatus ?? .unavailable

        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("APPLE HEALTH")
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Spacing.screenMargin)

            VStack(spacing: 0) {
                if status == .notDetermined {
                    Button {
                        Task { try? await health?.requestWorkoutAuthorization() }
                    } label: {
                        SettingsValueRow(title: "Workouts", value: "Allow")
                    }
                    .buttonStyle(.plain)
                } else {
                    // Not a button: nothing here can change it. iOS never lets
                    // an app grant or revoke its own permission, so a tappable
                    // row would be a control that does nothing.
                    SettingsValueRow(title: "Workouts", value: healthValue(status))
                }
            }
            .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.card))
            .padding(.horizontal, Spacing.screenMargin)

            Text(healthExplanation(status))
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Spacing.screenMargin)
                .fixedSize(horizontal: false, vertical: true)

            if status == .authorized {
                calorieRateRow(energyStatus: energyStatus)
            }
        }
    }

    /// The rate row and the sentence under it.
    ///
    /// **Three shapes, because the ENERGY permission has three answers that
    /// need different controls**, and it is authorized separately from the
    /// workout one:
    ///
    ///   * `.notDetermined` — an **Allow button**, not a picker. This is the
    ///     UPGRADE PATH and it is the case that is easy to miss: a device that
    ///     granted workouts BEFORE this build has never been asked about
    ///     energy, so the Workouts row above is already "On" and cannot ask
    ///     again. Without this button there would be no way, anywhere in the
    ///     app, to grant the permission the rate depends on.
    ///   * `.authorized` — the picker.
    ///   * `.denied` / `.unavailable` — the value, not tappable, because
    ///     nothing reads it. Same treatment as the Workouts row for the same
    ///     reason: a control that cannot do anything is the rest-timer bug.
    @ViewBuilder
    private func calorieRateRow(energyStatus: HealthSharingStatus) -> some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            VStack(spacing: 0) {
                switch energyStatus {
                case .notDetermined:
                    Button {
                        Task { try? await health?.requestWorkoutAuthorization() }
                    } label: {
                        SettingsValueRow(
                            title: "Workout Active Calories Rate",
                            value: "Allow"
                        )
                    }
                    .buttonStyle(.plain)

                case .authorized:
                    NavigationLink {
                        WorkoutCalorieRatePickerScreen(current: calorieRate) { picked in
                            choose(picked)
                        }
                    } label: {
                        SettingsValueRow(
                            title: "Workout Active Calories Rate",
                            value: calorieRate.settingsLabel
                        )
                    }
                    .buttonStyle(.plain)

                case .denied, .unavailable:
                    SettingsValueRow(
                        title: "Workout Active Calories Rate",
                        value: "Off"
                    )
                }
            }
            .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.card))
            .padding(.horizontal, Spacing.screenMargin)

            Text(calorieExplanation(energyStatus))
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Spacing.screenMargin)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Spacing.compact)
    }

    private func calorieExplanation(_ energyStatus: HealthSharingStatus) -> String {
        switch energyStatus {
        case .authorized:
            // Says it is an ESTIMATE and whose estimate it is. The app measures
            // nothing here and must not sound as though it does.
            return "An estimate you choose, added to each workout so it counts toward your activity. Nothing is measured."
        case .denied:
            return "Energy is turned off for MCP Strength in Health, so no calories are added. To allow it, open Health, then Sharing, then Apps."
        case .notDetermined:
            // The upgrade path: workouts were allowed before this feature
            // existed, so Health has never been asked about energy. Say what
            // tapping does rather than describing a state.
            return "Allow Active Energy to have an estimate of the calories burned added to each workout."
        case .unavailable:
            return "Apple Health is not available on this device."
        }
    }

    private func healthValue(_ status: HealthSharingStatus) -> String {
        switch status {
        case .notDetermined: "Allow"
        case .authorized:    "On"
        case .denied:        "Off"
        case .unavailable:   "Unavailable"
        }
    }

    /// Each state gets the sentence that names the NEXT STEP, because three of
    /// the four have one and it is not the same step.
    private func healthExplanation(_ status: HealthSharingStatus) -> String {
        switch status {
        case .notDetermined:
            return "Finished workouts can be added to Apple Health, so your training counts toward your activity. Nothing is read from Health."
        case .authorized:
            return "Workouts you finish are added to Apple Health. To stop, turn MCP Strength off in Health under Sharing."
        case .denied:
            // The only place that can change it is Health itself, so say so
            // rather than leaving a dead "Off" with no route back.
            return "Turned off. To allow it, open Health, then Sharing, then Apps, and turn on MCP Strength."
        case .unavailable:
            return "Apple Health is not available on this device."
        }
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

    /// Same shape, same reason: the no-op guard is on the MODEL
    /// (`AppSettings.setWorkoutCalorieRate`), because re-picking the rate that
    /// already has the tick must not dirty the row.
    private func choose(_ rate: WorkoutCalorieRate) {
        AppSettings.current(in: context).setWorkoutCalorieRate(rate)
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
            // Both sides wrap rather than truncate. "Workout Active Calories
            // Rate" against "Medium (200 kcal per hour)" does not fit one line
            // on any iPhone, and a truncated VALUE would defeat the entire
            // point of putting the number on the label.
            Text(title)
                .font(Typography.body)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.compact)
            Text(value)
                .font(Typography.body)
                .foregroundStyle(Theme.accent)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
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

/// Picks the rate Apple Health counts a workout at.
///
/// Five options, each naming the number it stands for, and picking one applies
/// it and goes back — the same grammar as `WeightUnitPickerScreen`, and for the
/// same reason: the write happens on tap, so there is nothing pending and no
/// Save to offer.
struct WorkoutCalorieRatePickerScreen: View {
    let current: WorkoutCalorieRate
    let onSelect: (WorkoutCalorieRate) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(WorkoutCalorieRate.allCases.enumerated()), id: \.element) { index, rate in
                    Button {
                        onSelect(rate)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rate.displayName)
                                    .font(Typography.body)
                                    .foregroundStyle(Theme.textPrimary)
                                // The rate under the name, because "Medium"
                                // alone is the app asserting an amount of
                                // energy without ever saying what it is.
                                if rate != .none {
                                    Text("\(Int(rate.kilocaloriesPerHour)) kcal per hour")
                                        .font(Typography.secondary)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            Spacer()
                            if rate == current {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.vertical, Spacing.comfortable)
                        .padding(.horizontal, Spacing.screenMargin)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index != WorkoutCalorieRate.allCases.count - 1 {
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
        .navigationTitle("Workout Calories")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            // WHAT THIS IS, said where it is chosen. Two sentences, and the
            // second is the one that matters: a Watch worn while lifting is
            // already recording energy, and whether Apple deduplicates ours
            // against it in the Activity rings is NOT established
            // (docs/02-architecture.md). `None` is the honest setting for a
            // Watch wearer until somebody checks.
            Text("Lifting energy is estimated from this rate, not measured. If you wear an Apple Watch while training it is already recording energy, and this may be counted on top — pick None if your rings look too high.")
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.comfortable)
                .background(Theme.surface)
                .fixedSize(horizontal: false, vertical: true)
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

#Preview("Calorie rate picker") {
    NavigationStack {
        WorkoutCalorieRatePickerScreen(current: .medium) { _ in }
    }
    .preferredColorScheme(.dark)
}
