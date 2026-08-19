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
//  ## A nil field must travel as an explicit `null`
//
//  Swift's synthesised `encode(to:)` uses `encodeIfPresent` for every
//  Optional, so a nil property is OMITTED FROM THE JSON ENTIRELY. An upsert
//  is `INSERT … ON CONFLICT DO UPDATE` and its SET clause is built from the
//  keys the payload actually contains — so an omitted column keeps whatever
//  the server already had. That silently turns *clear this* into *leave it
//  alone*:
//
//      1. the user sets a value; it pushes and the server stores it
//      2. they clear it; the key vanishes from the payload and the server
//         keeps the old value
//      3. the next pull brings the old value back down and overwrites the
//         local nil. The clear undoes itself, on every device.
//
//  Reachable today: unfiling a template (`folder_id`), Leave Superset
//  (`superset_group_id` — a shipped menu item), deleting a note or summary,
//  removing a prescribed weight or a logged one.
//
//  Every row therefore writes `encode(to:)` itself, using `encode` for every
//  field so a nil becomes JSON `null`. `serverUpdatedAt` is the ONE exception
//  and stays `encodeIfPresent`: it is server-owned (the `set_sync_metadata`
//  trigger writes it on every write) and a key for it is at best noise. Do
//  not add `init(from:)` — the synthesised decoder already treats an explicit
//  `null` as nil for an Optional.
//
//  `CodingKeys` is `CaseIterable` so one completeness test can ask every row
//  type: with every optional nil, is every key except `server_updated_at`
//  present? A forgotten line in a hand-written encoder would be worse than
//  the bug this exists to fix — the field would never travel at all, set or
//  cleared. The conformance lives on a same-file extension, not on the
//  enum declaration — `check_row_mapping.py` matches the literal
//  `enum CodingKeys: String, CodingKey {`, and `, CaseIterable` on that
//  line makes it report every struct as missing. docs/06-sync.md § "A nil
//  field must travel as an explicit `null`".
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

    /// Explicit `null` for every nil. The reason lives in the file header
    /// (and at length on `SyncExercisePreferenceRow.encode(to:)`): a
    /// synthesised encoder omits optionals, and an omitted column is not
    /// updated. `serverUpdatedAt` is the one `encodeIfPresent`.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(name, forKey: .name)
        try c.encode(aliases, forKey: .aliases)
        try c.encode(bodyPart, forKey: .bodyPart)
        try c.encode(category, forKey: .category)
        try c.encode(isCustom, forKey: .isCustom)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
        try c.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
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

    /// See `SyncExerciseRow.encode(to:)`. `serverUpdatedAt` is the one `encodeIfPresent`.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(name, forKey: .name)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(isCollapsed, forKey: .isCollapsed)
        try c.encode(kind, forKey: .kind)
        try c.encode(programCursor, forKey: .programCursor)
        try c.encode(totalCycles, forKey: .totalCycles)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
        try c.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
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

    /// See `SyncExerciseRow.encode(to:)`. `serverUpdatedAt` is the one `encodeIfPresent`.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(name, forKey: .name)
        try c.encode(folderID, forKey: .folderID)
        try c.encode(note, forKey: .note)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(lastPerformedAt, forKey: .lastPerformedAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
        try c.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
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

    /// See `SyncExerciseRow.encode(to:)`. `serverUpdatedAt` is the one `encodeIfPresent`.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(templateID, forKey: .templateID)
        try c.encode(exerciseID, forKey: .exerciseID)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(supersetGroupID, forKey: .supersetGroupID)
        try c.encode(note, forKey: .note)
        try c.encode(stickyNote, forKey: .stickyNote)
        try c.encode(defaultRestSeconds, forKey: .defaultRestSeconds)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
        try c.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
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

    /// See `SyncExerciseRow.encode(to:)`. `serverUpdatedAt` is the one `encodeIfPresent`.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(templateExerciseID, forKey: .templateExerciseID)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(setType, forKey: .setType)
        try c.encode(weight, forKey: .weight)
        try c.encode(reps, forKey: .reps)
        try c.encode(repRangeStart, forKey: .repRangeStart)
        try c.encode(repRangeEnd, forKey: .repRangeEnd)
        try c.encode(rpe, forKey: .rpe)
        try c.encode(distance, forKey: .distance)
        try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encode(restSeconds, forKey: .restSeconds)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
        try c.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
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

    /// See `SyncExerciseRow.encode(to:)`. `serverUpdatedAt` is the one `encodeIfPresent`.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(folderID, forKey: .folderID)
        try c.encode(templateID, forKey: .templateID)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(label, forKey: .label)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
        try c.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
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
    let summary: String?
    let totalVolume: Double
    let prCount: Int
    let updatedAt: Date
    let deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, note, summary
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

    /// See `SyncExerciseRow.encode(to:)`. `serverUpdatedAt` is the one `encodeIfPresent`.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(name, forKey: .name)
        try c.encode(templateID, forKey: .templateID)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(completedAt, forKey: .completedAt)
        try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encode(note, forKey: .note)
        try c.encode(summary, forKey: .summary)
        try c.encode(totalVolume, forKey: .totalVolume)
        try c.encode(prCount, forKey: .prCount)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
        try c.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
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
    let stickyNote: String?
    let defaultRestSeconds: Int
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
        case stickyNote = "sticky_note"
        case defaultRestSeconds = "default_rest_seconds"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }

    /// See `SyncExerciseRow.encode(to:)`. `serverUpdatedAt` is the one `encodeIfPresent`.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(workoutID, forKey: .workoutID)
        try c.encode(exerciseID, forKey: .exerciseID)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(supersetGroupID, forKey: .supersetGroupID)
        try c.encode(note, forKey: .note)
        try c.encode(stickyNote, forKey: .stickyNote)
        try c.encode(defaultRestSeconds, forKey: .defaultRestSeconds)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
        try c.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
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

    /// See `SyncExerciseRow.encode(to:)`. `serverUpdatedAt` is the one `encodeIfPresent`.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(workoutExerciseID, forKey: .workoutExerciseID)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(setType, forKey: .setType)
        try c.encode(weight, forKey: .weight)
        try c.encode(reps, forKey: .reps)
        try c.encode(rpe, forKey: .rpe)
        try c.encode(distance, forKey: .distance)
        try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encode(restSeconds, forKey: .restSeconds)
        try c.encode(isCompleted, forKey: .isCompleted)
        try c.encode(completedAt, forKey: .completedAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
        try c.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
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

    /// See `SyncExerciseRow.encode(to:)`. `serverUpdatedAt` is the one `encodeIfPresent`.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(name, forKey: .name)
        try c.encode(groupKind, forKey: .groupKind)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
        try c.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
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

    /// See `SyncExerciseRow.encode(to:)`. `serverUpdatedAt` is the one `encodeIfPresent`.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(typeID, forKey: .typeID)
        try c.encode(value, forKey: .value)
        try c.encode(unit, forKey: .unit)
        try c.encode(recordedAt, forKey: .recordedAt)
        try c.encode(source, forKey: .source)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
        try c.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
    }
}

