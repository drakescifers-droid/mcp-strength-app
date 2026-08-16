//
//  UIPreviewFixtures.swift
//  MCPStrength
//
//  Demo content for `-uiPreview 1 -uiPreviewFixtures 1`.
//
//  An empty screen tells you almost nothing about whether a layout works. The
//  bugs this project has actually shipped were about CONTENT: misaligned
//  columns that only appear when some sets have values and others do not, a
//  note long enough to push the sets off the card, a warm-up badge next to a
//  drop set. So the fixture is deliberately awkward rather than tidy — it
//  contains the cases a happy-path demo would miss.
//
//  ## Safety
//
//  The whole file is `#if DEBUG`, so it does not exist in a Release build, and
//  it only runs when BOTH launch arguments are present. It is idempotent: it
//  checks for its own marker and does nothing on a second launch, so repeated
//  previews do not stack up duplicate workouts.
//

import Foundation
import SwiftData

#if DEBUG

enum UIPreviewFixtures {

    /// Recognisable enough that a human scrolling history knows what they are
    /// looking at, and specific enough to search for when clearing up.
    private static let marker = "Preview Session"

    static func install(in container: ModelContainer) {
        let context = ModelContext(container)

        // Idempotent. Relaunching to look at a layout must not append a second
        // copy every time.
        let existing = try? context.fetch(
            FetchDescriptor<Workout>(predicate: #Predicate { $0.name == marker })
        )
        guard (existing ?? []).isEmpty else { return }

        guard let library = try? context.fetch(FetchDescriptor<Exercise>()),
              !library.isEmpty else { return }

        func exercise(_ name: String) -> Exercise? {
            library.first { $0.name.localizedCaseInsensitiveContains(name) }
        }

        let workout = Workout(
            name: marker,
            startedAt: .now.addingTimeInterval(-3_900),
            completedAt: .now.addingTimeInterval(-600),
            durationSeconds: 3_300,
            // Long on purpose: this is the case that proves the 200-character
            // limit and the More affordance actually do something.
            note: "Deload week. Keep everything at RPE 7 and stop one short of "
                + "failure on every working set — the point is to recover, not "
                + "to test anything. If the bar speed drops, end the set.",
            summary: "Slept about five hours and it showed. Everything felt "
                + "heavier than the numbers suggest, and the gym was packed so "
                + "the rest times ran long.",
            template: nil
        )
        context.insert(workout)

        // A loaded barbell movement: warm-ups, working sets, a drop set, RPE,
        // and one skipped set — every badge and both text colours in one block.
        if let bench = exercise("Bench Press") {
            let block = WorkoutExercise(
                order: 0,
                note: "Elbows tucked, pause on the chest.",
                stickyNote: "Left shoulder — stop if it pinches.",
                workout: workout,
                exercise: bench
            )
            context.insert(block)
            let sets: [(SetType, Double, Int, Double?, Bool)] = [
                (.warmup, 95, 10, nil, true),
                (.warmup, 135, 5, nil, true),
                (.normal, 185, 8, 7, true),
                (.normal, 185, 7, 7.5, true),
                (.dropSet, 155, 6, 8, true),
                (.normal, 185, 6, nil, false),
            ]
            for (i, s) in sets.enumerated() {
                context.insert(WorkoutSet(
                    order: i, setType: s.0, weight: s.1, reps: s.2, rpe: s.3,
                    restSeconds: 120, isCompleted: s.4,
                    completedAt: s.4 ? .now : nil, workoutExercise: block
                ))
            }
        }

        // Bodyweight: the category that gets NO 1RM estimate, so the column
        // heading must be absent rather than sitting over a blank column.
        if let pull = exercise("Pull Up") {
            let block = WorkoutExercise(order: 1, workout: workout, exercise: pull)
            context.insert(block)
            for (i, reps) in [8, 7, 5].enumerated() {
                context.insert(WorkoutSet(
                    order: i, reps: reps, restSeconds: 90,
                    isCompleted: true, workoutExercise: block
                ))
            }
        }

        // High reps: above the Brzycki/Epley crossover, so the estimate comes
        // from the other formula. Worth having one visible.
        if let curl = exercise("Bicep Curl") {
            let block = WorkoutExercise(
                order: 2,
                stickyNote: "Slow negatives.",
                workout: workout,
                exercise: curl
            )
            context.insert(block)
            for (i, reps) in [15, 13, 12].enumerated() {
                context.insert(WorkoutSet(
                    order: i, weight: 35, reps: reps, restSeconds: 60,
                    isCompleted: true, workoutExercise: block
                ))
            }
        }

        workout.totalVolume = WorkoutStats.totalVolume(for: workout)
        try? context.save()
    }
}

#endif
