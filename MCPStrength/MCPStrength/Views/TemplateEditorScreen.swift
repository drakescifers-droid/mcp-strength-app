//
//  TemplateEditorScreen.swift
//  MCPStrength
//
//  A template is a workout you have not performed yet. This editor is the SAME
//  layout as the active-workout screen: the shared `SetRow`, the shared column
//  header, the same rest dividers, the same "+ Add Set". It differs in exactly
//  two places — the top bar reads ✕ / "Edit Template" / Save instead of
//  timer / elapsed / Finish, and the final column is a lock affordance rather
//  than a completion checkmark (a template has nothing to complete).
//
//  Edit-discard semantics: edits live in local draft state until Save. ✕
//  discards (nothing is written); Save persists the drafts to the template (or
//  creates it, for a new template). This keeps "✕ discards / Save persists"
//  honest without a SwiftData transaction.
//

import SwiftUI
import SwiftData

// MARK: - Draft model

/// A mutable, value-type snapshot of a `TemplateExercise` being edited. Holds
/// the picked `Exercise` reference and its sets. The editor mutates these
/// freely; Save writes them back to the store.
struct DraftExercise: Identifiable {
    let id: UUID
    var exercise: Exercise
    var defaultRestSeconds: Int
    /// Carried through so Save does not lose it — same reason as DraftSet's
    /// repRange/rpe below. Save copies these onto the surviving row, so
    /// anything the draft does not hold would be wiped on a field write.
    /// Before the options menu these three had no UI and no way to be set,
    /// which made the loss invisible; the menu makes it immediate.
    var note: String?
    var stickyNote: String?
    var supersetGroupID: UUID?
    var sets: [DraftSet]
}

/// A mutable snapshot of a `TemplateSet`. `repRangeStart` / `repRangeEnd` /
/// `rpe` are carried through so Save does not lose them, but no UI is built for
/// them in this task (a later task owns prescribed-effort entry).
struct DraftSet: Identifiable {
    let id: UUID
    var order: Int
    var setType: SetType
    var weight: Double?
    var reps: Int?
    var repRangeStart: Int?
    var repRangeEnd: Int?
    var rpe: Double?
    var restSeconds: Int
}

// MARK: - TemplateEditorScreen

