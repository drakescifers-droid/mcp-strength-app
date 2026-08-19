//
//  SyncRowApply.swift
//  MCPStrength
//
//  The inverse of SyncRowMapper: write a row PULLED FROM THE SERVER onto a
//  local SwiftData model.
//
//  ## Why this is a different file, and a different code path
//
//  SyncRowMapper is the PUSH direction. This is PULL. They look like mirrors
//  of each other and they are — except for one rule that is the whole reason
//  they must not share a helper: applying a remote row must never mark the
//  model dirty. The local-write helper is the other path. Calling it here
//  dirties everything a pull touches, the next push sends it all straight
//  back, the server accepts it, the next pull returns it, and the two ends
//  never settle. docs/06-sync.md § "The echo trap". After apply, the local
//  row matches the server, so the only legal bookkeeping is `markSynced()`.
//
//  ## What this file deliberately does not do
//
//  Foreign keys arrive as UUIDs; models hold object references. Resolving a
//  uuid against the store is the sync engine's job. Every already-resolved
//  parent is passed IN, and this file never looks one up. A missing optional
//  parent is `nil`, which is how an unfiled template or a purged-and-
//  nullified workout.template lands.
//
//  `id` is not copied. The caller matched this model to this row BY id;
//  reassigning it is at best a no-op and at worst a SwiftData identity
//  change we have no reason to invite. `user_id` has no local field.
//  `serverUpdatedAt` is the pull cursor and lives on the engine, not the
//  model.
//
//  ## The four columns whose names do not match
//
//  Postgres reserved words forced four renames on the row (docs/05-database.md
//  § Naming). Getting them backwards compiles cleanly and is wrong:
//
//      row.sortOrder       -> model.order
//      row.programCursor   -> model.cursor          (TemplateFolder)
//      row.groupKind       -> model.group           (MeasurementType)
//      row.durationSeconds -> model.duration        (TemplateSet, WorkoutSet)
//
//  Two near-misses that are NOT remapped, because the model already uses the
//  row's name: `Workout.durationSeconds` and `MeasurementType.sortOrder`.
//

import Foundation

enum SyncRowApply {

    // MARK: - Exercises

    /// Seeded library rows share baked UUIDs with Postgres. Their per-user
    /// fields live on `ExercisePreference`, a different row — applying an
    /// exercise cannot touch them, by construction. Do not start writing
    /// them here.
    static func apply(_ row: SyncExerciseRow, to exercise: Exercise) {
        exercise.name = row.name
        exercise.aliases = row.aliases
        exercise.bodyPart = row.bodyPart
        exercise.secondaryBodyParts = row.secondaryBodyParts
        exercise.category = row.category
        exercise.isCustom = row.isCustom
        settle(exercise, from: row.updatedAt, deletedAt: row.deletedAt)
    }

    // MARK: - Templates

    static func apply(_ row: SyncTemplateFolderRow, to folder: TemplateFolder) {
        folder.name = row.name
        folder.order = row.sortOrder
        folder.isCollapsed = row.isCollapsed
        folder.kind = row.kind
        folder.cursor = row.programCursor
        folder.totalCycles = row.totalCycles
        settle(folder, from: row.updatedAt, deletedAt: row.deletedAt)
    }

    static func apply(_ row: SyncTemplateRow, to template: Template, folder: TemplateFolder?) {
        template.name = row.name
        template.note = row.note
        template.order = row.sortOrder
        template.lastPerformedAt = row.lastPerformedAt
        template.folder = folder
        settle(template, from: row.updatedAt, deletedAt: row.deletedAt)
    }

    static func apply(
        _ row: SyncTemplateExerciseRow,
        to templateExercise: TemplateExercise,
        template: Template?,
        exercise: Exercise?
    ) {
        templateExercise.order = row.sortOrder
        templateExercise.supersetGroupID = row.supersetGroupID
        templateExercise.note = row.note
        templateExercise.stickyNote = row.stickyNote
        templateExercise.defaultRestSeconds = row.defaultRestSeconds
        templateExercise.template = template
        templateExercise.exercise = exercise
        settle(templateExercise, from: row.updatedAt, deletedAt: row.deletedAt)
    }

    static func apply(
        _ row: SyncTemplateSetRow,
        to set: TemplateSet,
        templateExercise: TemplateExercise?
    ) {
        set.order = row.sortOrder
        set.setType = row.setType
        set.weight = row.weight
        set.reps = row.reps
        set.repRangeStart = row.repRangeStart
        set.repRangeEnd = row.repRangeEnd
        set.rpe = row.rpe
        set.distance = row.distance
        set.duration = row.durationSeconds
        set.restSeconds = row.restSeconds
        set.templateExercise = templateExercise
        settle(set, from: row.updatedAt, deletedAt: row.deletedAt)
    }

    // MARK: - Programs

    static func apply(
        _ row: SyncProgramDayRow,
        to day: ProgramDay,
        folder: TemplateFolder?,
        template: Template?
    ) {
        day.order = row.sortOrder
        day.label = row.label
        day.folder = folder
        day.template = template
        settle(day, from: row.updatedAt, deletedAt: row.deletedAt)
    }

