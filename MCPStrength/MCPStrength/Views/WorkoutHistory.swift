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

    /// A snapshot of a previously-logged set's load. `nil` weight/reps mean
    /// that value was not recorded. `setType` is carried so the Previous
    /// column can tell a drop set from a working set at the same numbers.
    struct PreviousSet: Equatable, Sendable {
        let weight: Double?
        let reps: Int?
        let setType: SetType

        /// `setType` defaults to `.normal` so call sites we do not own
        /// (HistoryScreen best-set text, existing tests) keep compiling.
        /// A defaulted `let` is omitted from the synthesized memberwise
        /// init, so this is spelled out.
        init(weight: Double?, reps: Int?, setType: SetType = .normal) {
            self.weight = weight
            self.reps = reps
            self.setType = setType
        }
    }

    /// Find the weight × reps for the set at `position` of `exercise`, taken
    /// from the most recent COMPLETED workout that is NOT the in-progress one.
    ///
    /// **`position` counts within a KIND — warm-ups match warm-ups, everything
    /// else matches the working sequence — and both sides have to agree or the
    /// column lies.** `SetNumbering.positionsWithinKind` is what a caller uses
    /// to derive it; the filter below is the other half. `like` is the row's
    /// own set type and selects which sequence to read.
    ///
    /// Kind matters because `Add Warm-up Sets` inserts rows at the top of a
    /// list, and matching on raw position meant a generated ramp took the
    /// previous working load off the working set and displayed it against a
    /// warm-up. The reasoning lives with the rule, in `SetNumbering`.
    ///
    /// `like` defaults to `.normal` — the working sequence — because that is
    /// what a caller with no particular row in hand means.
    ///
    /// Returns `nil` when there is no qualifying history or no set at that
    /// position. The in-progress workout is excluded even if it happens to be
    /// passed in, and so is anything tombstoned — a deleted exercise must not
    /// come back as the weight you are told you lifted last time.
    static func previousSet(
        for exercise: Exercise,
        at position: Int,
        like setType: SetType = .normal,
        in workouts: [Workout],
        excluding inProgress: Workout? = nil
    ) -> PreviousSet? {
        let candidates = workouts
            .filter { $0.completedAt != nil }
            .filter { $0.id != inProgress?.id }
            .filter { workout in
                workout.liveExercises.contains { $0.exercise?.id == exercise.id }
            }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        guard let mostRecent = candidates.first,
              let workoutExercise = mostRecent.liveExercises
                .first(where: { $0.exercise?.id == exercise.id })
        else { return nil }

        // The history side of the kind match. A ramp logged last time must not
        // shift what the working rows report, for the same reason a ramp added
        // today must not — and a warm-up row reads last time's warm-ups rather
        // than nothing, which is what the reference app shows.
        let wantWarmup = (setType == .warmup)
        let sortedSets = workoutExercise.liveSets.filter { ($0.setType == .warmup) == wantWarmup }
        guard position >= 0, position < sortedSets.count else { return nil }
        let set = sortedSets[position]
        return PreviousSet(weight: set.weight, reps: set.reps, setType: set.setType)
    }
}
