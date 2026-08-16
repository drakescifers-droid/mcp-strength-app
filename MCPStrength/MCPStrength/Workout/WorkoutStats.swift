//
//  WorkoutStats.swift
//  MCPStrength
//

import Foundation

// MARK: - WorkoutStats
//
// Pure, side-effect-free calculations over workout data. Lifted out of the view
// layer so they can be reasoned about and tested directly — the same pattern as
// WorkoutHistory. Takes plain model objects, never a ModelContext.

enum WorkoutStats {

    // MARK: - Best set

    /// A snapshot of the best set found among an exercise's completed sets.
    struct BestSet: Equatable, Sendable {
        let weight: Double
        let reps: Int
    }

    /// Among `workoutExercise`'s COMPLETED sets, the one with the highest
    /// `weight × reps`. Ties break toward the heavier weight. Sets with no
    /// weight or no reps are ignored. Returns `nil` when no qualifying set
    /// exists.
    static func bestSet(for workoutExercise: WorkoutExercise) -> BestSet? {
        let candidates = workoutExercise.liveSets
            .filter(\.isCompleted)
            .compactMap { set -> (weight: Double, reps: Int, volume: Double)? in
                guard let weight = set.weight, let reps = set.reps else { return nil }
                return (weight: weight, reps: reps, volume: weight * Double(reps))
            }

        guard let best = candidates.max(by: { lhs, rhs in
            if lhs.volume != rhs.volume { return lhs.volume < rhs.volume }
            return lhs.weight < rhs.weight
        }) else { return nil }

        return BestSet(weight: best.weight, reps: best.reps)
    }

    /// The best set of an exercise that carries NO WEIGHT — pull-ups, crunches,
    /// anything reps-only. Most reps wins.
    ///
    /// This exists because `bestSet` requires both weight AND reps, so a
    /// bodyweight exercise returned nil and the history card dropped the row
    /// ENTIRELY: three sets of pull-ups logged, and the session summary did not
    /// mention them. Found by looking at the screen, which is the only way this
    /// class of bug ever gets found — it needs content of a shape the happy
    /// path does not produce.
    static func bestRepCount(for workoutExercise: WorkoutExercise) -> Int? {
        workoutExercise.liveSets
            .filter(\.isCompleted)
            .compactMap(\.reps)
            .max()
    }

    // MARK: - Total volume

    /// Sum of `weight × reps` over `workout`'s COMPLETED, LIVE sets only. An
    /// unchecked set was not performed and does not count; nor does a deleted
    /// one, which would otherwise keep inflating a total after removal. Sets missing weight
    /// or reps are skipped. Returns `0` for a workout with no completed sets
    /// — never nil, never a crash.
    static func totalVolume(for workout: Workout) -> Double {
        workout.liveExercises
            .flatMap(\.liveSets)
            .filter(\.isCompleted)
            .compactMap { set -> Double? in
                guard let weight = set.weight, let reps = set.reps else { return nil }
                return weight * Double(reps)
            }
            .reduce(0, +)
    }

    // MARK: - History filtering

    /// Completed workouts only (completedAt != nil), newest first. This is the
    /// data source for the history screen — an in-progress workout is excluded
    /// because showing it in history would misrepresent what was performed.
    static func completedWorkouts(from workouts: [Workout]) -> [Workout] {
        workouts
            .filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
}
