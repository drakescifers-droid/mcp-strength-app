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

    // Rest timer is lifted to this owner so both the per-set progress bars and
    // the top-bar timer button can reach it. `restingSetID` identifies which
    // set's divider is currently live; the model itself carries no set info.
    @State private var restTimer = RestTimer()
    @State private var restingSetID: UUID?
    @State private var showingRestControls = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: Spacing.spacious) {
                    workoutHeaderBlock

                    ForEach(sortedExercises, id: \.id) { workoutExercise in
                        ExerciseBlock(
                            workoutExercise: workoutExercise,
                            allWorkouts: allWorkouts,
                            inProgressWorkout: workout,
                            now: now,
                            restTimer: restTimer,
                            restingSetID: restingSetID,
                            onStartRest: { setID, seconds in
                                startRest(for: setID, seconds: seconds)
                            },
                            onOpenRestControls: {
                                showingRestControls = true
                            }
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
        .sheet(isPresented: $showingRestControls) {
            RestControlsSheet(
                restTimer: $restTimer,
                now: now
            )
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
                if restingSetID != nil {
                    showingRestControls = true
                }
            } label: {
                Image(systemName: "timer")
                    .font(Typography.body)
                    .foregroundStyle(restingSetID == nil ? Theme.textSecondary : Theme.accent)
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

    // MARK: - Workout header block

    // The title strip between the top bar and the first exercise: the workout
    // name, then the start date and the running elapsed time. The name comes
    // straight from the model — this view never generates or renames it.
    private var workoutHeaderBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text(workout.name)
                .font(Typography.title)
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: Spacing.spacious) {
                Label {
                    Text(workoutDateText)
                        .font(Typography.secondary)
                        .foregroundStyle(Theme.textSecondary)
                } icon: {
                    Image(systemName: "calendar")
                        .font(Typography.secondary)
                        .foregroundStyle(Theme.textSecondary)
                }

                Label {
                    Text(formatTime(elapsedSeconds))
                        .font(Typography.secondary)
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "clock")
                        .font(Typography.secondary)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Spacing.compact)
    }

    private var workoutDateText: String {
        workout.startedAt.formatted(.dateTime.month().day().year())
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
        workout.totalVolume = WorkoutStats.totalVolume(for: workout)
        onFinish()
    }

    private func cancel() {
        context.delete(workout)
        onCancel()
    }

    /// Begin the rest countdown for the set the user just checked complete.
    /// Replaces any rest already in flight (e.g. the user checks a second set
    /// before the first rest finished).
    private func startRest(for setID: UUID, seconds: Int) {
        restingSetID = setID
        restTimer = RestTimer()
        restTimer.start(duration: TimeInterval(max(0, seconds)), at: Date())
    }
}

// MARK: - ExerciseBlock

/// One exercise's section: name, column header, the set rows with rest
/// dividers between them, and the "+ Add Set" button.
private struct ExerciseBlock: View {
    let workoutExercise: WorkoutExercise
    let allWorkouts: [Workout]
    let inProgressWorkout: Workout
    let now: Date
    let restTimer: RestTimer
    let restingSetID: UUID?
    let onStartRest: (UUID, Int) -> Void
    let onOpenRestControls: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.comfortable) {
            Text(workoutExercise.exercise?.name ?? "Unknown Exercise")
                .font(Typography.body.weight(.semibold))
                .foregroundStyle(Theme.accent)

            SetRowColumnHeader(trailingIcon: "checkmark")

            VStack(spacing: 0) {
                ForEach(Array(sortedSets.enumerated()), id: \.element.id) { index, set in
                    SetRow(
                        setType: Binding(get: { set.setType }, set: { set.setType = $0 }),
                        setNumber: workingNumbers[index],
                        previousText: previousText(for: set, position: index),
                        weight: Binding(get: { set.weight }, set: { set.weight = $0 }),
                        prescription: Binding(
                            get: { RepRange.fromWorkout(reps: set.reps) },
                            set: { newValue in
                                // A performance has a number, not a range — only
                                // .fixed (or nil) is ever written here; a range
                                // is rejected by the parser with allowRange:false.
                                set.reps = newValue.flatMap { range -> Int? in
                                    if case .fixed(let n) = range { return n }
                                    return nil
                                }
                            }
                        ),
                        allowRange: false,
                        rpe: Binding(get: { set.rpe }, set: { set.rpe = $0 }),
                        trailing: .completion(
                            isCompleted: set.isCompleted,
                            onToggle: { toggleComplete(set) }
                        )
                    )

                    if index < sortedSets.count - 1 {
                        restDividerOrBar(for: set)
                    } else {
                        // A rest after the LAST set of an exercise still counts:
                        // there is no divider below to replace, but the user
                        // still rests before moving on. Show the progress bar
                        // only when a rest is actually running for this set.
                        if isResting(set) {
                            restDividerOrBar(for: set)
                        }
                    }
                }
            }

            AddSetButton(label: "+ Add Set (\(formatTime(defaultRestSeconds)))") {
                addSet()
            }
        }
    }

    private var sortedSets: [WorkoutSet] {
        workoutExercise.sets.sorted { $0.order < $1.order }
    }

    // Working-set numbers parallel to `sortedSets`: only `.normal` sets consume
    // a number, so warm-ups / drop sets / failure sets render a letter and the
    // numbering of normal sets continues past them (docs/01-data-model.md § SetType).
    private var workingNumbers: [Int?] {
        SetNumbering.workingNumbers(for: sortedSets.map(\.setType))
    }

    private var defaultRestSeconds: Int {
        // The model default a fresh set gets (90s). Shown on the button and
        // applied to the appended set.
        90
    }

    // MARK: - Rest divider / progress bar

    /// True when this set owns the live rest countdown and the countdown is
    /// still visibly running (not yet elapsed and not skipped).
    private func isResting(_ set: WorkoutSet) -> Bool {
        restingSetID == set.id && !restTimer.isFinished(at: now)
    }

    /// Renders the divider below `set`. When that set's rest is running the
    /// thin rule is replaced by a full-width depleting progress bar; otherwise
    /// the existing thin-rule-plus-time divider is used.
    @ViewBuilder
    private func restDividerOrBar(for set: WorkoutSet) -> some View {
        if isResting(set) {
            RestProgressBar(
                timer: restTimer,
                now: now,
                onTap: onOpenRestControls
            )
        } else {
            RestDivider(restSeconds: set.restSeconds)
        }
    }

    // MARK: - Completion

    /// Toggle the set's completion and start a rest when it becomes complete.
    /// Owns the model mutation that the shared `SetRow` deliberately does not.
    private func toggleComplete(_ set: WorkoutSet) {
        set.isCompleted.toggle()
        set.completedAt = set.isCompleted ? Date() : nil
        // Starting a rest only fires when the set becomes complete —
        // unchecking does not start one.
        if set.isCompleted {
            onStartRest(set.id, set.restSeconds)
        }
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

// MARK: - PreviousText formatter

/// Pure formatter for the "Previous" column. Split out so it can be reasoned
/// about and tested independently of SwiftUI. Shared by the workout screen and
/// the template editor via the `SetRow`'s `previousText` parameter.
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
        // No load recorded — do not render a lone "(D)" / "(W)" / "(F)".
        // That would read as history when there is none.
        guard !parts.isEmpty else { return "—" }
        return parts.joined(separator: " ") + letterSuffix(for: prev.setType)
    }

    /// Suffixed only for lettered types. `.normal` is silent: most sets are
    /// normal, and the reference never tags them.
    private static func letterSuffix(for setType: SetType) -> String {
        switch setType {
        case .warmup:  return " (W)"
        case .dropSet: return " (D)"
        case .failure: return " (F)"
        case .normal:  return ""
        }
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

// MARK: - RestProgressBar

/// Replaces a set's rest divider while that set's rest countdown is running:
/// a full-width accent bar that depletes left-to-right as time runs out, with
/// the remaining time centred on it in `m:ss`. A thin light border outlines
/// it. Tapping the bar presents the timer controls.
private struct RestProgressBar: View {
    let timer: RestTimer
    let now: Date
    var onTap: () -> Void = {}

    private var remainingSeconds: Int {
        Int(timer.remaining(at: now).rounded())
    }

    var body: some View {
        GeometryReader { proxy in
            let progress = timer.progress(at: now)
            ZStack {
                // Track
                Rectangle()
                    .fill(Theme.fieldFill)
                // Accent fill depletes from the left as time runs out.
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: proxy.size.width * progress)
                    .animation(.linear(duration: 1), value: progress)
            }
            .overlay {
                Text(formatTime(remainingSeconds))
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
            }
            .overlay(
                // Thin light border.
                Rectangle()
                    .stroke(Theme.textSecondary.opacity(0.4), lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: Radius.chip))
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
        }
        .frame(height: 40)
        .padding(.vertical, Spacing.compact)
    }
}