// MARK: - Settings and per-exercise preferences
//
// Neither table has an `id` column. `SyncWireRow` requires `var id: UUID`,
// so both expose it as a COMPUTED property that is not in `CodingKeys` and
// therefore never encoded or decoded.
//
// `SyncExercisePreferenceRow.id` returns `exerciseID`. The local model's
// `id` IS the exercise's id, so the generic pull index matches without
// special handling. `SyncAppSettingsRow.id` returns `userID` only to
// satisfy the protocol — nothing matches on it. The settings pull goes
// through `AppSettings.current(in:)`, not `index[row.id]`. Matching on
// id would insert a second settings row: Drake's phone already holds
// one with a random UUID, the server identifies settings by user_id,
// and `current(in:)` then reads whichever happened to be older.
// docs/06-sync.md § "Syncing the two singleton-ish tables".

struct SyncAppSettingsRow: Codable, Sendable, Equatable {
    let userID: UUID
    let weightUnit: WeightUnit
    let measurementWeightUnit: WeightUnit
    let distanceUnit: DistanceUnit
    let sizeUnit: SizeUnit
    let defaultRestSeconds: Int
    let weekStartDay: Int
    let theme: String?
    let language: String?
    let previousSetBehavior: String?
    let updatedAt: Date
    let deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case theme, language
        case userID = "user_id"
        case weightUnit = "weight_unit"
        case measurementWeightUnit = "measurement_weight_unit"
        case distanceUnit = "distance_unit"
        case sizeUnit = "size_unit"
        case defaultRestSeconds = "default_rest_seconds"
        case weekStartDay = "week_start_day"
        case previousSetBehavior = "previous_set_behavior"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }

    /// Explicit `null` for every nil, for the reason argued at length on
    /// `SyncExercisePreferenceRow.encode(to:)`: the synthesised encoder omits
    /// nil optionals, an omitted column is not updated by an upsert, and
    /// "clear this" therefore becomes "leave it alone".
    ///
    /// None of this row's three nullable fields has a screen yet, so nothing
    /// can clear one TODAY. It is written this way anyway, because the day one
    /// of them gets a picker is not the day anybody will remember that the
    /// encoder silently drops the clear.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userID, forKey: .userID)
        try c.encode(weightUnit, forKey: .weightUnit)
        try c.encode(measurementWeightUnit, forKey: .measurementWeightUnit)
        try c.encode(distanceUnit, forKey: .distanceUnit)
        try c.encode(sizeUnit, forKey: .sizeUnit)
        try c.encode(defaultRestSeconds, forKey: .defaultRestSeconds)
        try c.encode(weekStartDay, forKey: .weekStartDay)
        try c.encode(theme, forKey: .theme)
        try c.encode(language, forKey: .language)
        try c.encode(previousSetBehavior, forKey: .previousSetBehavior)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
        try c.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
    }
}

