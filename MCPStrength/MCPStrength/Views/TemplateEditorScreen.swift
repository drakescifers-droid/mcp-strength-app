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
    /// repRange/rpe below. Save REPLACES a template's exercises, so anything
    /// the draft does not hold is erased on every edit. Before the options
    /// menu these three had no UI and no way to be set, which made the loss
    /// invisible; the menu makes it immediate.
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
                    scope: .newSets(exerciseName: draft.exercise.name),
                    current: draft.defaultRestSeconds
                ) { exercises[option.index].defaultRestSeconds = $0 }

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
        case .createSuperset:
            toggleSuperset(at: index)
        case .removeExercise:
            exercises.remove(at: index)
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

            SetRowColumnHeader(trailingIcon: "lock.fill")

            VStack(spacing: 0) {
                ForEach(Array(draft.sets.enumerated()), id: \.element.id) { setIndex, set in
                    SetRow(
                        setType: bindingForSetType(exercise: index, set: setIndex),
                        setNumber: workingNumbers[setIndex],
                        previousText: previousText(for: draft.exercise, at: setIndex),
                        weight: bindingForWeight(exercise: index, set: setIndex),
                        prescription: bindingForPrescription(exercise: index, set: setIndex),
                        allowRange: true,
                        rpe: bindingForRPE(exercise: index, set: setIndex),
                        trailing: .locked
                    )

                    if setIndex < draft.sets.count - 1 {
                        RestDivider(restSeconds: set.restSeconds) {
                            activeOption = ActiveOption(
                                index: index,
                                kind: .setRest(setIndex)
                            )
                        }
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
    private func previousText(for exercise: Exercise, at position: Int) -> String {
        let prev = WorkoutHistory.previousSet(
            for: exercise,
            at: position,
            in: allWorkouts
        )
        return PreviousText.format(prev)
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
                        id: UUID(),
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
                                    id: UUID(),
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

    // Persist the drafts. For a new template, create it; for an existing one,
    // update the name and replace its exercises/sets with the drafts (the old
    // exercises cascade-delete their sets). repRange/rpe are carried through so
    // existing prescriptions survive an edit round-trip.
    private func save() {
        let target: Template
        if let template {
            target = template
            target.name = name
            // Tombstone the old exercises and their sets. NOTE: this
            // replace-everything strategy is cheap locally and expensive once
            // this syncs — every save tombstones the whole subtree and inserts
            // a new one with fresh ids, so the server sees a template's
            // contents deleted and recreated on each edit. Diffing instead
            // (update in place, tombstone only what was removed) is recorded in
            // docs/04-status.md as required before the sync engine ships.
            for old in target.liveExercises {
                SoftDelete.templateExercise(old)
            }
        } else {
            // Per-folder position: a new template lands at the end of ITS
            // folder (or the unfiled list), not after every template in the store.
            let existing = (try? context.fetch(FetchDescriptor<Template>())) ?? []
            let nextOrder = existing.filter { $0.folder?.id == folder?.id }.count
            target = Template(name: name, order: nextOrder, folder: folder)
            context.insert(target)
        }

        for (exerciseOrder, draftExercise) in exercises.enumerated() {
            let tx = TemplateExercise(
                order: exerciseOrder,
                supersetGroupID: draftExercise.supersetGroupID,
                note: draftExercise.note,
                stickyNote: draftExercise.stickyNote,
                defaultRestSeconds: draftExercise.defaultRestSeconds,
                template: target,
                exercise: draftExercise.exercise
            )
            context.insert(tx)

            for (setOrder, draftSet) in draftExercise.sets.enumerated() {
                let ts = TemplateSet(
                    order: setOrder,
                    setType: draftSet.setType,
                    weight: draftSet.weight,
                    reps: draftSet.reps,
                    repRangeStart: draftSet.repRangeStart,
                    repRangeEnd: draftSet.repRangeEnd,
                    rpe: draftSet.rpe,
                    restSeconds: draftSet.restSeconds,
                    templateExercise: tx
                )
                context.insert(ts)
            }
        }

        dismiss()
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
    context.insert(TemplateSet(order: 0, weight: 225, reps: 5, restSeconds: 180, templateExercise: tx))
    context.insert(TemplateSet(order: 1, weight: 245, reps: 5, restSeconds: 180, templateExercise: tx))

    return TemplateEditorScreen(template: template)
        .modelContainer(container)
}
