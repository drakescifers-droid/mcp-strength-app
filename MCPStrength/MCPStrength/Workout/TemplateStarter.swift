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
    /// - Each set copies `weight`, `reps`, `setType`, and `restSeconds` as the
    ///   starting values, and `isCompleted` is forced false on every set (a
    ///   fresh performance has nothing completed yet).
    /// - `repRangeStart` / `repRangeEnd` / `rpe` are template-only prescription
    ///   fields and are NOT copied onto the workout's sets.
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
                let workoutSet = WorkoutSet(
                    order: templateSet.order,
                    setType: templateSet.setType,
                    weight: templateSet.weight,
                    reps: templateSet.reps,
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