extension SyncAppSettingsRow {
    /// Satisfies `SyncWireRow`. Not a column, not stored, not in
    /// CodingKeys — `app_settings` is keyed on `user_id`. Nothing
    /// matches on this value; the settings pull goes through
    /// `AppSettings.current(in:)`, not `index[row.id]`.
    var id: UUID { userID }
}

struct SyncExercisePreferenceRow: Codable, Sendable, Equatable {
    let userID: UUID
    let exerciseID: UUID
    let weightUnitOverride: WeightUnit?
    let barType: BarType?
    let focusMetric: FocusMetric
    let notes: String?
    let updatedAt: Date
    let deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case notes
        case userID = "user_id"
        case exerciseID = "exercise_id"
        case weightUnitOverride = "weight_unit_override"
        case barType = "bar_type"
        case focusMetric = "focus_metric"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }

    /// **A NIL FIELD MUST GO ON THE WIRE AS AN EXPLICIT `null`, and the
    /// synthesised encoder will not do it.**
    ///
    /// Swift's synthesised `encode(to:)` uses `encodeIfPresent` for every
    /// `Optional`, so a nil property is OMITTED FROM THE JSON ENTIRELY. An
    /// upsert is `INSERT … ON CONFLICT DO UPDATE`, and its SET clause is built
    /// from the keys the payload actually contains — so an omitted column keeps
    /// whatever the server already had.
    ///
    /// That turns "clear this" into "leave it alone", silently:
    ///
    ///   1. the user picks Olympic Bar for Bench Press; `bar_type` pushes and
    ///      the server stores it;
    ///   2. the user changes their mind and picks *Not set*; `barType` becomes
    ///      nil, the key vanishes from the payload, and the server keeps
    ///      `olympicBar`;
    ///   3. the next pull brings `olympicBar` back down and overwrites the
    ///      local nil. The setting un-clears itself.
    ///
    /// `ExercisePreferencesSheet` offers *Default* and *Not set* as real
    /// choices — `nil` IS the chosen value here, not a missing one
    /// (`ExercisePreferenceEditing`) — so this is reachable the day the sheet
    /// ships. `encode` rather than `encodeIfPresent` writes the key as `null`
    /// and the clear travels.
    ///
    /// > `serverUpdatedAt` is the ONE field that must still be omitted rather
    /// > than nulled: it is server-owned, the trigger sets it on every write,
    /// > and sending a key for it is at best noise. It is `encodeIfPresent`
    /// > deliberately, and it is the only one.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userID, forKey: .userID)
        try c.encode(exerciseID, forKey: .exerciseID)
        try c.encode(weightUnitOverride, forKey: .weightUnitOverride)
        try c.encode(barType, forKey: .barType)
        try c.encode(focusMetric, forKey: .focusMetric)
        try c.encode(notes, forKey: .notes)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
        try c.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
    }
}

