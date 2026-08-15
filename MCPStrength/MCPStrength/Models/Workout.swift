//
//  Workout.swift
//  MCPStrength
//

import Foundation
import SwiftData

@Model
final class Workout {
    var id: UUID
    var name: String
    var startedAt: Date
    var completedAt: Date?
    var durationSeconds: Int
    var note: String?
    var totalVolume: Double
    var prCount: Int

    var template: Template?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
    var exercises: [WorkoutExercise] = []

    init(
        id: UUID = UUID(),
        name: String,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        durationSeconds: Int = 0,
        note: String? = nil,
        totalVolume: Double = 0,
        prCount: Int = 0,
        template: Template? = nil
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationSeconds = durationSeconds
        self.note = note
        self.totalVolume = totalVolume
        self.prCount = prCount
        self.template = template
    }
}

@Model
final class WorkoutExercise {
    var id: UUID
    var order: Int
    var supersetGroupID: UUID?
    var note: String?

    var workout: Workout?
    var exercise: Exercise?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.workoutExercise)
    var sets: [WorkoutSet] = []

    init(
        id: UUID = UUID(),
        order: Int,
        supersetGroupID: UUID? = nil,
        note: String? = nil,
        workout: Workout? = nil,
        exercise: Exercise? = nil
    ) {
        self.id = id
        self.order = order
        self.supersetGroupID = supersetGroupID
        self.note = note
        self.workout = workout
        self.exercise = exercise
    }
}

@Model
final class WorkoutSet {
    var id: UUID
    var order: Int
    var setType: SetType
    var weight: Double?
    var reps: Int?
    var rpe: Double?
    var distance: Double?
    var duration: Int?
    var restSeconds: Int
    var isCompleted: Bool
    var completedAt: Date?

    var workoutExercise: WorkoutExercise?

    init(
        id: UUID = UUID(),
        order: Int,
        setType: SetType = .normal,
        weight: Double? = nil,
        reps: Int? = nil,
        rpe: Double? = nil,
        distance: Double? = nil,
        duration: Int? = nil,
        restSeconds: Int = 90,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        workoutExercise: WorkoutExercise? = nil
    ) {
        self.id = id
        self.order = order
        self.setType = setType
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.distance = distance
        self.duration = duration
        self.restSeconds = restSeconds
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.workoutExercise = workoutExercise
    }
}