struct TemplateEditorScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// The user's global weight unit, published by `ContentView` and inherited
    /// through the sheet this screen is presented in.
    @Environment(\.weightUnit) private var globalWeightUnit

    /// The template being edited. `nil` means a brand-new template (the + path);
    /// Save creates it, ✕ leaves the store untouched.
    let template: Template?

    /// Destination folder for a NEW template. Ignored when `template` is
    /// non-nil — editing an existing template does not re-file it.
    let folder: TemplateFolder?

    init(template: Template?, folder: TemplateFolder? = nil) {
        self.template = template
        self.folder = folder
    }

    /// All history, for the "Previous" column — reused exactly as on the
    /// workout screen (see Views/WorkoutHistory.swift).
    @Query(filter: #Predicate<Workout> { $0.deletedAt == nil },
           sort: [SortDescriptor(\Workout.startedAt, order: .reverse)])
    private var allWorkouts: [Workout]

    @State private var name: String = ""
    @State private var exercises: [DraftExercise] = []
    @State private var showingExercisePicker = false

    /// Which option sheet is open, and for which exercise.
    ///
    /// One identifiable value rather than a boolean per sheet: the index and
    /// the presentation cannot disagree, which is the `.sheet(item:)` lesson
    /// from docs/04-status.md.
    @State private var activeOption: ActiveOption?

    struct ActiveOption: Identifiable {
        /// `rest` is the exercise's default for NEW sets, from the menu.
        /// `setRest` is one existing set's own rest, from tapping its divider.
        /// Two different values on two different rows — see `RestDivider`.
        enum Kind { case note, stickyNote, rest, setRest(Int), replace }
        let id = UUID()
        let index: Int
        let kind: Kind
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: Spacing.spacious) {
                    nameField

                    ForEach(Array(exercises.enumerated()), id: \.element.id) { index, _ in
                        exerciseBlock(at: index)
                    }

                    addExercisesButton
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.spacious)
            }
        }
        .background(Theme.surface)
        .sheet(item: $activeOption) { option in
            optionSheet(for: option)
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisesScreen(onSelect: { exercise in
                addExercise(exercise)
                showingExercisePicker = false
            })
        }
        .onAppear { loadDraft() }
    }

    // MARK: - Header

    // ✕ / "Edit Template" / Save. Save uses the accent, solid — the affirmative
    // path. ✕ discards the drafts and dismisses.
    private var header: some View {
        HStack(spacing: Spacing.comfortable) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(Typography.body)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.chip))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Edit Template")
                .font(Typography.title)
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Button("Save") { save() }
                .buttonStyle(PrimaryActionButtonStyle(fill: Theme.accent))
                .frame(maxWidth: 140)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.vertical, Spacing.compact)
    }

    // MARK: - Options sheets

    @ViewBuilder
    private func optionSheet(for option: ActiveOption) -> some View {
        if exercises.indices.contains(option.index) {
            let draft = exercises[option.index]
            switch option.kind {
            case .note:
                ExerciseNoteSheet(
                    isSticky: false,
                    exerciseName: draft.exercise.name,
                    initialText: draft.note
                ) { exercises[option.index].note = $0 }

            case .stickyNote:
                ExerciseNoteSheet(
                    isSticky: true,
                    exerciseName: draft.exercise.name,
                    initialText: draft.stickyNote
                ) { exercises[option.index].stickyNote = $0 }

            case .rest:
                RestTimerSheet(
                    scope: .wholeExercise(exerciseName: draft.exercise.name),
                    current: draft.defaultRestSeconds
                ) { seconds in
                    // Same rule as the workout screen: the exercise default AND
                    // every set already drafted. These are value types, so the
                    // sets are rewritten in place and nothing is persisted
                    // until Save — TemplateSaveDiff sees them as ordinary
                    // field changes on KEPT rows.
                    exercises[option.index].defaultRestSeconds = seconds
                    for i in exercises[option.index].sets.indices {
                        exercises[option.index].sets[i].restSeconds = seconds
                    }
                }

            case .setRest(let setIndex):
                if draft.sets.indices.contains(setIndex) {
                    RestTimerSheet(
                        scope: .oneSet,
                        current: draft.sets[setIndex].restSeconds
                    ) { exercises[option.index].sets[setIndex].restSeconds = $0 }
                }

            case .replace:
                // Swaps the movement and KEEPS the sets. Replacing an exercise
                // means "I did this on a different machine", not "start over" —
                // wiping the prescription would make it faster to delete and
                // re-add, which is the tell that the feature is wrong.
                ExercisesScreen(onSelect: { picked in
                    exercises[option.index].exercise = picked
                    activeOption = nil
                })
            }
        }
    }

    // MARK: - Options menu

    /// The menu owns no behaviour; this decides what each choice means HERE.
    /// The live workout screen answers the same menu differently — it edits
    /// persisted models, this edits in-memory drafts — which is exactly why the
    /// menu itself is behaviour-free.
    private func onOption(_ index: Int, _ option: ExerciseOption) {
        guard exercises.indices.contains(index) else { return }
        switch option {
        case .addNote:
            activeOption = ActiveOption(index: index, kind: .note)
        case .addStickyNote:
            activeOption = ActiveOption(index: index, kind: .stickyNote)
        case .updateRestTimers:
            activeOption = ActiveOption(index: index, kind: .rest)
        case .replaceExercise:
            activeOption = ActiveOption(index: index, kind: .replace)
        case .addWarmupSets:
            addWarmupSets(at: index)
        case .createSuperset:
            toggleSuperset(at: index)
        case .removeExercise:
            exercises.remove(at: index)
        }
    }

    /// Replace this exercise's warm-up drafts with a freshly generated ramp.
    ///
    /// Same rule as the live workout screen — regenerate from the current
    /// working weight rather than appending — but the mechanics are far
    /// simpler here, and that difference is the reason the two screens answer
    /// this menu separately. These are value-type DRAFTS: dropping a warm-up
    /// is `removeAll`, with no tombstone to write, because nothing is
    /// persisted until Save. `TemplateSaveDiff` then works out which real rows
    /// disappeared and tombstones exactly those.
    ///
    /// A template's working weight is a PRESCRIPTION and is often blank —
    /// `TemplateSet.weight` is optional and plenty of templates carry only rep
    /// ranges. No weight means no ramp, which `WarmupSets` already returns as
    /// an empty plan.
    private func addWarmupSets(at index: Int) {
        let sets = exercises[index].sets
        let working = sets.first { $0.setType != .warmup && $0.weight != nil }

        // Ramps in the user's unit and converts each step back on the way into
        // the draft — see the workout screen's copy, and `WarmupSets` for why
        // this calculation is the one that leaves canonical kilograms.
        let unit = displayUnit(for: exercises[index].exercise)
        let plan = WarmupSets.plan(
            forWorkingWeight: working?.weight.map {
                WeightUnits.displayed(from: $0, in: unit)
            },
            barWeight: exercises[index].exercise.barType?.weight(in: unit),
            in: unit
        )
        guard !plan.isEmpty else { return }

        let rest = exercises[index].defaultRestSeconds
        let warmups = plan.enumerated().map { offset, step in
            DraftSet(
                id: UUID(),
                order: offset,
                setType: step.setType,
                weight: WeightUnits.kilograms(from: step.weight, in: unit),
                reps: step.reps,
                restSeconds: rest
            )
        }
        // A fresh UUID per generated set is correct here: these are NEW rows,
        // and loadDraft's ids exist so SURVIVING rows can be matched. A warm-up
        // that was just replaced is gone, and its draft id with it.
        let survivors = sets.filter { $0.setType != .warmup }
        exercises[index].sets = (warmups + survivors).enumerated().map { offset, set in
            var renumbered = set
            renumbered.order = offset
            return renumbered
        }
    }

    /// Group an exercise with the one above it, or leave the group it is in.
    ///
    /// Pairing with the PRECEDING exercise is the whole rule. A superset is
    /// performed round-robin in list order, so "join the thing before me" is
    /// both the common case and the only one expressible without a second
    /// selection UI. Leaving is symmetrical: clear the id.
    private func toggleSuperset(at index: Int) {
        if exercises[index].supersetGroupID != nil {
            exercises[index].supersetGroupID = nil
            return
        }
        guard index > 0 else {
            // Nothing above to pair with. A superset of one is not a superset,
            // so this is a no-op rather than a group containing one exercise.
            return
        }
        let existing = exercises[index - 1].supersetGroupID
        let group = existing ?? UUID()
        exercises[index - 1].supersetGroupID = group
        exercises[index].supersetGroupID = group
    }

    // MARK: - Name field

    private var nameField: some View {
        TextField("Template Name", text: $name)
            .font(Typography.title)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Spacing.comfortable)
            .padding(.vertical, Spacing.compact)
            .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.chip))
    }

    // MARK: - Exercise block

    // Built from the SHARED SetRow — identical structure to the workout screen's
    // ExerciseBlock: exercise name in accent, column headers (lock trailing),
    // set rows with editable weight and reps, rest dividers between sets, and an
    // "+ Add Set" button.
    @ViewBuilder
    private func exerciseBlock(at index: Int) -> some View {
        let draft = exercises[index]
        // Working-set numbers parallel to `draft.sets`: only `.normal` sets
        // consume a number, so lettered types are skipped and normal numbering
        // continues past them (docs/01-data-model.md § SetType).
        let workingNumbers = SetNumbering.workingNumbers(for: draft.sets.map(\.setType))
        // Counted within kind, because the editor has `Add Warm-up Sets` too and
        // the same shift would happen here.
        let previousPositions = SetNumbering.positionsWithinKind(for: draft.sets.map(\.setType))

        VStack(alignment: .leading, spacing: Spacing.comfortable) {
            HStack(spacing: Spacing.compact) {
                Text(draft.exercise.name)
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ExerciseOptionsMenu(
                    hasNote: !(draft.note ?? "").isEmpty,
                    hasStickyNote: !(draft.stickyNote ?? "").isEmpty,
                    isInSuperset: draft.supersetGroupID != nil,
                    onSelect: { onOption(index, $0) }
                )
            }

            if let sticky = draft.stickyNote, !sticky.isEmpty {
                ExpandableNote(text: sticky, kind: .exercise, tint: Theme.warmup)
            }

            SetRowColumnHeader(
                trailingIcon: "lock.fill",
                unit: displayUnit(for: draft.exercise)
            )

            VStack(spacing: 0) {
                ForEach(Array(draft.sets.enumerated()), id: \.element.id) { setIndex, set in
                    SetRow(
                        setType: bindingForSetType(exercise: index, set: setIndex),
                        setNumber: workingNumbers[setIndex],
                        previousText: previousText(
                            for: draft.exercise,
                            at: previousPositions[setIndex],
                            like: set.setType
                        ),
                        weight: bindingForWeight(exercise: index, set: setIndex),
                        unit: displayUnit(for: draft.exercise),
                        prescription: bindingForPrescription(exercise: index, set: setIndex),
                        allowRange: true,
                        rpe: bindingForRPE(exercise: index, set: setIndex),
                        trailing: .locked,
                        onDelete: { deleteSet(at: setIndex, in: index) }
                    )

                    // Every set, last one included — same rule as the workout
                    // screen, and for the same two reasons: the rest after the
                    // final set is a real rest, and the divider is the only way
                    // to edit one.
                    RestDivider(restSeconds: set.restSeconds) {
                        activeOption = ActiveOption(
                            index: index,
                            kind: .setRest(setIndex)
                        )
                    }
                }
            }

            AddSetButton(label: "+ Add Set (\(formatMinutesSeconds(draft.defaultRestSeconds)))") {
                addSet(to: index)
            }
        }
    }

    // MARK: - Bindings into draft state

    // The shared SetRow is decoupled from any model; here it binds into the
    // local drafts so edits are not committed until Save.
    private func bindingForWeight(exercise: Int, set: Int) -> Binding<Double?> {
        Binding(
            get: { exercises[exercise].sets[set].weight },
            set: { exercises[exercise].sets[set].weight = $0 }
        )
    }

    // The reps prescription is the SINGLE source of truth for the row's Reps
    // field. Reading collapses `reps` / `repRangeStart` / `repRangeEnd` into one
    // `RepRange?`; writing splits it back out — a fixed target writes `reps`
    // and clears the range, a range writes the range and clears `reps`. The two
    // are mutually exclusive by construction.
    private func bindingForPrescription(exercise: Int, set: Int) -> Binding<RepRange?> {
        Binding(
            get: {
                let s = exercises[exercise].sets[set]
                return RepRange.fromTemplate(reps: s.reps, start: s.repRangeStart, end: s.repRangeEnd)
            },
            set: { newValue in
                let fields = newValue?.templateFields()
                exercises[exercise].sets[set].reps = fields?.reps
                exercises[exercise].sets[set].repRangeStart = fields?.start
                exercises[exercise].sets[set].repRangeEnd = fields?.end
            }
        )
    }

    private func bindingForRPE(exercise: Int, set: Int) -> Binding<Double?> {
        Binding(
            get: { exercises[exercise].sets[set].rpe },
            set: { exercises[exercise].sets[set].rpe = $0 }
        )
    }

    private func bindingForSetType(exercise: Int, set: Int) -> Binding<SetType> {
        Binding(
            get: { exercises[exercise].sets[set].setType },
            set: { exercises[exercise].sets[set].setType = $0 }
        )
    }

    // MARK: - Previous

    // Reuses WorkoutHistory exactly as the workout screen does — the template's
    // exercises are the same Exercise records, so prior performances match.
    private func previousText(for exercise: Exercise, at position: Int, like setType: SetType) -> String {
        let prev = WorkoutHistory.previousSet(
            for: exercise,
            at: position,
            like: setType,
            in: allWorkouts
        )
        return PreviousText.format(prev, in: displayUnit(for: exercise))
    }

    // MARK: - Units

    /// The unit this exercise's weights are read and written in.
    ///
    /// Per exercise rather than per screen, because the override is a property
    /// of the lift. Same resolution as the live workout screen's
    /// `ExerciseBlock.displayUnit`, and both become a lookup on
    /// `ExercisePreference` when those fields move (docs/06-sync.md).
    private func displayUnit(for exercise: Exercise) -> WeightUnit {
        WeightUnits.displayUnit(
            override: exercise.weightUnitOverride,
            global: globalWeightUnit
        )
    }

    // MARK: - Bottom action

    private var addExercisesButton: some View {
        Button("Add Exercises") { showingExercisePicker = true }
            .buttonStyle(.tintedAccent)
    }

    // MARK: - Load

    // Hydrate the drafts from the existing template, or seed a default name
    // for a new one. The `isEmpty` guards make this idempotent across re-renders.
    private func loadDraft() {
        guard exercises.isEmpty, name.isEmpty else { return }
        if let template {
            name = template.name
            exercises = template.liveExercises
                .sorted(by: { $0.order < $1.order })
                .map { tx in
                    DraftExercise(
                        id: tx.id,
                        exercise: tx.exercise ?? Exercise(
                            name: "Unknown Exercise",
                            bodyPart: .other,
                            category: .repsOnly,
                            focusMetric: .totalVolume
                        ),
                        defaultRestSeconds: tx.defaultRestSeconds,
                        note: tx.note,
                        stickyNote: tx.stickyNote,
                        supersetGroupID: tx.supersetGroupID,
                        sets: tx.liveSets
                            .sorted(by: { $0.order < $1.order })
                            .map { ts in
                                DraftSet(
                                    id: ts.id,
                                    order: ts.order,
                                    setType: ts.setType,
                                    weight: ts.weight,
                                    reps: ts.reps,
                                    repRangeStart: ts.repRangeStart,
                                    repRangeEnd: ts.repRangeEnd,
                                    rpe: ts.rpe,
                                    restSeconds: ts.restSeconds
                                )
                            }
                    )
                }
        } else {
            name = "New Template"
        }
    }

    // MARK: - Mutations (on drafts)

    private func addExercise(_ exercise: Exercise) {
        exercises.append(
            DraftExercise(
                id: UUID(),
                exercise: exercise,
                defaultRestSeconds: 90,
                sets: [
                    DraftSet(
                        id: UUID(),
                        order: 0,
                        setType: .normal,
                        restSeconds: 90
                    )
                ]
            )
        )
    }

    /// Drop one drafted set, from the swipe affordance on its row.
    ///
    /// No tombstone here and that is not an oversight: these are value-type
    /// DRAFTS and nothing is persisted until Save. `TemplateSaveDiff` compares
    /// ids at save time and writes the tombstone for any row that has
    /// disappeared — exactly what it already does for warm-ups replaced by a
    /// regenerated ramp. Writing one here would tombstone a row the user might
    /// still discard by closing without saving.
    ///
    /// `order` is rewritten so the remaining sets stay dense, matching the
    /// warm-up path in this file.
    private func deleteSet(at setIndex: Int, in exerciseIndex: Int) {
        guard exercises.indices.contains(exerciseIndex),
              exercises[exerciseIndex].sets.indices.contains(setIndex)
        else { return }
        exercises[exerciseIndex].sets.remove(at: setIndex)
        for i in exercises[exerciseIndex].sets.indices {
            exercises[exerciseIndex].sets[i].order = i
        }
    }

    private func addSet(to exerciseIndex: Int) {
        let nextOrder = (exercises[exerciseIndex].sets.map(\.order).max() ?? -1) + 1
        let rest = exercises[exerciseIndex].defaultRestSeconds
        exercises[exerciseIndex].sets.append(
            DraftSet(
                id: UUID(),
                order: nextOrder,
                setType: .normal,
                restSeconds: rest
            )
        )
    }

    // MARK: - Save

    // Persist the drafts. Identity is the join key: a draft hydrated from an
    // existing row carries that row's id (see loadDraft), and a draft the user
    // just added carries a freshly minted one. TemplateSaveDiff classifies
    // each id as KEPT (update in place), ADDED (insert), or REMOVED
    // (tombstone). Saving a template the user did not change therefore
    // produces no insertions and no tombstones — the property the old
    // replace-everything write could never have. A new template has no
    // existing rows, so the same plan is all-ADDED.
    private func save() {
        let target: Template
        let existingPairs: [(id: UUID, setIDs: [UUID])]

        if let template {
            target = template
            if target.name != name {
                target.name = name
                target.markEdited()
            }
            existingPairs = target.liveExercises.map { tx in
                (id: tx.id, setIDs: tx.liveSets.map(\.id))
            }
        } else {
            // Per-folder position: a new template lands at the end of ITS
            // folder (or the unfiled list), not after every template in the store.
            let existing = (try? context.fetch(FetchDescriptor<Template>())) ?? []
            let nextOrder = existing.filter { $0.folder?.id == folder?.id }.count
            target = Template(name: name, order: nextOrder, folder: folder)
            context.insert(target)
            existingPairs = []
        }

        let draftPairs = exercises.map { draft in
            (id: draft.id, setIDs: draft.sets.map(\.id))
        }
        applySavePlan(
            TemplateSaveDiff.plan(drafts: draftPairs, existing: existingPairs),
            to: target
        )

        dismiss()
    }

    /// Writes one TemplateSaveDiff plan onto `target`. Kept rows are updated
    /// in place and marked only when a field (including order) actually
    /// changed — over-marking is a redundant upsert, under-marking loses
    /// the edit. Added rows are inserted with the draft's already-minted
    /// id so a later load hydrates the same identity. Removed exercises go
    /// through SoftDelete.templateExercise (CASCADE to sets); removed sets
    /// on a surviving exercise are markDeleted themselves. Never
    /// context.delete: a real delete cannot reach a device that was offline
    /// when it happened, so the row comes back on the next pull.
    private func applySavePlan(_ plan: TemplateSaveDiff.Plan, to target: Template) {
        let existingByID = Dictionary(uniqueKeysWithValues: target.liveExercises.map { ($0.id, $0) })
        let draftByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })

        for id in plan.exercises.removed {
            if let tx = existingByID[id] {
                SoftDelete.templateExercise(tx)
            }
        }

        for item in plan.exercises.kept {
            guard let tx = existingByID[item.id], let draft = draftByID[item.id] else { continue }
            applyKeptExercise(draft, to: tx, newOrder: item.newOrder)
            applySetPlan(
                plan.setsByKeptExercise[item.id] ?? .empty,
                draft: draft,
                exercise: tx
            )
        }

        for item in plan.exercises.added {
            guard let draft = draftByID[item.id] else { continue }
            insertExercise(draft, order: item.newOrder, into: target)
        }
    }

    private func applyKeptExercise(_ draft: DraftExercise, to tx: TemplateExercise, newOrder: Int) {
        // Replace Exercise keeps the draft's id and only swaps the movement,
        // so the TemplateExercise row is KEPT and this comparison is what
        // actually writes the new Exercise onto it.
        let exerciseChanged = tx.exercise?.id != draft.exercise.id
        let changed =
            tx.order != newOrder
            || tx.supersetGroupID != draft.supersetGroupID
            || tx.note != draft.note
            || tx.stickyNote != draft.stickyNote
            || tx.defaultRestSeconds != draft.defaultRestSeconds
            || exerciseChanged

        tx.order = newOrder
        tx.supersetGroupID = draft.supersetGroupID
        tx.note = draft.note
        tx.stickyNote = draft.stickyNote
        tx.defaultRestSeconds = draft.defaultRestSeconds
        if exerciseChanged {
            tx.exercise = draft.exercise
        }
        if changed {
            tx.markEdited()
        }
    }

    private func applySetPlan(
        _ plan: TemplateSaveDiff.Level,
        draft: DraftExercise,
        exercise tx: TemplateExercise
    ) {
        let existingByID = Dictionary(uniqueKeysWithValues: tx.liveSets.map { ($0.id, $0) })
        let draftByID = Dictionary(uniqueKeysWithValues: draft.sets.map { ($0.id, $0) })

        for id in plan.removed {
            existingByID[id]?.markDeleted()
        }

        for item in plan.kept {
            guard let ts = existingByID[item.id], let draftSet = draftByID[item.id] else { continue }
            applyKeptSet(draftSet, to: ts, newOrder: item.newOrder)
        }

        for item in plan.added {
            guard let draftSet = draftByID[item.id] else { continue }
            insertSet(draftSet, order: item.newOrder, into: tx)
        }
    }

    private func applyKeptSet(_ draft: DraftSet, to ts: TemplateSet, newOrder: Int) {
        let changed =
            ts.order != newOrder
            || ts.setType != draft.setType
            || ts.weight != draft.weight
            || ts.reps != draft.reps
            || ts.repRangeStart != draft.repRangeStart
            || ts.repRangeEnd != draft.repRangeEnd
            || ts.rpe != draft.rpe
            || ts.restSeconds != draft.restSeconds

        ts.order = newOrder
        ts.setType = draft.setType
        ts.weight = draft.weight
        ts.reps = draft.reps
        ts.repRangeStart = draft.repRangeStart
        ts.repRangeEnd = draft.repRangeEnd
        ts.rpe = draft.rpe
        ts.restSeconds = draft.restSeconds
        if changed {
            ts.markEdited()
        }
    }

    private func insertExercise(_ draft: DraftExercise, order: Int, into template: Template) {
        let tx = TemplateExercise(
            id: draft.id,
            order: order,
            supersetGroupID: draft.supersetGroupID,
            note: draft.note,
            stickyNote: draft.stickyNote,
            defaultRestSeconds: draft.defaultRestSeconds,
            template: template,
            exercise: draft.exercise
        )
        context.insert(tx)
        for (setOrder, draftSet) in draft.sets.enumerated() {
            insertSet(draftSet, order: setOrder, into: tx)
        }
    }

    private func insertSet(_ draft: DraftSet, order: Int, into exercise: TemplateExercise) {
        let ts = TemplateSet(
            id: draft.id,
            order: order,
            setType: draft.setType,
            weight: draft.weight,
            reps: draft.reps,
            repRangeStart: draft.repRangeStart,
            repRangeEnd: draft.repRangeEnd,
            rpe: draft.rpe,
            restSeconds: draft.restSeconds,
            templateExercise: exercise
        )
        context.insert(ts)
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Exercise.self, Template.self, TemplateExercise.self, TemplateSet.self,
        Workout.self, WorkoutExercise.self, WorkoutSet.self,
        configurations: config
    )
    let context = container.mainContext

    let exercise = Exercise(name: "Back Squat", bodyPart: .legs, category: .barbell, focusMetric: .totalVolume)
    context.insert(exercise)

    let template = Template(name: "Leg Day", order: 0)
    context.insert(template)
    let tx = TemplateExercise(order: 0, defaultRestSeconds: 180, template: template, exercise: exercise)
    context.insert(tx)
    context.insert(TemplateSet(order: 0, weight: WeightUnits.kilograms(from: 225, in: .lbs), reps: 5, restSeconds: 180, templateExercise: tx))
    context.insert(TemplateSet(order: 1, weight: WeightUnits.kilograms(from: 245, in: .lbs), reps: 5, restSeconds: 180, templateExercise: tx))

    return TemplateEditorScreen(template: template)
        .modelContainer(container)
}