extension SyncExercisePreferenceRow {
    /// The local preference's id is the exercise's id, so the generic
    /// pull index hits. Not a column, not stored, not in CodingKeys.
    var id: UUID { exerciseID }
}

// MARK: - CodingKeys: CaseIterable
//
// Same-file extensions, not `enum CodingKeys: String, CodingKey, CaseIterable`.
// `supabase/scripts/check_row_mapping.py` matches that declaration literally
// up to the `{`; putting CaseIterable on the line makes it report every
// struct as having no CodingKeys, which is a false alarm that hides a real
// misspelled column. Swift synthesises `allCases` for a same-file
// extension of a no-payload enum; do not write the case list by hand.

extension SyncExerciseRow.CodingKeys: CaseIterable {}
extension SyncTemplateFolderRow.CodingKeys: CaseIterable {}
extension SyncTemplateRow.CodingKeys: CaseIterable {}
extension SyncTemplateExerciseRow.CodingKeys: CaseIterable {}
extension SyncTemplateSetRow.CodingKeys: CaseIterable {}
extension SyncProgramDayRow.CodingKeys: CaseIterable {}
extension SyncWorkoutRow.CodingKeys: CaseIterable {}
extension SyncWorkoutExerciseRow.CodingKeys: CaseIterable {}
extension SyncWorkoutSetRow.CodingKeys: CaseIterable {}
extension SyncMeasurementTypeRow.CodingKeys: CaseIterable {}
extension SyncMeasurementEntryRow.CodingKeys: CaseIterable {}
extension SyncAppSettingsRow.CodingKeys: CaseIterable {}
extension SyncExercisePreferenceRow.CodingKeys: CaseIterable {}

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
            summary: workout.summary,
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
            stickyNote: exercise.stickyNote,
            defaultRestSeconds: exercise.defaultRestSeconds,
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

    static func row(for settings: AppSettings, userID: UUID) -> SyncAppSettingsRow {
        SyncAppSettingsRow(
            userID: userID,
            weightUnit: settings.weightUnit,
            measurementWeightUnit: settings.measurementWeightUnit,
            distanceUnit: settings.distanceUnit,
            sizeUnit: settings.sizeUnit,
            defaultRestSeconds: settings.defaultRestSeconds,
            weekStartDay: settings.weekStartDay,
            theme: settings.theme,
            language: settings.language,
            previousSetBehavior: settings.previousSetBehavior,
            updatedAt: settings.updatedAt,
            deletedAt: settings.deletedAt
        )
    }

    /// A preference that has lost its exercise cannot be encoded. The
    /// server key is `(user_id, exercise_id)` and there is no honest
    /// uuid to invent — the same rule as every other child mapper.
    static func row(for preference: ExercisePreference, userID: UUID) -> SyncExercisePreferenceRow? {
        guard let exerciseID = preference.exercise?.id else { return nil }
        return SyncExercisePreferenceRow(
            userID: userID,
            exerciseID: exerciseID,
            weightUnitOverride: preference.weightUnitOverride,
            barType: preference.barType,
            focusMetric: preference.focusMetric,
            notes: preference.notes,
            updatedAt: preference.updatedAt,
            deletedAt: preference.deletedAt
        )
    }
}