    // MARK: - Workouts

    /// `durationSeconds` keeps its name on Workout — this is not one of the
    /// four reserved-word remaps. Only TemplateSet / WorkoutSet call the
    /// same column `duration`.
    static func apply(_ row: SyncWorkoutRow, to workout: Workout, template: Template?) {
        workout.name = row.name
        workout.startedAt = row.startedAt
        workout.completedAt = row.completedAt
        workout.durationSeconds = row.durationSeconds
        workout.note = row.note
        workout.summary = row.summary
        workout.totalVolume = row.totalVolume
        workout.prCount = row.prCount
        workout.template = template
        settle(workout, from: row.updatedAt, deletedAt: row.deletedAt)
    }

    static func apply(
        _ row: SyncWorkoutExerciseRow,
        to workoutExercise: WorkoutExercise,
        workout: Workout?,
        exercise: Exercise?
    ) {
        workoutExercise.order = row.sortOrder
        workoutExercise.supersetGroupID = row.supersetGroupID
        workoutExercise.note = row.note
        workoutExercise.stickyNote = row.stickyNote
        workoutExercise.defaultRestSeconds = row.defaultRestSeconds
        workoutExercise.workout = workout
        workoutExercise.exercise = exercise
        settle(workoutExercise, from: row.updatedAt, deletedAt: row.deletedAt)
    }

    static func apply(
        _ row: SyncWorkoutSetRow,
        to set: WorkoutSet,
        workoutExercise: WorkoutExercise?
    ) {
        set.order = row.sortOrder
        set.setType = row.setType
        set.weight = row.weight
        set.reps = row.reps
        set.rpe = row.rpe
        set.distance = row.distance
        set.duration = row.durationSeconds
        set.restSeconds = row.restSeconds
        set.isCompleted = row.isCompleted
        set.completedAt = row.completedAt
        set.workoutExercise = workoutExercise
        settle(set, from: row.updatedAt, deletedAt: row.deletedAt)
    }

    // MARK: - Measurements

    /// `sortOrder` keeps its name on MeasurementType. The remap here is
    /// `groupKind` → `group`; folding it into `order` would not compile,
    /// but copying `groupKind` onto nothing would.
    static func apply(_ row: SyncMeasurementTypeRow, to type: MeasurementType) {
        type.name = row.name
        type.group = row.groupKind
        type.sortOrder = row.sortOrder
        settle(type, from: row.updatedAt, deletedAt: row.deletedAt)
    }

    static func apply(
        _ row: SyncMeasurementEntryRow,
        to entry: MeasurementEntry,
        type: MeasurementType?
    ) {
        entry.value = row.value
        entry.unit = row.unit
        entry.recordedAt = row.recordedAt
        entry.source = row.source
        entry.type = type
        settle(entry, from: row.updatedAt, deletedAt: row.deletedAt)
    }

    // MARK: - Settings and per-exercise preferences

    /// `id` is not copied. The settings pull matched this model through
    /// `AppSettings.current(in:)`, not by id, and rewriting the local
    /// uuid to the user id is a sync-time fixup wearing a migration's
    /// clothes. docs/06-sync.md.
    static func apply(_ row: SyncAppSettingsRow, to settings: AppSettings) {
        settings.weightUnit = row.weightUnit
        settings.measurementWeightUnit = row.measurementWeightUnit
        settings.distanceUnit = row.distanceUnit
        settings.sizeUnit = row.sizeUnit
        settings.defaultRestSeconds = row.defaultRestSeconds
        settings.weekStartDay = row.weekStartDay
        settings.workoutCalorieRate = row.workoutCalorieRate
        settings.writeWorkoutsToHealth = row.writeWorkoutsToHealth
        settings.writeMeasurementsToHealth = row.writeMeasurementsToHealth
        settings.readMeasurementsFromHealth = row.readMeasurementsFromHealth
        settings.theme = row.theme
        settings.language = row.language
        settings.previousSetBehavior = row.previousSetBehavior
        settle(settings, from: row.updatedAt, deletedAt: row.deletedAt)
    }

    static func apply(
        _ row: SyncExercisePreferenceRow,
        to preference: ExercisePreference,
        exercise: Exercise?
    ) {
        preference.weightUnitOverride = row.weightUnitOverride
        preference.barType = row.barType
        preference.focusMetric = row.focusMetric
        preference.notes = row.notes
        preference.exercise = exercise
        settle(preference, from: row.updatedAt, deletedAt: row.deletedAt)
    }

    // MARK: - Bookkeeping

    /// Copy the two timestamps the pull is authoritative for, then mark the
    /// row clean. Extracted so a new apply cannot forget one of the three
    /// and so nobody reaches for the local-write helper by habit.
    ///
    /// Dropping `deletedAt` resurrects a tombstone on this device. Dropping
    /// `updatedAt` throws away the last-write-wins key. Skipping the clean
    /// mark (or dirtying the row) is the echo trap.
    private static func settle(_ model: some Syncable, from updatedAt: Date, deletedAt: Date?) {
        model.updatedAt = updatedAt
        model.deletedAt = deletedAt
        model.markSynced()
    }
}
