//
//  ActiveWorkoutScreen.swift
//  MCPStrength
//
//  The core screen of the product: the one a person uses standing in a gym
//  between sets. Large tap targets, obvious state, no density. Everything
//  reads from the Design layer — no raw colours or radii inline.
//

import SwiftUI
import SwiftData
import Combine

// MARK: - ActiveWorkoutScreen

/// The active workout logging screen. Owns one in-progress `Workout` and the
/// editing surface for its exercises and sets. `onFinish` / `onCancel` return
/// the caller (ContentView) to the root — this screen does not decide whether
/// the workout object survives; it only mutates it and reports.
struct ActiveWorkoutScreen: View {
    @Environment(\.modelContext) private var context

    let workout: Workout
    var onFinish: () -> Void = {}
    var onCancel: () -> Void = {}

    // All history, for the "Previous" column. Reverse-chronological sort makes
    // WorkoutHistory.previousSet's "most recent" pick cheap, and is harmless
    // when there is no history yet.
    @Query(sort: [SortDescriptor(\Workout.startedAt, order: .reverse)])
    private var allWorkouts: [Workout]

    @State private var now = Date()
    @State private var showingExercisePicker = false
    @State private var showingCancelConfirm = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: Spacing.spacious) {
                    ForEach(sortedExercises, id: \.id) { workoutExercise in
                        ExerciseBlock(
                            workoutExercise: workoutExercise,
                            allWorkouts: allWorkouts,
                            inProgressWorkout: workout
                        )
                    }

                    bottomActions
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
        .confirmationDialog(
            "Cancel this workout? Sets logged so far will be discarded.",
            isPresented: $showingCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("Cancel Workout", role: .destructive) { cancel() }
            Button("Keep Logging", role: .cancel) {}
        }
        .onReceive(ticker) { now = $0 }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.comfortable) {
            Button {
                // Live rest countdown is deliberately out of scope (see task
                // brief). The button is a real, large tap target that exists
                // for layout fidelity and future wiring.
            } label: {
                Image(systemName: "timer")
                    .font(Typography.body)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.chip))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(formatTime(elapsedSeconds))
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()

            Spacer()

            Button("Finish") { finish() }
                .buttonStyle(.primaryAction)
                .frame(maxWidth: 140)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.vertical, Spacing.compact)
    }

    // MARK: - Bottom actions

    private var bottomActions: some View {
        VStack(spacing: Spacing.comfortable) {
            Button("Add Exercises") { showingExercisePicker = true }
                .buttonStyle(.tintedAccent)

            Button("Cancel Workout") { showingCancelConfirm = true }
                .buttonStyle(.tintedDestructive)
        }
    }

    // MARK: - Derived

    private var sortedExercises: [WorkoutExercise] {
        workout.exercises.sorted { $0.order < $1.order }
    }

    private var elapsedSeconds: Int {
        max(0, Int(now.timeIntervalSince(workout.startedAt)))
    }

    // MARK: - Mutations

    private func addExercise(_ exercise: Exercise) {
        let nextOrder = (workout.exercises.map(\.order).max() ?? -1) + 1
        let workoutExercise = WorkoutExercise(order: nextOrder)
        workoutExercise.workout = workout
        workoutExercise.exercise = exercise
        context.insert(workoutExercise)

        let firstSet = WorkoutSet(order: 0)
        firstSet.workoutExercise = workoutExercise
        context.insert(firstSet)
    }

    private func finish() {
        workout.completedAt = Date()
        workout.durationSeconds = elapsedSeconds
        onFinish()
    }

    private func cancel() {
        context.delete(workout)
        onCancel()
    }
}

// MARK: - ExerciseBlock

/// One exercise's section: name, column header, the set rows with rest
/// dividers between them, and the "+ Add Set" button.
private struct ExerciseBlock: View {
    let workoutExercise: WorkoutExercise
    let allWorkouts: [Workout]
    let inProgressWorkout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.comfortable) {
            Text(workoutExercise.exercise?.name ?? "Unknown Exercise")
                .font(Typography.body.weight(.semibold))
                .foregroundStyle(Theme.accent)

            columnHeader

            VStack(spacing: 0) {
                ForEach(Array(sortedSets.enumerated()), id: \.element.id) { index, set in
                    SetRow(
                        set: set,
                        setNumber: index + 1,
                        previousText: previousText(for: set, position: index)
                    )

                    if index < sortedSets.count - 1 {
                        restDivider(restSeconds: set.restSeconds)
                    }
                }
            }

            addButton
        }
    }

    private var sortedSets: [WorkoutSet] {
        workoutExercise.sets.sorted { $0.order < $1.order }
    }

    private var addButton: some View {
        Button {
            addSet()
        } label: {
            Text("+ Add Set (\(formatTime(defaultRestSeconds)))")
                .font(Typography.body)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.compact)
                .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.button))
        }
        .buttonStyle(.plain)
    }

    private var defaultRestSeconds: Int {
        // The model default a fresh set gets (90s). Shown on the button and
        // applied to the appended set.
        90
    }

    // MARK: - Column header

    private var columnHeader: some View {
        HStack(spacing: Spacing.compact) {
            Text("Set")
                .frame(width: 28, alignment: .leading)
            Text("Previous")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("lbs")
                .frame(width: 64, alignment: .center)
            Text("Reps")
                .frame(width: 56, alignment: .center)
            Image(systemName: "checkmark")
                .frame(width: 36, alignment: .center)
        }
        .font(Typography.secondary)
        .foregroundStyle(Theme.textSecondary)
    }

    // MARK: - Rest divider

    private func restDivider(restSeconds: Int) -> some View {
        HStack(spacing: Spacing.compact) {
            Rectangle()
                .fill(Theme.fieldFill)
                .frame(height: 1)
            Text(formatTime(restSeconds))
                .font(Typography.secondary)
                .foregroundStyle(Theme.accent)
                .monospacedDigit()
            Rectangle()
                .fill(Theme.fieldFill)
                .frame(height: 1)
        }
        .padding(.vertical, Spacing.compact)
    }

    // MARK: - Previous

    private func previousText(for set: WorkoutSet, position: Int) -> String {
        guard let exercise = workoutExercise.exercise else { return "—" }
        let prev = WorkoutHistory.previousSet(
            for: exercise,
            at: position,
            in: allWorkouts,
            excluding: inProgressWorkout
        )
        return PreviousText.format(prev)
    }

    private func addSet() {
        let nextOrder = (workoutExercise.sets.map(\.order).max() ?? -1) + 1
        let newSet = WorkoutSet(order: nextOrder, restSeconds: defaultRestSeconds)
        newSet.workoutExercise = workoutExercise
        // context is shared via the environment; insert through the exercise's
        // context to keep this subview decoupled from @Environment.
        if let context = workoutExercise.modelContext {
            context.insert(newSet)
        }
    }
}

