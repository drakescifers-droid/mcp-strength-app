//
//  SyncRows.swift
//  MCPStrength
//
//  The wire format: one struct per Postgres table, and the conversion from a
//  SwiftData model into it.
//
//  ## Why these exist at all
//
//  A `@Model` class cannot go on the wire. It holds object references where
//  Postgres holds foreign keys, it carries relationships the server has no
//  column for, and its property names are camelCase where the columns are
//  snake_case. So each table gets a flat `Codable` struct, and `CodingKeys` is
//  where the two naming schemes meet.
//
//  ## The failure mode these are shaped around
//
//  A wrong key is invisible until it reaches the server, and then it is either
//  a 400 on every sync forever or — worse — a column that silently never gets
//  written. Four columns do NOT match their Swift property name, all forced by
//  Postgres reserved words (docs/05-database.md § Naming):
//
//      order  -> sort_order        cursor -> program_cursor
//      group  -> group_kind        duration -> duration_seconds
//
//  Those four are exactly where a typo would go unnoticed, so
//  `supabase/scripts/check_row_mapping.py` diffs every `CodingKeys` in this
//  file against the actual columns in the schema migration. Run it after
//  touching either side.
//
//  ## What is deliberately absent
//
//  `created_at` and `server_updated_at` are SERVER-owned. The trigger sets both
//  on every write regardless of what arrives (verified in
//  supabase/tests/01_schema_test.sql), so sending them is pointless.
//  `serverUpdatedAt` is present but optional because the PULL direction needs
//  it — it is the cursor, and the only reason a client ever reads it.
//
//  Enum values are the Swift raw values verbatim, which is the whole reason
//  docs/05-database.md insisted the Postgres enums spell them the same way:
//  encoding the Swift enum directly produces the exact string the column
//  accepts, with no mapping table in between to get wrong.
//

import Foundation

// MARK: - Exercises

struct SyncExerciseRow: Codable, Sendable, Equatable {
    let id: UUID
    let userID: UUID?
    let name: String
    let aliases: [String]
    let bodyPart: BodyPart
    let category: ExerciseCategory
    let isCustom: Bool
    let updatedAt: Date
    let deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, aliases
        case userID = "user_id"
        case bodyPart = "body_part"
        case category
        case isCustom = "is_custom"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }
}

// MARK: - Templates

struct SyncTemplateFolderRow: Codable, Sendable, Equatable {
    let id: UUID
    let userID: UUID
    let name: String
    let sortOrder: Int
    let isCollapsed: Bool
    let kind: FolderKind
    let programCursor: Int
    let totalCycles: Int?
    let updatedAt: Date
    let deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, kind
        case userID = "user_id"
        case sortOrder = "sort_order"
        case isCollapsed = "is_collapsed"
        case programCursor = "program_cursor"
        case totalCycles = "total_cycles"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }
}

struct SyncTemplateRow: Codable, Sendable, Equatable {
    let id: UUID
    let userID: UUID
    let name: String
    let folderID: UUID?
    let note: String?
    let sortOrder: Int
    let lastPerformedAt: Date?
    let updatedAt: Date
    let deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, note
        case userID = "user_id"
        case folderID = "folder_id"
        case sortOrder = "sort_order"
        case lastPerformedAt = "last_performed_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }
}

struct SyncTemplateExerciseRow: Codable, Sendable, Equatable {
    let id: UUID
    let userID: UUID
    let templateID: UUID
    let exerciseID: UUID?
    let sortOrder: Int
    let supersetGroupID: UUID?
    let note: String?
    let stickyNote: String?
    let defaultRestSeconds: Int
    let updatedAt: Date
    let deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, note
        case userID = "user_id"
        case templateID = "template_id"
        case exerciseID = "exercise_id"
        case sortOrder = "sort_order"
        case supersetGroupID = "superset_group_id"
        case stickyNote = "sticky_note"
        case defaultRestSeconds = "default_rest_seconds"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }
}

struct SyncTemplateSetRow: Codable, Sendable, Equatable {
    let id: UUID
    let userID: UUID
    let templateExerciseID: UUID
    let sortOrder: Int
    let setType: SetType
    let weight: Double?
    let reps: Int?
    let repRangeStart: Int?
    let repRangeEnd: Int?
    let rpe: Double?
    let distance: Double?
    let durationSeconds: Int?
    let restSeconds: Int
    let updatedAt: Date
    let deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, weight, reps, rpe, distance
        case userID = "user_id"
        case templateExerciseID = "template_exercise_id"
        case sortOrder = "sort_order"
        case setType = "set_type"
        case repRangeStart = "rep_range_start"
        case repRangeEnd = "rep_range_end"
        case durationSeconds = "duration_seconds"
        case restSeconds = "rest_seconds"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }
}

// MARK: - Programs

