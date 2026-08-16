//
//  Template.swift
//  MCPStrength
//

import Foundation
import SwiftData

enum FolderKind: String, Codable, CaseIterable, Sendable {
    case folder, program
}

enum SetType: String, Codable, CaseIterable, Sendable {
    case normal, warmup, dropSet, failure
}

@Model
final class TemplateFolder {
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
    /// Position among folders, 0-based. Distinct from `Template.order`, which
    /// is position within a folder (or the unfiled list) — not a global rank.
    var order: Int
    var isCollapsed: Bool
    var kind: FolderKind
    var cursor: Int
    var totalCycles: Int?

    @Relationship(deleteRule: .nullify, inverse: \Template.folder)
    var templates: [Template] = []

    @Relationship(deleteRule: .cascade, inverse: \ProgramDay.folder)
    var programDays: [ProgramDay] = []

    init(
        id: UUID = UUID(),
        name: String,
        order: Int,
        isCollapsed: Bool = false,
        kind: FolderKind = .folder,
        cursor: Int = 0,
        totalCycles: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.isCollapsed = isCollapsed
        self.kind = kind
        self.cursor = cursor
        self.totalCycles = totalCycles
    }
}

@Model
final class Template {
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
    var note: String?
    /// Position within its folder (or within the unfiled list when `folder` is
    /// nil), 0-based, renumbered densely on move/reorder. This is NOT a global
    /// rank — it used to be, and the next reader will assume it still is.
    var order: Int
    var lastPerformedAt: Date?

    var folder: TemplateFolder?

    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template)
    var exercises: [TemplateExercise] = []

    /// Workouts already performed from this template.
    ///
    /// **NULLIFY, never cascade.** Deleting a template must never delete the workouts
    /// performed from it — tidying up your templates would silently destroy training
    /// history. Nullify clears `Workout.template` on each of them instead, leaving the
    /// workout and its `name` (a stored copy, see docs/01 § Workouts) intact.
    ///
    /// Declaring the inverse is what makes that happen at all. Without it,
    /// `Workout.template` was an untracked reference that kept pointing at a deleted
    /// object rather than going nil.
    @Relationship(deleteRule: .nullify, inverse: \Workout.template)
    var workouts: [Workout] = []

    /// Program days that point at this template.
    ///
    /// **NULLIFY, never cascade.** Deleting a template should empty a program's
    /// day slot, never delete the program or its other days. Declaring the
    /// inverse is what makes `ProgramDay.template` go nil; without it the day
    /// keeps pointing at a deleted object.
    @Relationship(deleteRule: .nullify, inverse: \ProgramDay.template)
    var programDays: [ProgramDay] = []

    init(
        id: UUID = UUID(),
        name: String,
        note: String? = nil,
        order: Int,
        lastPerformedAt: Date? = nil,
        folder: TemplateFolder? = nil
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.order = order
        self.lastPerformedAt = lastPerformedAt
        self.folder = folder
    }
}

@Model
final class TemplateExercise {
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
    var stickyNote: String?
    var defaultRestSeconds: Int

    var template: Template?
    var exercise: Exercise?

    @Relationship(deleteRule: .cascade, inverse: \TemplateSet.templateExercise)
    var sets: [TemplateSet] = []

    init(
        id: UUID = UUID(),
        order: Int,
        supersetGroupID: UUID? = nil,
        note: String? = nil,
        stickyNote: String? = nil,
        defaultRestSeconds: Int = 90,
        template: Template? = nil,
        exercise: Exercise? = nil
    ) {
        self.id = id
        self.order = order
        self.supersetGroupID = supersetGroupID
        self.note = note
        self.stickyNote = stickyNote
        self.defaultRestSeconds = defaultRestSeconds
        self.template = template
        self.exercise = exercise
    }
}

@Model
final class TemplateSet {
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
    var repRangeStart: Int?
    var repRangeEnd: Int?
    var rpe: Double?
    var distance: Double?
    var duration: Int?
    var restSeconds: Int

    var templateExercise: TemplateExercise?

    init(
        id: UUID = UUID(),
        order: Int,
        setType: SetType = .normal,
        weight: Double? = nil,
        reps: Int? = nil,
        repRangeStart: Int? = nil,
        repRangeEnd: Int? = nil,
        rpe: Double? = nil,
        distance: Double? = nil,
        duration: Int? = nil,
        restSeconds: Int = 90,
        templateExercise: TemplateExercise? = nil
    ) {
        self.id = id
        self.order = order
        self.setType = setType
        self.weight = weight
        self.reps = reps
        self.repRangeStart = repRangeStart
        self.repRangeEnd = repRangeEnd
        self.rpe = rpe
        self.distance = distance
        self.duration = duration
        self.restSeconds = restSeconds
        self.templateExercise = templateExercise
    }
}
