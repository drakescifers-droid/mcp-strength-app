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

    /// Every live workout, so backfill can subtract what Health already has.
    /// `missingFromHealth` then drops unfinished / tombstoned / zero-length;
    /// this query only has to keep deleted-at-nil so a tombstone is not even
    /// in the array (the rule still refuses one if a caller handed it in).
    @Query(filter: #Predicate<Workout> { $0.deletedAt == nil })
    private var workouts: [Workout]

    /// Live and tombstoned. `alreadyHave` for import must include
    /// tombstones so a deleted Health row does not come back as a new one.
    /// `missingFromHealth` still refuses tombstones via `plan`.
    @Query private var measurementEntries: [MeasurementEntry]

    @Query(filter: #Predicate<MeasurementType> { $0.deletedAt == nil })
    private var measurementTypes: [MeasurementType]

    /// The banner sentence, or `nil` to show nothing. Nil is also the
    /// "could not ask Health" case — a failed query must not look like
    /// "Health has none of ours", which would offer Add for every finished
    /// workout and then duplicate them.
    @State private var backfillPrompt: String?
    @State private var missingWorkouts: [Workout] = []
    /// The look the app is wearing. Read here only to name it on the row —
    /// the picker itself does the writing.
    @Environment(ThemeStore.self) private var themeStore

    @State private var isAddingBackfill = false

    @State private var measurementWritePrompt: String?
    @State private var missingMeasurements: [MeasurementEntry] = []
    @State private var isAddingMeasurementWrite = false

    @State private var measurementImportPrompt: String?
    @State private var importableMeasurements: [HealthMeasurementImportPlan] = []
    @State private var isAddingMeasurementImport = false

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

                    section("Appearance") {
                        NavigationLink {
                            ThemePickerScreen()
                        } label: {
                            SettingsValueRow(
                                title: "Theme",
                                value: themeStore.selected.name
                            )
                        }
                        .buttonStyle(.plain)
                    }

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
        // Follows the palette, not a hard-coded dark. A sheet inherits the
        // window's scheme, but saying it here keeps this screen right when it
        // is presented from somewhere that does not.
        .preferredColorScheme(Theme.palette.colorScheme)
        .task(id: backfillScanKey) {
            await refreshBackfill()
        }
        .task(id: measurementBackfillScanKey) {
            await refreshMeasurementBackfill()
        }
    }

    /// Rescan when permission, the toggle, or the number of live workouts
    /// changes. A finished session while this sheet is open should be able
    /// to appear on the banner without dismissing Settings.
    private var backfillScanKey: String {
        "\(writeWorkoutsToHealth)-\(health?.workoutSharingStatus.hashValue ?? 0)-\(workouts.count)"
    }

    private var measurementBackfillScanKey: String {
        "\(writeMeasurementsToHealth)-\(readMeasurementsFromHealth)-\(health?.measurementSharingStatus.hashValue ?? 0)-\(measurementEntries.count)"
    }

    // MARK: - Apple Health
    //
    // TWO KINDS OF SWITCH, and they are not the same thing. The iOS
    // permission is asked once and cannot be revoked from here. The
    // `writeWorkoutsToHealth` toggle is the in-app switch the reference
    // has — permitted AND switched on — because without it the only way
    // to stop writing is to leave the app for Health. `Workout Active
    // Calories Rate` is a third thing: a number, stored, synced, shown
    // only when workouts are actually being written.
    //
    // The four permission states are still genuinely different sentences.
    // `.notDetermined` is a button; `.denied` is an instruction to go to
    // Health; `.authorized` is the toggle.

    private var writeWorkoutsToHealth: Bool {
        settings.first?.writeWorkoutsToHealth ?? true
    }

    private var writeMeasurementsToHealth: Bool {
        settings.first?.writeMeasurementsToHealth ?? true
    }

    private var readMeasurementsFromHealth: Bool {
        settings.first?.readMeasurementsFromHealth ?? true
    }

    @ViewBuilder
    private var healthSection: some View {
        let status = health?.workoutSharingStatus ?? .unavailable
        let energyStatus = health?.activeEnergySharingStatus ?? .unavailable

        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("APPLE HEALTH")
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Spacing.screenMargin)

            Text("ALLOW MCP STRENGTH TO WRITE")
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, Spacing.compact)

            VStack(spacing: 0) {
                if status == .notDetermined {
                    Button {
                        Task { try? await health?.requestWorkoutAuthorization() }
                    } label: {
                        SettingsValueRow(title: "Workouts", value: "Allow")
                    }
                    .buttonStyle(.plain)
                } else if status == .authorized {
                    SettingsToggleRow(
                        title: "Workouts",
                        subtitle: "Sync workouts originating from MCP Strength to Apple Health.",
                        isOn: writeWorkoutsToHealth,
                        onChange: { enabled in
                            AppSettings.current(in: context).setWriteWorkoutsToHealth(enabled)
                        }
                    )
                } else {
                    SettingsValueRow(title: "Workouts", value: healthValue(status))
                }
            }
            .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.card))
            .padding(.horizontal, Spacing.screenMargin)

            if status == .authorized, writeWorkoutsToHealth, let prompt = backfillPrompt {
                HealthBackfillBanner(
                    text: prompt,
                    isBusy: isAddingBackfill,
                    addAccessibilityLabel: "Add workouts to Apple Health",
                    onAdd: { Task { await addMissingWorkoutsToHealth() } }
                )
                .padding(.horizontal, Spacing.screenMargin)
            }

            Text(healthExplanation(status))
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Spacing.screenMargin)
                .fixedSize(horizontal: false, vertical: true)

            measurementWriteRow(status: health?.measurementSharingStatus ?? .unavailable)

            measurementReadRow(status: health?.measurementSharingStatus ?? .unavailable)

            if status == .authorized, writeWorkoutsToHealth {
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

    @ViewBuilder
    private func measurementWriteRow(status: HealthSharingStatus) -> some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            VStack(spacing: 0) {
                if status == .notDetermined {
                    Button {
                        Task { try? await health?.requestMeasurementAuthorization() }
                    } label: {
                        SettingsValueRow(title: "Measurements", value: "Allow")
                    }
                    .buttonStyle(.plain)
                } else if status == .authorized {
                    SettingsToggleRow(
                        title: "Measurements",
                        subtitle: "Sync measurements originating from MCP Strength to Apple Health.",
                        isOn: writeMeasurementsToHealth,
                        onChange: { enabled in
                            AppSettings.current(in: context).setWriteMeasurementsToHealth(enabled)
                        }
                    )
                } else {
                    SettingsValueRow(title: "Measurements", value: healthValue(status))
                }
            }
            .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.card))
            .padding(.horizontal, Spacing.screenMargin)

            if status == .authorized, writeMeasurementsToHealth, let prompt = measurementWritePrompt {
                HealthBackfillBanner(
                    text: prompt,
                    isBusy: isAddingMeasurementWrite,
                    addAccessibilityLabel: "Add measurements to Apple Health",
                    onAdd: { Task { await addMissingMeasurementsToHealth() } }
                )
                .padding(.horizontal, Spacing.screenMargin)
            }

            Text(measurementWriteExplanation(status))
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Spacing.screenMargin)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Spacing.compact)
    }

    private func measurementWriteExplanation(_ status: HealthSharingStatus) -> String {
        switch status {
        case .notDetermined:
            return "Weight, Body Fat %, Caloric Intake and Waist can be added to Apple Health. The other body-part measurements have no Apple Health type, so they stay in this app."
        case .authorized:
            if writeMeasurementsToHealth {
                return "Those four types are added when you record them. Neck, arms, legs and the rest have no Apple Health type and are not sent."
            }
            return "Measurements you record are not added to Apple Health. Turn this back on to resume."
        case .denied:
            return "Turned off. To allow it, open Health, then Sharing, then Apps, and turn on MCP Strength."
        case .unavailable:
            return "Apple Health is not available on this device."
        }
    }

    @ViewBuilder
    private func measurementReadRow(status: HealthSharingStatus) -> some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("ALLOW MCP STRENGTH TO READ")
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Spacing.screenMargin)

            VStack(spacing: 0) {
                if status == .notDetermined {
                    Button {
                        Task { try? await health?.requestMeasurementAuthorization() }
                    } label: {
                        SettingsValueRow(title: "Measurements", value: "Allow")
                    }
                    .buttonStyle(.plain)
                } else if status == .authorized {
                    SettingsToggleRow(
                        title: "Measurements",
                        subtitle: "Measurements will be read from Apple Health and shown here. They sync like any other entry you record.",
                        isOn: readMeasurementsFromHealth,
                        onChange: { enabled in
                            AppSettings.current(in: context).setReadMeasurementsFromHealth(enabled)
                        }
                    )
                } else {
                    SettingsValueRow(title: "Measurements", value: healthValue(status))
                }
            }
            .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.card))
            .padding(.horizontal, Spacing.screenMargin)

            if status == .authorized, readMeasurementsFromHealth, let prompt = measurementImportPrompt {
                HealthBackfillBanner(
                    text: prompt,
                    isBusy: isAddingMeasurementImport,
                    addAccessibilityLabel: "Add measurements from Apple Health",
                    onAdd: { Task { await addMeasurementsFromHealth() } }
                )
                .padding(.horizontal, Spacing.screenMargin)
            }

            Text(measurementReadExplanation(status))
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Spacing.screenMargin)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Spacing.compact)
    }

    private func measurementReadExplanation(_ status: HealthSharingStatus) -> String {
        switch status {
        case .notDetermined:
            return "Weight, Body Fat %, Caloric Intake and Waist already in Apple Health can be added here. The other body-part measurements have no Apple Health type."
        case .authorized:
            if readMeasurementsFromHealth {
                return "Those four types can be added from Apple Health. A number this app wrote is not imported again."
            }
            return "Measurements in Apple Health are not added here. Turn this back on to resume."
        case .denied:
            return "Turned off. To allow it, open Health, then Sharing, then Apps, and turn on MCP Strength."
        case .unavailable:
            return "Apple Health is not available on this device."
        }
    }

    private func calorieExplanation(_ energyStatus: HealthSharingStatus) -> String {
        switch energyStatus {
        case .authorized:
            // The rate is the FALLBACK. Watch samples, when present, are
            // used instead — that is the whole point of the read permission.
            return "If Apple Watch already recorded energy for the session, those calories are used. Otherwise this rate is the estimate. None writes no energy."
        case .denied:
            return "Energy is turned off for MCP Strength in Health, so no calories are added. To allow it, open Health, then Sharing, then Apps."
        case .notDetermined:
            // Same prompt now asks to READ Active Energy as well as write
            // it. Say both, or the sheet Drake sees will ask for something
            // this sentence did not mention.
            return "Allow Active Energy so workouts can use calories Apple Watch already recorded, or this estimate when it has not."
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
            return "Finished workouts can be added to Apple Health, so your training counts toward your activity."
        case .authorized:
            if writeWorkoutsToHealth {
                return "Workouts you finish are added to Apple Health."
            }
            return "Workouts you finish are not added to Apple Health. Turn this back on to resume."
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

    /// Ask Health what it already has, then compose the banner from the
    /// two backfill functions. A failed query clears the banner rather
    /// than treating it as "Health has none of ours" — that would offer
    /// Add for every finished workout and then duplicate them.
    @MainActor
    private func refreshBackfill() async {
        guard
            writeWorkoutsToHealth,
            health?.workoutSharingStatus == .authorized,
            let health
        else {
            missingWorkouts = []
            backfillPrompt = nil
            return
        }
        do {
            let written = try await health.writtenExternalIDs()
            let missing = HealthWorkoutRule.missingFromHealth(
                workouts,
                alreadyWritten: written
            )
            missingWorkouts = missing
            backfillPrompt = HealthWorkoutRule.backfillPrompt(count: missing.count)
        } catch {
            missingWorkouts = []
            backfillPrompt = nil
        }
    }

    /// Write every missing workout through the same path Finish uses, then
    /// rescan. One failure does not abort the rest — a session Health
    /// already has (the race with a finish that landed while this ran)
    /// must not block the others. `writeWorkout` is itself idempotent.
    @MainActor
    private func addMissingWorkoutsToHealth() async {
        guard let health, !isAddingBackfill else { return }
        isAddingBackfill = true
        defer { isAddingBackfill = false }
        let rate = calorieRate
        for workout in missingWorkouts {
            guard case .success(let plan) = HealthWorkoutRule.plan(for: workout, rate: rate)
            else { continue }
            try? await health.writeWorkout(plan, rate: rate, workoutsEnabled: true)
        }
        await refreshBackfill()
    }

    /// Same throw-clears-the-banner contract as workouts. Write and import
    /// are two queries; a failure on one must not invent a banner for the
    /// other, so each has its own do/catch.
    @MainActor
    private func refreshMeasurementBackfill() async {
        let status = health?.measurementSharingStatus
        guard let health, status == .authorized else {
            missingMeasurements = []
            measurementWritePrompt = nil
            importableMeasurements = []
            measurementImportPrompt = nil
            return
        }

        if writeMeasurementsToHealth {
            do {
                let written = try await health.writtenMeasurementExternalIDs()
                let missing = HealthMeasurementRule.missingFromHealth(
                    from: measurementEntries,
                    alreadyWritten: written
                )
                missingMeasurements = missing
                measurementWritePrompt = HealthMeasurementRule.writePrompt(count: missing.count)
            } catch {
                missingMeasurements = []
                measurementWritePrompt = nil
            }
        } else {
            missingMeasurements = []
            measurementWritePrompt = nil
        }

        if readMeasurementsFromHealth {
            do {
                let facts = try await health.measurementSampleFacts()
                let alreadyHave = Set(measurementEntries.map(\.id))
                let plans = HealthMeasurementRule.importPlans(
                    from: facts,
                    alreadyHave: alreadyHave
                )
                importableMeasurements = plans
                measurementImportPrompt = HealthMeasurementRule.importPrompt(count: plans.count)
            } catch {
                importableMeasurements = []
                measurementImportPrompt = nil
            }
        } else {
            importableMeasurements = []
            measurementImportPrompt = nil
        }
    }

    @MainActor
    private func addMissingMeasurementsToHealth() async {
        guard let health, !isAddingMeasurementWrite else { return }
        isAddingMeasurementWrite = true
        defer { isAddingMeasurementWrite = false }
        for entry in missingMeasurements {
            guard case .success(let plan) = HealthMeasurementRule.plan(for: entry) else { continue }
            try? await health.writeMeasurement(plan, enabled: true)
        }
        await refreshMeasurementBackfill()
    }

    @MainActor
    private func addMeasurementsFromHealth() async {
        guard !isAddingMeasurementImport else { return }
        isAddingMeasurementImport = true
        defer { isAddingMeasurementImport = false }
        let typesByID = Dictionary(uniqueKeysWithValues: measurementTypes.map { ($0.id, $0) })
        for plan in importableMeasurements {
            guard let type = typesByID[plan.typeID] else { continue }
            let entry = MeasurementEntry(
                id: plan.id,
                value: plan.local.value,
                unit: plan.local.unit,
                recordedAt: plan.recordedAt,
                source: .healthKit,
                type: type
            )
            context.insert(entry)
            entry.markEdited()
        }
        try? context.save()
        await refreshMeasurementBackfill()
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
private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.compact) {
            VStack(alignment: .leading, spacing: Spacing.compact / 2) {
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Typography.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.compact)
            Toggle("", isOn: Binding(
                get: { isOn },
                set: onChange
            ))
            .labelsHidden()
            .tint(Theme.accent)
        }
        .padding(.vertical, Spacing.comfortable)
        .padding(.horizontal, Spacing.screenMargin)
    }
}

