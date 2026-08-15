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
    var name: String
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
    var name: String
    var note: String?
    var order: Int
    var lastPerformedAt: Date?

    var folder: TemplateFolder?

    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template)
    var exercises: [TemplateExercise] = []

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