// MARK: - SetRow

/// One editable set row: badge, previous, weight chip, reps chip, check.
/// Weight/reps are held in local String state so the user can type "85."
/// without the field snapping back to "85" mid-keystroke; values commit
/// through to the model on every change that parses (or clears when empty).
private struct SetRow: View {
    let set: WorkoutSet
    let setNumber: Int
    let previousText: String

    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @State private var didSync: Bool = false

    var body: some View {
        HStack(spacing: Spacing.compact) {
            SetTypeBadge(setType: set.setType, setNumber: setNumber)
                .frame(width: 28)

            Text(previousText)
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            TextField("0", text: $weightText)
                .keyboardType(.decimalPad)
                .textInputAutocapitalization(.never)
                .foregroundStyle(Theme.textPrimary)
                .entryChipStyle()
                .frame(width: 64)
                .onChange(of: weightText) { _, newValue in commitWeight(newValue) }

            TextField("0", text: $repsText)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .foregroundStyle(Theme.textPrimary)
                .entryChipStyle()
                .frame(width: 56)
                .onChange(of: repsText) { _, newValue in commitReps(newValue) }

            checkButton
                .frame(width: 36)
        }
        .padding(.vertical, Spacing.compact)
        .onAppear { syncFromModel() }
    }

    private var checkButton: some View {
        Button {
            toggleComplete()
        } label: {
            Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(set.isCompleted ? Theme.success : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sync / commit

    private func syncFromModel() {
        guard !didSync else { return }
        didSync = true
        if let w = set.weight {
            weightText = PreviousText.formatWeight(w)
        }
        if let r = set.reps {
            repsText = String(r)
        }
    }

    private func commitWeight(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            set.weight = nil
        } else if let value = Double(trimmed) {
            set.weight = value
        }
        // Unparseable input (e.g. "85.") is left as-is locally without writing,
        // so the user can finish typing the decimal.
    }

    private func commitReps(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            set.reps = nil
        } else if let value = Int(trimmed) {
            set.reps = value
        }
    }

    private func toggleComplete() {
        set.isCompleted.toggle()
        set.completedAt = set.isCompleted ? Date() : nil
    }
}

// MARK: - PreviousText formatter

/// Pure formatter for the "Previous" column. Split out so it can be reasoned
/// about and tested independently of SwiftUI.
enum PreviousText {
    static func format(_ prev: WorkoutHistory.PreviousSet?) -> String {
        guard let prev else { return "—" }
        var parts: [String] = []
        if let w = prev.weight {
            parts.append("\(formatWeight(w)) lb")
        }
        if let r = prev.reps {
            parts.append("× \(r)")
        }
        guard !parts.isEmpty else { return "—" }
        return parts.joined(separator: " ")
    }

    /// Whole-number weights drop the trailing ".0"; otherwise show the value
    /// compactly (e.g. 85, 82.5).
    static func formatWeight(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

// MARK: - Time formatting

/// m:ss for a duration in seconds. Used by the header timer and the rest
/// dividers.
private func formatTime(_ total: Int) -> String {
    let m = max(0, total) / 60
    let s = max(0, total) % 60
    return String(format: "%d:%02d", m, s)
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Exercise.self, Workout.self, WorkoutExercise.self, WorkoutSet.self,
        configurations: config
    )
    let context = container.mainContext

    let exercise = Exercise(
        name: "Back Squat",
        bodyPart: .legs,
        category: .barbell,
        focusMetric: .totalVolume
    )
    context.insert(exercise)

    let workout = Workout(name: "Afternoon Workout", startedAt: Date())
    context.insert(workout)

    let we = WorkoutExercise(order: 0, workout: workout, exercise: exercise)
    context.insert(we)
    context.insert(WorkoutSet(order: 0, weight: 135, reps: 5, restSeconds: 90, workoutExercise: we))
    context.insert(WorkoutSet(order: 1, weight: 185, reps: 5, restSeconds: 120, workoutExercise: we))
    context.insert(WorkoutSet(order: 2, setType: .warmup, restSeconds: 90, workoutExercise: we))

    return ActiveWorkoutScreen(workout: workout)
        .modelContainer(container)
}