/// The yellow strip under Workouts. Copy comes from
/// `HealthWorkoutRule.backfillPrompt`; this view only lays it out.
///
/// Add is a real button, not a tap on the whole strip: the sentence is a
/// question, and tapping the question to answer it is easy to do by
/// accident while scrolling. Busy replaces the label rather than hiding
/// the control — a vanished Add while writing reads as "nothing to add".
private struct HealthBackfillBanner: View {
    let text: String
    let isBusy: Bool
    let addAccessibilityLabel: String
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.compact) {
            Image(systemName: "info.circle")
                .font(Typography.body)
                .foregroundStyle(Theme.noticeText)
            Text(text)
                .font(Typography.secondary)
                .foregroundStyle(Theme.noticeText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.compact)
            Button(action: onAdd) {
                if isBusy {
                    ProgressView()
                        .tint(Theme.noticeText)
                } else {
                    Text("Add")
                        .font(Typography.button)
                        .foregroundStyle(Theme.noticeText)
                }
            }
            .disabled(isBusy)
            .accessibilityLabel(isBusy ? "Adding. \(addAccessibilityLabel)" : addAccessibilityLabel)
        }
        .padding(.vertical, Spacing.comfortable)
        .padding(.horizontal, Spacing.screenMargin)
        .background(Theme.notice, in: .rect(cornerRadius: Radius.card))
    }
}

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
    var popsOnSelect: Bool = true
    let onSelect: (WeightUnit) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(WeightUnit.allCases.enumerated()), id: \.element) { index, unit in
                    Button {
                        onSelect(unit)
                        if popsOnSelect {
                            dismiss()
                        }
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
            // WHAT THIS IS, said where it is chosen. Watch samples win when
            // they exist; this rate is the fallback; None still means off.
            Text("If Apple Watch already recorded Active Energy during the session, that number is used and this rate is ignored. Otherwise this rate is the estimate. None means no calories from this app at all.")
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
        .environment(ThemeStore())
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
