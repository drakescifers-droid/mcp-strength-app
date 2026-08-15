//
//  WorkoutHistory.swift
//  MCPStrength
//

import Foundation

// MARK: - WorkoutHistory
//
// Pure, side-effect-free lookup of "what did the user lift for this set last time".
//
// This is deliberately lifted out of any view body because it reads real history
// and is the easiest thing in the screen to get silently wrong. It takes plain
// arrays/values, never a ModelContext, so it is trivially unit-testable.

enum WorkoutHistory {

    /// A snapshot of a previously-logged set's load. `nil` fields mean that
    /// value was not recorded for that set.
    struct PreviousSet: Equatable, Sendable {
        let weight: Double?
        let reps: Int?
    }

    /// Find the weight × reps for the set at `position` (0-based, in order) of
    /// `exercise`, taken from the most recent COMPLETED workout that is NOT the
    /// in-progress one.
    ///
    /// Returns `nil` when there is no qualifying history or no set at that
    /// position. The in-progress workout is excluded even if it happens to be
    /// passed in.
    static func previousSet(
        for exercise: Exercise,
        at position: Int,
        in workouts: [Workout],
        excluding inProgress: Workout? = nil
    ) -> PreviousSet? {
        let candidates = workouts
            .filter { $0.completedAt != nil }
            .filter { $0.id != inProgress?.id }
            .filter { workout in
                workout.exercises.contains { $0.exercise?.id == exercise.id }
            }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        guard let mostRecent = candidates.first,
              let workoutExercise = mostRecent.exercises
                .first(where: { $0.exercise?.id == exercise.id })
        else { return nil }

        let sortedSets = workoutExercise.sets.sorted { $0.order < $1.order }
        guard position >= 0, position < sortedSets.count else { return nil }
        let set = sortedSets[position]
        return PreviousSet(weight: set.weight, reps: set.reps)
    }
}