struct SyncProgramDayRow: Codable, Sendable, Equatable {
    let id: UUID
    let userID: UUID
    let folderID: UUID
    let templateID: UUID?
    let sortOrder: Int
    let label: String?
    let updatedAt: Date
    let deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, label
        case userID = "user_id"
        case folderID = "folder_id"
        case templateID = "template_id"
        case sortOrder = "sort_order"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }
}

// MARK: - Workouts

struct SyncWorkoutRow: Codable, Sendable, Equatable {
    let id: UUID
    let userID: UUID
    let name: String
    let templateID: UUID?
    let startedAt: Date
    let completedAt: Date?
    let durationSeconds: Int
    let note: String?
    let totalVolume: Double
    let prCount: Int
    let updatedAt: Date
    let deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, note
        case userID = "user_id"
        case templateID = "template_id"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case durationSeconds = "duration_seconds"
        case totalVolume = "total_volume"
        case prCount = "pr_count"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }
}

struct SyncWorkoutExerciseRow: Codable, Sendable, Equatable {
    let id: UUID
    let userID: UUID
    let workoutID: UUID
    let exerciseID: UUID?
    let sortOrder: Int
    let supersetGroupID: UUID?
    let note: String?
    let updatedAt: Date
    let deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, note
        case userID = "user_id"
        case workoutID = "workout_id"
        case exerciseID = "exercise_id"
        case sortOrder = "sort_order"
        case supersetGroupID = "superset_group_id"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }
}

struct SyncWorkoutSetRow: Codable, Sendable, Equatable {
    let id: UUID
    let userID: UUID
    let workoutExerciseID: UUID
    let sortOrder: Int
    let setType: SetType
    let weight: Double?
    let reps: Int?
    let rpe: Double?
    let distance: Double?
    let durationSeconds: Int?
    let restSeconds: Int
    let isCompleted: Bool
    let completedAt: Date?
    let updatedAt: Date
    let deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, weight, reps, rpe, distance
        case userID = "user_id"
        case workoutExerciseID = "workout_exercise_id"
        case sortOrder = "sort_order"
        case setType = "set_type"
        case durationSeconds = "duration_seconds"
        case restSeconds = "rest_seconds"
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }
}

// MARK: - Measurements

struct SyncMeasurementTypeRow: Codable, Sendable, Equatable {
    let id: UUID
    let userID: UUID?
    let name: String
    let groupKind: MeasurementGroup
    let sortOrder: Int
    let updatedAt: Date
    let deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case userID = "user_id"
        case groupKind = "group_kind"
        case sortOrder = "sort_order"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }
}

struct SyncMeasurementEntryRow: Codable, Sendable, Equatable {
    let id: UUID
    let userID: UUID
    let typeID: UUID?
    let value: Double
    let unit: String
    let recordedAt: Date
    let source: MeasurementSource
    let updatedAt: Date
    let deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, value, unit, source
        case userID = "user_id"
        case typeID = "type_id"
        case recordedAt = "recorded_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }
}

// NOTE: `exercise_preferences` has no row type here on purpose. The table
// exists (docs/05-database.md § "The one real divergence") but the app has no
// model for it and nothing reads or writes those four per-user fields yet. A
// struct with no producer and no consumer is dead code that reads as coverage.

// MARK: - Model → row
//
// The PUSH direction only. Pulling needs the reverse, and that is a different
// problem: it has to resolve foreign keys back into object references against a
// ModelContext, which these free functions deliberately know nothing about.
//
// Relationships become ids. A parent id is non-optional where the schema says
// NOT NULL, so a child that has somehow lost its parent CANNOT be encoded — it
// returns nil rather than inventing a uuid. That row stays dirty and is retried,
// which is the honest outcome: a set with no exercise is corrupt locally, and
// pushing it under a fabricated parent would spread the corruption to every
// device.

enum SyncRowMapper {

    static func row(for exercise: Exercise, userID: UUID) -> SyncExerciseRow {
        SyncExerciseRow(
            id: exercise.id,
            userID: userID,
            name: exercise.name,
            aliases: exercise.aliases,
            bodyPart: exercise.bodyPart,
            category: exercise.category,
            isCustom: exercise.isCustom,
            updatedAt: exercise.updatedAt,
            deletedAt: exercise.deletedAt
        )
    }

    static func row(for folder: TemplateFolder, userID: UUID) -> SyncTemplateFolderRow {
        SyncTemplateFolderRow(
            id: folder.id,
            userID: userID,
            name: folder.name,
            sortOrder: folder.order,
            isCollapsed: folder.isCollapsed,
            kind: folder.kind,
            programCursor: folder.cursor,
            totalCycles: folder.totalCycles,
            updatedAt: folder.updatedAt,
            deletedAt: folder.deletedAt
        )
    }

