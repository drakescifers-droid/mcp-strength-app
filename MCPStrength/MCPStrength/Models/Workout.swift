//
//  Workout.swift
//  MCPStrength
//

import Foundation
import SwiftData

@Model
final class Workout {
    var id: UUID

    // MARK: Sync metadata
    //
    // Three columns, mirroring the server. The DEFAULTS are the load-bearing
    // part and the reasoning is in Sync/Syncable.swift — in short: declaration
    // -level defaults so SwiftData can lightweight-migrate an existing store,
    // and `needsSync = true` so a migrated or newly created row is PUSHED
    // rather than silently assumed clean.

    /// Wall-clock time of the last local edit. The last-write-wins key.
    var updatedAt: Date = Date.distantPast
    /// Tombstone. Non-nil means deleted; the row stays so the delete can reach
    /// devices that were offline when it happened.
    var deletedAt: Date?
    /// Has local changes the server has not confirmed.
    var needsSync: Bool = true
    var name: String
    var startedAt: Date
    var completedAt: Date?
    var durationSeconds: Int

    // MARK: The two workout-level notes
    //
    // They are NOT two entry points to one field. They differ in author,
    // direction and moment, and collapsing them would leave an AI reading
    // history unable to tell its own instruction from the user's report of how
    // it went — poisoning the judgement both exist to support.
    //
    //   note    — INSTRUCTIONS GOING IN. Written by the plan (copied from
    //             Template.note when a workout starts) or by the MCP server.
    //             Read before and during: "focus on tempo, you are deloading".
    //   summary — FEEDBACK COMING OUT. Written by the user at the end, read
    //             later by the AI: "slept badly, everything felt heavy". This
    //             is what distinguishes a bad night from a downward trend.

    /// Instructions for this session. Carried from the template at start.
    var note: String?
    /// The user's closing note about how the session went.
    var summary: String? 
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
        summary: String? = nil,
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
        self.summary = summary
        self.totalVolume = totalVolume
        self.prCount = prCount
        self.template = template
    }
}

@Model
final class WorkoutExercise {
    var id: UUID

    // MARK: Sync metadata
    //
    // Three columns, mirroring the server. The DEFAULTS are the load-bearing
    // part and the reasoning is in Sync/Syncable.swift — in short: declaration
    // -level defaults so SwiftData can lightweight-migrate an existing store,
    // and `needsSync = true` so a migrated or newly created row is PUSHED
    // rather than silently assumed clean.

    /// Wall-clock time of the last local edit. The last-write-wins key.
    var updatedAt: Date = Date.distantPast
    /// Tombstone. Non-nil means deleted; the row stays so the delete can reach
    /// devices that were offline when it happened.
    var deletedAt: Date?
    /// Has local changes the server has not confirmed.
    var needsSync: Bool = true
    var order: Int
    var supersetGroupID: UUID?
    var note: String?

    // MARK: Parity with TemplateExercise
    //
    // The per-exercise menu is the SAME in a template and in a live workout, so
    // the two models have to be able to hold the same answers. These two were
    // on TemplateExercise only, which would have meant greying out "Add Sticky
    // Note" and "Update Rest Timers" mid-workout — the identical menu failing
    // to be identical.
    //
    // Added now, deliberately, while the store holds nothing worth keeping and
    // nothing has ever synced. The same change once history is on the server is
    // a migration against data the user cares about. Declaration-level defaults
    // for the usual reason (docs/04-status.md § lessons).

    /// A note that stays pinned while logging, rather than tucked away.
    var stickyNote: String?
    /// Rest that new sets inherit. Per-set `restSeconds` still overrides it.
    var defaultRestSeconds: Int = 90

    var workout: Workout?
    var exercise: Exercise?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.workoutExercise)
    var sets: [WorkoutSet] = []

    init(
        id: UUID = UUID(),
        order: Int,
        supersetGroupID: UUID? = nil,
        note: String? = nil,
        stickyNote: String? = nil,
        defaultRestSeconds: Int = 90,
        workout: Workout? = nil,
        exercise: Exercise? = nil
    ) {
        self.id = id
        self.order = order
        self.supersetGroupID = supersetGroupID
        self.note = note
        self.stickyNote = stickyNote
        self.defaultRestSeconds = defaultRestSeconds
        self.workout = workout
        self.exercise = exercise
    }
}

@Model
final class WorkoutSet {
    var id: UUID

    // MARK: Sync metadata
    //
    // Three columns, mirroring the server. The DEFAULTS are the load-bearing
    // part and the reasoning is in Sync/Syncable.swift — in short: declaration
    // -level defaults so SwiftData can lightweight-migrate an existing store,
    // and `needsSync = true` so a migrated or newly created row is PUSHED
    // rather than silently assumed clean.

    /// Wall-clock time of the last local edit. The last-write-wins key.
    var updatedAt: Date = Date.distantPast
    /// Tombstone. Non-nil means deleted; the row stays so the delete can reach
    /// devices that were offline when it happened.
    var deletedAt: Date?
    /// Has local changes the server has not confirmed.
    var needsSync: Bool = true
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
