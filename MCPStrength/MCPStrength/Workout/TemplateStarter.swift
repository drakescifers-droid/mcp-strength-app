//
//  TemplateStarter.swift
//  MCPStrength
//
//  Starting a workout from a template. The naming rule (docs/01-data-model.md
//  § Workouts, corrected once already): a workout started from a template
//  takes the TEMPLATE's name, copied onto `Workout.name` at start. The
//  generated time-of-day name is ONLY for quick workouts with no template.
//
//  `name` is stored on the Workout, never read through the `template`
//  relationship — so renaming or deleting a template later never rewrites the
//  history of workouts already performed from it.
//

import Foundation
import SwiftData

enum TemplateStarter {

    /// Create a new `Workout` by copying `template`'s exercises and sets.
    ///
    /// - The workout's `name` is the template's name, copied at start.
    /// - `Workout.template` is set so the relationship is recorded.
    /// - Each set copies `weight`, `setType`, and `restSeconds`, and `rpe`
    ///   (the prescribed effort target), and `isCompleted` is forced false on
    ///   every set (a fresh performance has nothing completed yet).
    /// - `reps` is pre-filled as follows: if the template set has a fixed
    ///   `reps`, copy it unchanged; if it has a RANGE instead, pre-fill `reps`
    ///   with `repRangeStart` — the BOTTOM of the range, where a lifter starts
    ///   before adjusting up through the range as the set progresses.
    ///   `WorkoutSet` deliberately has no range field (a plan has a range; a
    ///   performance has a number — docs/01 § Prescribed effort), so the range
    ///   itself is NOT copied, only the starting number is.
    /// - `repRangeEnd` is template-only and is NOT copied onto the workout.
    @discardableResult
    static func start(
        from template: Template,
        at date: Date = Date(),
        in context: ModelContext
    ) -> Workout {
        let workout = Workout(name: template.name, startedAt: date, template: template)
        context.insert(workout)

        for templateExercise in template.exercises.sorted(by: { $0.order < $1.order }) {
            let workoutExercise = WorkoutExercise(
                order: templateExercise.order,
                workout: workout,
                exercise: templateExercise.exercise
            )
            context.insert(workoutExercise)

            for templateSet in templateExercise.sets.sorted(by: { $0.order < $1.order }) {
                // Fixed reps wins; otherwise fall back to the bottom of a range.
                let prefillReps = templateSet.reps ?? templateSet.repRangeStart
                let workoutSet = WorkoutSet(
                    order: templateSet.order,
                    setType: templateSet.setType,
                    weight: templateSet.weight,
                    reps: prefillReps,
                    rpe: templateSet.rpe,
                    restSeconds: templateSet.restSeconds,
                    isCompleted: false,
                    workoutExercise: workoutExercise
                )
                context.insert(workoutSet)
            }
        }

        return workout
    }
}