// MARK: - RestControlsSheet

/// The timer control panel: a large Pause/Resume button, −15s / +15s, Reset,
/// and Skip. Presented from the top-bar timer button or by tapping a live
/// progress bar. Deliberately simple — a plain sheet, no alerts.
private struct RestControlsSheet: View {
    @Binding var restTimer: RestTimer
    let now: Date

    @Environment(\.dismiss) private var dismiss

    private var isPaused: Bool {
        restTimer.state == .paused
    }

    var body: some View {
        VStack(spacing: Spacing.spacious) {
            Text("Rest")
                .font(Typography.title)
                .foregroundStyle(Theme.textPrimary)

            Text(formatTime(Int(restTimer.remaining(at: now).rounded())))
                .font(Typography.title)
                .monospacedDigit()
                .foregroundStyle(Theme.accent)

            Button {
                if isPaused {
                    restTimer.resume(at: Date())
                } else {
                    restTimer.pause(at: Date())
                }
            } label: {
                Text(isPaused ? "Resume" : "Pause")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryAction)
            .frame(maxWidth: .infinity)

            HStack(spacing: Spacing.comfortable) {
                Button {
                    restTimer.adjust(by: -15, at: Date())
                } label: {
                    Text("−15s")
                }
                .buttonStyle(.tintedAccent)

                Button {
                    restTimer.adjust(by: 15, at: Date())
                } label: {
                    Text("+15s")
                }
                .buttonStyle(.tintedAccent)
            }

            Button {
                restTimer.reset(at: Date())
            } label: {
                Text("Reset")
            }
            .buttonStyle(.tintedAccent)

            Button {
                restTimer.skip()
                dismiss()
            } label: {
                Text("Skip Rest")
            }
            .buttonStyle(.tintedDestructive)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.vertical, Spacing.spacious)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .presentationDetents([.medium])
    }
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
