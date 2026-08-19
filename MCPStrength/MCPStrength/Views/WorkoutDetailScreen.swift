//
//  WorkoutDetailScreen.swift
//  MCPStrength
//

import SwiftUI

// MARK: - WorkoutDetailScreen
//
// A read-only record of a completed workout. Shows every exercise with its full
// set list: set-type badge, weight, reps. Nothing is editable — this is what
// happened, not a logging surface. Reuses SetTypeBadge from the Design layer.

struct WorkoutDetailScreen: View {
    let workout: Workout

    /// The user's global weight unit, published by `ContentView`. The volume in
    /// the header is a whole-session number and has no exercise to take an
    /// override from, so it uses the global unit directly — unlike the set
    /// lines below, which resolve per exercise.
    @Environment(\.weightUnit) private var globalWeightUnit

    private var sortedExercises: [WorkoutExercise] {
        workout.liveExercises
    }

    var body: some View {
        ScrollView {
            // `comfortable`, not `spacious`: this is a readout, and 24pt
            // between blocks pushed a three-exercise session onto two screens.
            VStack(alignment: .leading, spacing: Spacing.comfortable) {
                header

                ForEach(sortedExercises, id: \.id) { workoutExercise in
                    ExerciseDetailBlock(workoutExercise: workoutExercise)
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.spacious)
        }
        .background(Theme.surface)
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        // NO title here. The navigation bar already shows `workout.name`, and
        // printing it again immediately underneath cost a full line at the top
        // of every history entry to say something the user just read.
        VStack(alignment: .leading, spacing: Spacing.compact) {
            HStack(spacing: Spacing.spacious) {
                Label {
                    Text(dateText)
                        .font(Typography.secondary)
                        .foregroundStyle(Theme.textSecondary)
                } icon: {
                    Image(systemName: "calendar")
                        .font(Typography.secondary)
                        .foregroundStyle(Theme.textSecondary)
                }

                Label {
                    Text(durationText)
                        .font(Typography.secondary)
                        .foregroundStyle(Theme.textSecondary)
                } icon: {
                    Image(systemName: "clock")
                        .font(Typography.secondary)
                        .foregroundStyle(Theme.textSecondary)
                }

                Label {
                    Text(volumeText)
                        .font(Typography.secondary)
                        .foregroundStyle(Theme.textSecondary)
                } icon: {
                    Image(systemName: "scalemass")
                        .font(Typography.secondary)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if let note = workout.note, !note.isEmpty {
                ExpandableNote(text: note, kind: .session)
                    .padding(.top, Spacing.compact)
            }
        }
    }

    private var dateText: String {
        let date = workout.completedAt ?? workout.startedAt
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
    }

    private var durationText: String {
        let minutes = max(0, workout.durationSeconds) / 60
        return "\(minutes)m"
    }

    private var volumeText: String {
        // `totalVolume` is stored kilogram-volume, converted with the sets it
        // was computed from (`WeightUnitMigration`). A volume scales linearly,
        // so converting the total is the same as converting every set and
        // re-summing.
        PreviousText.weightText(kilograms: workout.totalVolume, in: globalWeightUnit)
    }
}

// MARK: - ExerciseDetailBlock

/// One exercise's section: the name, then one compact line per set.
///
/// **This screen deliberately does NOT reuse `SetRowColumnHeader` or the entry
/// chips.** It did, and that was the bug: the header declares six columns
/// (Set / Previous / lbs / Reps / RPE / ✓) while the read-only row rendered
/// four values, so the weight landed under "Previous", the reps under "lbs",
/// and RPE had a heading nothing ever filled.
///
/// The deeper reason is that the logging screen's layout is shaped by things
/// history does not have: tap targets sized for a thumb, a Previous column to
/// compare against, a checkbox to hit mid-set. Borrowing it imports all of that
/// dead structure. History has one job — show what happened — so each set is
/// one self-describing line and the column headings are gone entirely.
private struct ExerciseDetailBlock: View {
    let workoutExercise: WorkoutExercise

    @Environment(\.weightUnit) private var globalWeightUnit

    /// The unit every weight in this block is shown in. Same resolution as the
    /// logging screens' blocks — see `Views/DisplayUnit.swift`.
    private var displayUnit: WeightUnit {
        WeightUnits.displayUnit(
            override: workoutExercise.exercise?.preference?.weightUnitOverride,
            global: globalWeightUnit
        )
    }

    private var sortedSets: [WorkoutSet] {
        workoutExercise.liveSets
    }

    /// Whether ANY set here can be estimated. Drives the column heading, so a
    /// bodyweight exercise gets no "1RM" label over a column of blanks.
    private var showsOneRepMax: Bool {
        guard let category = workoutExercise.exercise?.category,
              OneRepMax.supportsEstimate(category) else { return false }
        return sortedSets.contains {
            OneRepMax.estimate(for: $0, category: category, in: displayUnit) != nil
        }
    }

    // Warm-ups do not consume a working-set number (docs/01-data-model.md § SetType).
    private var workingNumbers: [Int?] {
        SetNumbering.workingNumbers(for: sortedSets.map(\.setType))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            HStack {
                Text(workoutExercise.exercise?.name ?? "Unknown Exercise")
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)

                Spacer(minLength: Spacing.compact)

                // Only headed when the column will actually hold something —
                // a "1RM" label over an empty column reads as a broken feature
                // rather than as a category that has no meaningful total load.
                if showsOneRepMax {
                    Text("1RM")
                        .font(Typography.secondary.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            // Notes are shown here because they are not only the user's — the
            // MCP server writes coaching instructions into them, and an
            // instruction you cannot read after the session is not an
            // instruction. Sticky is tinted like its pinned form during the
            // workout so the same note looks like the same note.
            if let sticky = workoutExercise.stickyNote, !sticky.isEmpty {
                ExpandableNote(text: sticky, kind: .exercise, tint: Theme.warmup)
            }
            if let note = workoutExercise.note, !note.isEmpty {
                ExpandableNote(text: note, kind: .exercise)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sortedSets.enumerated()), id: \.element.id) { index, set in
                    CompletedSetLine(
                        setType: set.setType,
                        setNumber: workingNumbers[index],
                        weight: set.weight,
                        unit: displayUnit,
                        reps: set.reps,
                        rpe: set.rpe,
                        isCompleted: set.isCompleted,
                        oneRepMax: OneRepMax.estimate(
                            for: set,
                            category: workoutExercise.exercise?.category,
                            in: displayUnit
                        )
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.comfortable)
        .padding(.vertical, Spacing.comfortable)
        .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.card))
    }
}

// MARK: - CompletedSetLine

/// One set, as a single line: badge, what was lifted, and RPE if it was recorded.
///
/// No checkbox. On a finished workout a circle is not a control — nothing can
/// be tapped — and an empty one reads as an unticked box the user is being
/// invited to fix. The done/not-done distinction still matters, so it is
/// carried by WEIGHT AND COLOUR instead of a widget: a set that was never
/// completed is dimmed and marked "skipped", which says the same thing without
/// looking like something is waiting on you.
///
/// THE WHOLE LINE takes the set type's colour, not just the badge. A warm-up is
/// orange end to end and a drop set purple, matching the reference app — at a
/// glance you read the shape of the session (two warm-ups, three working sets,
/// a drop) without parsing a small badge on every row.
private struct CompletedSetLine: View {
    let setType: SetType
    let setNumber: Int?
    /// Stored KILOGRAMS, converted for display by this view.
    let weight: Double?
    /// The unit `weight` is rendered in, and the unit `oneRepMax` is ALREADY
    /// in.
    let unit: WeightUnit
    let reps: Int?
    let rpe: Double?
    let isCompleted: Bool
    /// Already in `unit`, not kilograms — the estimate rounds to a whole unit,
    /// so it can only be computed in the unit it is displayed in. See
    /// `OneRepMax.estimate(for:category:in:)`.
    let oneRepMax: Double?

    /// The line's colour. Set type wins; an incomplete set is muted regardless,
    /// because "you did not do this" outranks "this was a drop set".
    private var lineColor: Color {
        guard isCompleted else { return Theme.textSecondary }
        switch setType {
        case .normal:  return Theme.textPrimary
        case .warmup:  return Theme.warmup
        case .dropSet: return Theme.dropSet
        case .failure: return Theme.failure
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.comfortable) {
            SetTypeBadge(setType: setType, setNumber: setNumber)
                .frame(width: 26, alignment: .leading)

            Text(performanceText)
                .font(Typography.body)
                .monospacedDigit()
                .foregroundStyle(lineColor)

            Spacer(minLength: Spacing.compact)

            if !isCompleted {
                Text("skipped")
                    .font(Typography.secondary)
                    .foregroundStyle(Theme.textSecondary)
            } else if let rpe {
                Text("RPE \(RPE.format(rpe))")
                    .font(Typography.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }

            if let oneRepMax {
                Text(PreviousText.formatWeight(oneRepMax))
                    .font(Typography.body)
                    .monospacedDigit()
                    .foregroundStyle(lineColor.opacity(0.75))
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
        .padding(.vertical, 5)
    }

    /// Self-describing on one line, so no column headings are needed.
    ///
    /// The em dash is for a set that carries no numbers at all. Showing an
    /// empty line there would read as a rendering fault rather than as "nothing
    /// was recorded" — the same reasoning as never displaying a fabricated zero.
    private var performanceText: String {
        switch (weight, reps) {
        case let (weight?, reps?):
            "\(PreviousText.weightText(kilograms: weight, in: unit)) × \(reps)"
        case let (weight?, nil):
            PreviousText.weightText(kilograms: weight, in: unit)
        case let (nil, reps?):
            reps == 1 ? "1 rep" : "\(reps) reps"
        case (nil, nil):
            "—"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WorkoutDetailScreen(
            workout: Workout(
                name: "Leg Day",
                startedAt: Date(),
                completedAt: Date(),
                durationSeconds: 3120,
                note: "Felt strong today",
                // Stored kilograms, written as the pounds it represents so the
                // preview still reads as a plausible session.
                totalVolume: WeightUnits.kilograms(from: 5400, in: .lbs)
            )
        )
    }
}
