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

    private var sortedExercises: [WorkoutExercise] {
        workout.liveExercises
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.spacious) {
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
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text(workout.name)
                .font(Typography.title)
                .foregroundStyle(Theme.textPrimary)

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
                Text(note)
                    .font(Typography.body)
                    .foregroundStyle(Theme.textPrimary)
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
        "\(PreviousText.formatWeight(workout.totalVolume)) lb"
    }
}

// MARK: - ExerciseDetailBlock

/// One exercise's read-only section in the detail screen: name, column header,
/// and the full set list rendered as non-editable rows.
private struct ExerciseDetailBlock: View {
    let workoutExercise: WorkoutExercise

    private var sortedSets: [WorkoutSet] {
        workoutExercise.liveSets
    }

    // Working-set numbers parallel to `sortedSets`: this screen is read-only
    // history, so the type is NOT editable here — only the numbering is fixed
    // so warm-ups no longer consume a working-set slot (docs/01-data-model.md § SetType).
    private var workingNumbers: [Int?] {
        SetNumbering.workingNumbers(for: sortedSets.map(\.setType))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.comfortable) {
            Text(workoutExercise.exercise?.name ?? "Unknown Exercise")
                .font(Typography.body.weight(.semibold))
                .foregroundStyle(Theme.accent)

            SetRowColumnHeader(trailingIcon: "checkmark")

            VStack(spacing: 0) {
                ForEach(Array(sortedSets.enumerated()), id: \.element.id) { index, set in
                    ReadOnlySetRow(
                        setType: set.setType,
                        setNumber: workingNumbers[index],
                        weight: set.weight,
                        reps: set.reps,
                        isCompleted: set.isCompleted
                    )

                    if index < sortedSets.count - 1 {
                        RestDivider(restSeconds: set.restSeconds)
                    }
                }
            }
        }
        .padding(Spacing.comfortable)
        .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.card))
    }
}

// MARK: - ReadOnlySetRow

/// A non-editable set row for the detail screen: badge, weight, reps, and a
/// completion indicator. Mirrors the SetRow layout but with Text instead of
/// TextFields — nothing can be changed.
private struct ReadOnlySetRow: View {
    let setType: SetType
    let setNumber: Int?
    let weight: Double?
    let reps: Int?
    let isCompleted: Bool

    var body: some View {
        HStack(spacing: Spacing.compact) {
            SetTypeBadge(setType: setType, setNumber: setNumber)
                .frame(width: 28)

            Text(weightText)
                .font(Typography.chipValue)
                .foregroundStyle(Theme.textPrimary)
                .entryChipStyle()
                .frame(width: 64)

            Text(repsText)
                .font(Typography.chipValue)
                .foregroundStyle(Theme.textPrimary)
                .entryChipStyle()
                .frame(width: 56)

            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(isCompleted ? Theme.success : Theme.textSecondary)
                .frame(width: 36)
        }
        .padding(.vertical, Spacing.compact)
        .background(
            isCompleted ? Theme.success.opacity(0.12) : Color.clear,
            in: .rect(cornerRadius: Radius.chip)
        )
    }

    private var weightText: String {
        guard let weight else { return "" }
        return PreviousText.formatWeight(weight)
    }

    private var repsText: String {
        guard let reps else { return "" }
        return String(reps)
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
                totalVolume: 5400
            )
        )
    }
}