    static func row(for template: Template, userID: UUID) -> SyncTemplateRow {
        SyncTemplateRow(
            id: template.id,
            userID: userID,
            name: template.name,
            folderID: template.folder?.id,
            note: template.note,
            sortOrder: template.order,
            lastPerformedAt: template.lastPerformedAt,
            updatedAt: template.updatedAt,
            deletedAt: template.deletedAt
        )
    }

    static func row(for exercise: TemplateExercise, userID: UUID) -> SyncTemplateExerciseRow? {
        guard let templateID = exercise.template?.id else { return nil }
        return SyncTemplateExerciseRow(
            id: exercise.id,
            userID: userID,
            templateID: templateID,
            exerciseID: exercise.exercise?.id,
            sortOrder: exercise.order,
            supersetGroupID: exercise.supersetGroupID,
            note: exercise.note,
            stickyNote: exercise.stickyNote,
            defaultRestSeconds: exercise.defaultRestSeconds,
            updatedAt: exercise.updatedAt,
            deletedAt: exercise.deletedAt
        )
    }

    static func row(for set: TemplateSet, userID: UUID) -> SyncTemplateSetRow? {
        guard let parentID = set.templateExercise?.id else { return nil }
        return SyncTemplateSetRow(
            id: set.id,
            userID: userID,
            templateExerciseID: parentID,
            sortOrder: set.order,
            setType: set.setType,
            weight: set.weight,
            reps: set.reps,
            repRangeStart: set.repRangeStart,
            repRangeEnd: set.repRangeEnd,
            rpe: set.rpe,
            distance: set.distance,
            durationSeconds: set.duration,
            restSeconds: set.restSeconds,
            updatedAt: set.updatedAt,
            deletedAt: set.deletedAt
        )
    }

    static func row(for day: ProgramDay, userID: UUID) -> SyncProgramDayRow? {
        guard let folderID = day.folder?.id else { return nil }
        return SyncProgramDayRow(
            id: day.id,
            userID: userID,
            folderID: folderID,
            templateID: day.template?.id,
            sortOrder: day.order,
            label: day.label,
            updatedAt: day.updatedAt,
            deletedAt: day.deletedAt
        )
    }

    static func row(for workout: Workout, userID: UUID) -> SyncWorkoutRow {
        SyncWorkoutRow(
            id: workout.id,
            userID: userID,
            name: workout.name,
            templateID: workout.template?.id,
            startedAt: workout.startedAt,
            completedAt: workout.completedAt,
            durationSeconds: workout.durationSeconds,
            note: workout.note,
            totalVolume: workout.totalVolume,
            prCount: workout.prCount,
            updatedAt: workout.updatedAt,
            deletedAt: workout.deletedAt
        )
    }

    static func row(for exercise: WorkoutExercise, userID: UUID) -> SyncWorkoutExerciseRow? {
        guard let workoutID = exercise.workout?.id else { return nil }
        return SyncWorkoutExerciseRow(
            id: exercise.id,
            userID: userID,
            workoutID: workoutID,
            exerciseID: exercise.exercise?.id,
            sortOrder: exercise.order,
            supersetGroupID: exercise.supersetGroupID,
            note: exercise.note,
            updatedAt: exercise.updatedAt,
            deletedAt: exercise.deletedAt
        )
    }

    static func row(for set: WorkoutSet, userID: UUID) -> SyncWorkoutSetRow? {
        guard let parentID = set.workoutExercise?.id else { return nil }
        return SyncWorkoutSetRow(
            id: set.id,
            userID: userID,
            workoutExerciseID: parentID,
            sortOrder: set.order,
            setType: set.setType,
            weight: set.weight,
            reps: set.reps,
            rpe: set.rpe,
            distance: set.distance,
            durationSeconds: set.duration,
            restSeconds: set.restSeconds,
            isCompleted: set.isCompleted,
            completedAt: set.completedAt,
            updatedAt: set.updatedAt,
            deletedAt: set.deletedAt
        )
    }

    static func row(for type: MeasurementType, userID: UUID) -> SyncMeasurementTypeRow {
        SyncMeasurementTypeRow(
            id: type.id,
            userID: userID,
            name: type.name,
            groupKind: type.group,
            sortOrder: type.sortOrder,
            updatedAt: type.updatedAt,
            deletedAt: type.deletedAt
        )
    }

    static func row(for entry: MeasurementEntry, userID: UUID) -> SyncMeasurementEntryRow {
        SyncMeasurementEntryRow(
            id: entry.id,
            userID: userID,
            typeID: entry.type?.id,
            value: entry.value,
            unit: entry.unit,
            recordedAt: entry.recordedAt,
            source: entry.source,
            updatedAt: entry.updatedAt,
            deletedAt: entry.deletedAt
        )
    }
}
