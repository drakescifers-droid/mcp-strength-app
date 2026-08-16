//
//  HistoryScreen.swift
//  MCPStrength
//

import SwiftUI
import SwiftData

// MARK: - HistoryScreen
//
// The workout history list. Completed workouts grouped into month sections
// (newest first), each rendered as a card with the workout name, date, stats,
// note, and a per-exercise best-set table. In-progress workouts are excluded
// — they have not been performed yet.

struct HistoryScreen: View {
    @Query(filter: #Predicate<Workout> { $0.deletedAt == nil },
           sort: [SortDescriptor(\Workout.completedAt, order: .reverse)])
    private var allWorkouts: [Workout]

    private var workouts: [Workout] {
        WorkoutStats.completedWorkouts(from: allWorkouts)
    }

    private var monthSections: [(key: DateComponents, workouts: [Workout])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: workouts) { workout in
            calendar.dateComponents([.year, .month], from: workout.completedAt ?? workout.startedAt)
        }
        return grouped
            .map { (key: $0.key, workouts: $0.value) }
            .sorted { lhs, rhs in
                if lhs.key.year != rhs.key.year { return (lhs.key.year ?? 0) > (rhs.key.year ?? 0) }
                return (lhs.key.month ?? 0) > (rhs.key.month ?? 0)
            }
    }

    var body: some View {
        Group {
            if workouts.isEmpty {
                emptyState
            } else {
                workoutList
            }
        }
        .background(Theme.surface)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Workout list

    private var workoutList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.comfortable, pinnedViews: [.sectionHeaders]) {
                ForEach(monthSections, id: \.key) { section in
                    Section {
                        ForEach(section.workouts, id: \.id) { workout in
                            NavigationLink {
                                WorkoutDetailScreen(workout: workout)
                            } label: {
                                WorkoutHistoryCard(workout: workout)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        monthHeader(for: section.key)
                    }
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.spacious)
        }
    }

    // MARK: - Month header

    private func monthHeader(for components: DateComponents) -> some View {
        let calendar = Calendar.current
        let date = calendar.date(from: components) ?? Date()
        let title = date
            .formatted(.dateTime.month(.wide).year())
            .uppercased()

        return Text(title)
            .font(Typography.secondary.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.comfortable)
            .padding(.bottom, Spacing.compact)
            .background(Theme.surface)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Spacing.comfortable) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textSecondary)

            Text("No Workouts Yet")
                .font(Typography.title)
                .foregroundStyle(Theme.textPrimary)

            Text("Completed workouts will appear here.")
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - WorkoutHistoryCard

/// A single completed workout rendered as a rounded card: name, date, stats
/// (duration + total volume), optional note, and a best-set table.
private struct WorkoutHistoryCard: View {
    let workout: Workout

    private var sortedExercises: [WorkoutExercise] {
        workout.liveExercises
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.comfortable) {
            header
            statsRow
            if let note = workout.note, !note.isEmpty {
                Text(note)
                    .font(Typography.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            bestSetTable
        }
        .padding(Spacing.comfortable)
        .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .stroke(Theme.textSecondary.opacity(0.2), lineWidth: 1)
        )
        .contentShape(.rect(cornerRadius: Radius.card))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.compact / 2) {
            Text(workout.name)
                .font(Typography.title)
                .foregroundStyle(Theme.textPrimary)

            Text(dateText)
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var dateText: String {
        let date = workout.completedAt ?? workout.startedAt
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: Spacing.spacious) {
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
    }

    private var durationText: String {
        let minutes = max(0, workout.durationSeconds) / 60
        return "\(minutes)m"
    }

    private var volumeText: String {
        "\(PreviousText.formatWeight(workout.totalVolume)) lb"
    }

    // MARK: - Best set table

    private var bestSetTable: some View {
        let rows = sortedExercises.compactMap { exercise -> (exercise: WorkoutExercise, best: WorkoutStats.BestSet)? in
            guard let best = WorkoutStats.bestSet(for: exercise) else { return nil }
            return (exercise, best)
        }

        return VStack(spacing: 0) {
            tableHeader

            ForEach(rows, id: \.exercise.id) { row in
                tableRow(for: row.exercise, best: row.best)
            }
        }
    }

    private var tableHeader: some View {
        HStack {
            Text("Exercise")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Best Set")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(Typography.secondary)
        .foregroundStyle(Theme.textSecondary)
        .padding(.bottom, Spacing.compact)
    }

    private func tableRow(for workoutExercise: WorkoutExercise, best: WorkoutStats.BestSet) -> some View {
        let exerciseName = workoutExercise.exercise?.name ?? "Unknown Exercise"
        let setCount = workoutExercise.liveSets.count
        let bestText = PreviousText.format(.init(weight: best.weight, reps: best.reps))

        return HStack {
            Text("\(setCount) × \(exerciseName)")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(bestText)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(Typography.body)
        .foregroundStyle(Theme.textPrimary)
        .padding(.vertical, Spacing.compact / 2)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HistoryScreen()
    }
    .modelContainer(for: [
        Exercise.self,
        TemplateFolder.self,
        Template.self,
        TemplateExercise.self,
        TemplateSet.self,
        ProgramDay.self,
        Workout.self,
        WorkoutExercise.self,
        WorkoutSet.self,
    ], inMemory: true)
}
