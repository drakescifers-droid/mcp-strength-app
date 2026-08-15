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

    /// All history, for the "Previous" column — reused exactly as on the
    /// workout screen (see Views/WorkoutHistory.swift).
    @Query(sort: [SortDescriptor(\Workout.startedAt, order: .reverse)])
    private var allWorkouts: [Workout]

    @State private var name: String = ""
    @State private var exercises: [DraftExercise] = []
    @State private var showingExercisePicker = false

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
            Text(draft.exercise.name)
                .font(Typography.body.weight(.semibold))
                .foregroundStyle(Theme.accent)

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
                        RestDivider(restSeconds: set.restSeconds)
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
            exercises = template.exercises
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
                        sets: tx.sets
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
            // Remove old exercises (their sets cascade-delete).
            for old in target.exercises {
                context.delete(old)
            }
        } else {
            let nextOrder = (try? context.fetchCount(FetchDescriptor<Template>())) ?? 0
            target = Template(name: name, order: nextOrder)
            context.insert(target)
        }

        for (exerciseOrder, draftExercise) in exercises.enumerated() {
            let tx = TemplateExercise(
                order: exerciseOrder,
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
