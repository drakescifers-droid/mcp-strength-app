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
    /// Set when Finish would throw away sets that have values typed in them.
    /// `.alert(item:)`-shaped for the same reason sheets are: the value and the
    /// presentation cannot disagree.
    @State private var pendingDiscard: WorkoutFinishing.DiscardSummary?

    /// Which option sheet is open, and for which exercise. Holds the EXERCISE,
    /// not an index: this screen's list can be reordered mid-session, and an
    /// index would silently start pointing at a different exercise.
    @State private var activeOption: ActiveOption?

    /// Whether the session-note editor is open.
    @State private var editingWorkoutNote = false

    struct ActiveOption: Identifiable {
        enum Kind { case note, stickyNote, rest, replace }
        let id = UUID()
        let exercise: WorkoutExercise
        let kind: Kind
    }

    /// Which set's own rest is being edited, opened by tapping its divider.
    /// Holds the SET rather than an index for the same reason `ActiveOption`
    /// holds the exercise: this list reorders mid-session.
    @State private var editingSetRest: SetRestEdit?

    struct SetRestEdit: Identifiable {
        let id = UUID()
        let set: WorkoutSet
    }

    @Environment(\.modelContext) private var context

    let workout: Workout
    var onFinish: () -> Void = {}
    var onCancel: () -> Void = {}

    // All history, for the "Previous" column. Reverse-chronological sort makes
    // WorkoutHistory.previousSet's "most recent" pick cheap, and is harmless
    // when there is no history yet.
    @Query(filter: #Predicate<Workout> { $0.deletedAt == nil },
           sort: [SortDescriptor(\Workout.startedAt, order: .reverse)])
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

    // Non-nil while an exercise title is being dragged. Every block
    // collapses to its title row so the user can actually see (and
    // drop onto) exercises that would otherwise be two screens of
    // sets away.
    @State private var draggingExerciseID: UUID?

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
                            isCollapsed: isReordering,
                            onReorderLift: { draggingExerciseID = workoutExercise.id },
                            onReorderEnded: { draggingExerciseID = nil },
                            onStartRest: { setID, seconds in
                                startRest(for: setID, seconds: seconds)
                            },
                            onOpenRestControls: {
                                showingRestControls = true
                            },
                            onOption: { option in
                                handleOption(option, for: workoutExercise)
                            },
                            onEditRest: { set in
                                editingSetRest = SetRestEdit(set: set)
                            }
                        )
                        .dropDestination(for: String.self) { items, _ in
                            handleExerciseDrop(items, onto: workoutExercise)
                        } isTargeted: { targeted in
                            // Payload isn't readable until drop. Any non-nil
                            // id is enough to collapse the list.
                            if targeted, draggingExerciseID == nil {
                                draggingExerciseID = workoutExercise.id
                            }
                        }
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
        .sheet(item: $activeOption) { option in
            optionSheet(for: option)
        }
        .sheet(item: $editingSetRest) { edit in
            RestTimerSheet(scope: .oneSet, current: edit.set.restSeconds) {
                edit.set.restSeconds = $0
                edit.set.markEdited()
            }
        }
        .sheet(isPresented: $editingWorkoutNote) {
            ExerciseNoteSheet(
                isSticky: false,
                exerciseName: workout.name,
                initialText: workout.note
            ) {
                workout.note = $0
                workout.markEdited()
            }
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
        // Driven BY the value, not by a separate flag: `presenting:` takes the
        // summary itself, so the alert and the thing it describes cannot
        // disagree. Same reasoning as .sheet(item:) in docs/04-status.md.
        .alert(
            "Discard unfinished sets?",
            isPresented: Binding(
                get: { pendingDiscard != nil },
                set: { if !$0 { pendingDiscard = nil } }
            ),
            presenting: pendingDiscard
        ) { _ in
            Button("Discard and Finish", role: .destructive) { commitFinish() }
            Button("Keep Logging", role: .cancel) { pendingDiscard = nil }
        } message: { summary in
            Text(discardMessage(for: summary))
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
            // The header DISPLAYS the session note; the button to write one
            // lives at the bottom, next to Finish. Two entry points for the
            // same field would be clutter, and the bottom is where the note
            // actually gets written.
            Text(workout.name)
                .font(Typography.title)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let note = workout.note, !note.isEmpty {
                ExpandableNote(text: note, kind: .session)
            }

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
        // Same 0.4 the rest-progress border already uses — dim the
        // chrome so only the collapsed title rows read as drop targets.
        .opacity(isReordering ? 0.4 : 1)
    }

    private var workoutDateText: String {
        workout.startedAt.formatted(.dateTime.month().day().year())
    }

    // MARK: - Bottom actions

    private var bottomActions: some View {
        VStack(spacing: Spacing.comfortable) {
            Button("Add Exercises") { showingExercisePicker = true }
                .buttonStyle(.tintedAccent)

            // A SUMMARY note belongs here, not at the top. It is written at the
            // END of a session — "slept badly", "gym was packed, rushed the
            // last two" — so the entry point sits where the thumb already is
            // when finishing, immediately above Cancel and a scroll from
            // Finish. Putting it in the header meant scrolling back up to write
            // the one thing you only know once you are done.
            Button(hasSessionNote ? "Edit Workout Note" : "Add Workout Note") {
                editingWorkoutNote = true
            }
            .buttonStyle(.tintedAccent)

            Button("Cancel Workout") { showingCancelConfirm = true }
                .buttonStyle(.tintedDestructive)
        }
        .opacity(isReordering ? 0.4 : 1)
    }

    private var hasSessionNote: Bool {
        !(workout.note ?? "").isEmpty
    }

    // MARK: - Derived

    private var sortedExercises: [WorkoutExercise] {
        workout.liveExercises
    }

    private var isReordering: Bool { draggingExerciseID != nil }

    private var elapsedSeconds: Int {
        max(0, Int(now.timeIntervalSince(workout.startedAt)))
    }

    // MARK: - Mutations

    private func addExercise(_ exercise: Exercise) {
        let nextOrder = (workout.liveExercises.map(\.order).max() ?? -1) + 1
        let workoutExercise = WorkoutExercise(order: nextOrder)
        workoutExercise.workout = workout
        workoutExercise.exercise = exercise
        context.insert(workoutExercise)

        let firstSet = WorkoutSet(order: 0)
        firstSet.workoutExercise = workoutExercise
        context.insert(firstSet)
    }

    /// Tapping Finish. Asks first ONLY when there is something to lose.
    ///
    /// Unticked sets are discarded on finish (WorkoutFinishing explains why),
    /// and that destroys numbers the user may have typed and simply forgotten
    /// to tick. Confirming every finish would be nagging; confirming none of
    /// them loses a set to a mis-tap. So the prompt appears only when a doomed
    /// set actually has values in it.
    // MARK: - Exercise options

    /// The same menu as the template editor, answered differently: this screen
    /// edits PERSISTED models, so every change marks the row for sync and a
    /// removal is a soft delete rather than dropping an array element.
    private func handleOption(_ option: ExerciseOption, for exercise: WorkoutExercise) {
        switch option {
        case .addNote:
            activeOption = ActiveOption(exercise: exercise, kind: .note)
        case .addStickyNote:
            activeOption = ActiveOption(exercise: exercise, kind: .stickyNote)
        case .updateRestTimers:
            activeOption = ActiveOption(exercise: exercise, kind: .rest)
        case .replaceExercise:
            activeOption = ActiveOption(exercise: exercise, kind: .replace)
        case .createSuperset:
            toggleSuperset(for: exercise)
        case .removeExercise:
            // Soft, unlike the discard at Finish. This row may already exist on
            // the server if the workout was finished and reopened, and the
            // cascade to its sets has to propagate either way.
            SoftDelete.workoutExercise(exercise)
        }
    }

    /// Pair with the exercise ABOVE, or leave the current group. See the
    /// template editor's copy for the reasoning — a superset is round-robin in
    /// list order, so "join the one before me" is the only rule that needs no
    /// second selection UI.
    private func toggleSuperset(for exercise: WorkoutExercise) {
        let ordered = workout.liveExercises
        guard let index = ordered.firstIndex(where: { $0.id == exercise.id }) else { return }

        if exercise.supersetGroupID != nil {
            exercise.supersetGroupID = nil
            exercise.markEdited()
            return
        }
        guard index > 0 else { return }
        let previous = ordered[index - 1]
        let group = previous.supersetGroupID ?? UUID()
        previous.supersetGroupID = group
        previous.markEdited()
        exercise.supersetGroupID = group
        exercise.markEdited()
    }

    @ViewBuilder
    private func optionSheet(for option: ActiveOption) -> some View {
        let exercise = option.exercise
        let name = exercise.exercise?.name ?? "Exercise"
        switch option.kind {
        case .note:
            ExerciseNoteSheet(isSticky: false, exerciseName: name, initialText: exercise.note) {
                exercise.note = $0
                exercise.markEdited()
            }
        case .stickyNote:
            ExerciseNoteSheet(isSticky: true, exerciseName: name, initialText: exercise.stickyNote) {
                exercise.stickyNote = $0
                exercise.markEdited()
            }
        case .rest:
            RestTimerSheet(
                scope: .newSets(exerciseName: name),
                current: exercise.defaultRestSeconds
            ) {
                exercise.defaultRestSeconds = $0
                exercise.markEdited()
            }
        case .replace:
            ExercisesScreen(onSelect: { picked in
                exercise.exercise = picked
                exercise.markEdited()
                activeOption = nil
            })
        }
    }

    private func finish() {
        let summary = WorkoutFinishing.discardSummary(for: workout)
        if summary.hasEnteredValues {
            pendingDiscard = summary
        } else {
            commitFinish()
        }
    }

    /// Names what is about to be lost, specifically. "Some sets weren't
    /// completed" is a shrug; "2 sets on Barbell Row" is something the user can
    /// check against what they remember doing.
    private func discardMessage(for summary: WorkoutFinishing.DiscardSummary) -> String {
        let sets = summary.setCount == 1 ? "1 set has" : "\(summary.setCount) sets have"
        var text = "\(sets) weights or reps typed in but were never ticked off. "
        if summary.exerciseCount == 1 {
            text += "1 exercise will be removed from this workout. "
        } else if summary.exerciseCount > 1 {
            text += "\(summary.exerciseCount) exercises will be removed from this workout. "
        }
        return text + "Finishing keeps only the sets you completed."
    }

    private func commitFinish() {
        pendingDiscard = nil
        WorkoutFinishing.finish(workout, elapsedSeconds: elapsedSeconds, in: context)
        onFinish()
    }

    private func cancel() {
        // A REAL delete, and now provably safe. An unfinished workout is not
        // eligible to push (PushFilter.shouldPush), so a cancelled one has
        // never reached the server and there is nothing out there for a
        // tombstone to propagate to. Keeping one would store — and later
        // upload — a record of a workout that never happened.
        //
        // This was a soft delete until the "only finished workouts sync" rule
        // existed, because nothing could then PROVE the workout had not been
        // pushed. The rule turned a guess into a guarantee.
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

    /// Drop onto an exercise row: insert at that row's position after the
    /// dragged id has been removed (the ListOrdering index convention).
    /// Same-list — source and destination are the workout's ordered ids.
    private func handleExerciseDrop(_ items: [String], onto target: WorkoutExercise) -> Bool {
        defer { draggingExerciseID = nil }
        guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
        if id == target.id { return true }

        let ids = sortedExercises.map(\.id)
        var dest = ids
        dest.removeAll { $0 == id }
        guard let index = dest.firstIndex(of: target.id) else { return false }

        let result = ListOrdering.move(id, from: ids, to: ids, at: index)
        let byID = Dictionary(uniqueKeysWithValues: workout.liveExercises.map { ($0.id, $0) })
        for (i, eid) in result.destination.enumerated() {
            byID[eid]?.order = i
            byID[eid]?.markEdited()
        }
        return true
    }
}

// MARK: - ExerciseBlock

/// One exercise's section: name, column header, the set rows with rest
/// dividers between them, and the "+ Add Set" button. While a reorder
/// drag is active the block collapses to the title row — a full set
/// list is taller than the screen, so without collapsing you cannot
/// drop onto an exercise two screens away.
private struct ExerciseBlock: View {
    let workoutExercise: WorkoutExercise
    let allWorkouts: [Workout]
    let inProgressWorkout: Workout
    let now: Date
    let restTimer: RestTimer
    let restingSetID: UUID?
    let isCollapsed: Bool
    var onReorderLift: () -> Void = {}
    var onReorderEnded: () -> Void = {}
    let onStartRest: (UUID, Int) -> Void
    let onOpenRestControls: () -> Void
    /// The menu selection, handled by the screen — this block owns no
    /// behaviour of its own.
    var onOption: (ExerciseOption) -> Void = { _ in }
    /// A rest divider was tapped. Handled by the screen for the same reason.
    var onEditRest: (WorkoutSet) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.comfortable) {
            // The name is still the DRAG HANDLE — long-pressing it starts a
            // reorder — so the menu button sits beside it rather than inside
            // it. Putting a Menu inside a `.draggable` makes the two gestures
            // fight: a long press has to be either a lift or a menu.
            HStack(spacing: Spacing.compact) {
                Text(workoutExercise.exercise?.name ?? "Unknown Exercise")
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .draggable(workoutExercise.id.uuidString) {
                        Text(workoutExercise.exercise?.name ?? "Unknown Exercise")
                            .font(Typography.body.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .onAppear(perform: onReorderLift)
                            .onDisappear(perform: onReorderEnded)
                    }

                // Hidden while reordering: the whole point of the collapse is
                // to get the list small enough to drag across, and a row of
                // menu buttons is noise you cannot tap mid-drag anyway.
                if !isCollapsed {
                    ExerciseOptionsMenu(
                        hasNote: !(workoutExercise.note ?? "").isEmpty,
                        hasStickyNote: !(workoutExercise.stickyNote ?? "").isEmpty,
                        isInSuperset: workoutExercise.supersetGroupID != nil,
                        onSelect: { onOption($0) }
                    )
                }
            }

            // A sticky note is pinned BELOW the name and stays visible while
            // logging — that is the entire difference between it and a note,
            // which lives behind the menu.
            if let sticky = workoutExercise.stickyNote, !sticky.isEmpty, !isCollapsed {
                ExpandableNote(text: sticky, kind: .exercise, tint: Theme.warmup)
            }

            if !isCollapsed {
                SetRowColumnHeader(trailingIcon: "checkmark")

                VStack(spacing: 0) {
                    ForEach(Array(sortedSets.enumerated()), id: \.element.id) { index, set in
                        SetRow(
                            setType: Binding(get: { set.setType }, set: { set.setType = $0; set.markEdited() }),
                            setNumber: workingNumbers[index],
                            previousText: previousText(for: set, position: index),
                            weight: Binding(get: { set.weight }, set: { set.weight = $0; set.markEdited() }),
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
                                    set.markEdited()
                                }
                            ),
                            allowRange: false,
                            rpe: Binding(get: { set.rpe }, set: { set.rpe = $0; set.markEdited() }),
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
    }

    private var sortedSets: [WorkoutSet] {
        workoutExercise.liveSets
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
            RestDivider(restSeconds: set.restSeconds) { onEditRest(set) }
        }
    }

    // MARK: - Completion

    /// Toggle the set's completion and start a rest when it becomes complete.
    /// Owns the model mutation that the shared `SetRow` deliberately does not.
    private func toggleComplete(_ set: WorkoutSet) {
        set.isCompleted.toggle()
        set.completedAt = set.isCompleted ? Date() : nil
        set.markEdited()
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
        let nextOrder = (workoutExercise.liveSets.map(\.order).max() ?? -1) + 1
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
