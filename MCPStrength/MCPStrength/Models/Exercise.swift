//
//  Exercise.swift
//  MCPStrength
//

import Foundation
import SwiftData

enum BodyPart: String, Codable, CaseIterable, Sendable {
    case arms, back, cardio, chest, core, fullBody, legs, olympic, other, shoulders
}

enum ExerciseCategory: String, Codable, CaseIterable, Sendable {
    case barbell, dumbbell, machineOther, weightedBodyweight, assistedBodyweight, repsOnly, cardio, duration
}

enum FocusMetric: String, Codable, CaseIterable, Sendable {
    case totalVolume, volumeIncrease, totalReps, weightPerRep
}

enum WeightUnit: String, Codable, CaseIterable, Sendable {
    case lbs, kg
}

enum BarType: String, Codable, CaseIterable, Sendable {
    case olympicBar, standardBar, ezBar, trapBar, dumbbell, other
}

@Model
final class Exercise {
    var id: UUID
    var name: String
    var aliases: [String]
    var bodyPart: BodyPart
    var category: ExerciseCategory
    var isCustom: Bool
    var weightUnitOverride: WeightUnit?
    var barType: BarType?
    var focusMetric: FocusMetric
    var notes: String?

    init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        bodyPart: BodyPart,
        category: ExerciseCategory,
        isCustom: Bool = false,
        weightUnitOverride: WeightUnit? = nil,
        barType: BarType? = nil,
        focusMetric: FocusMetric,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.bodyPart = bodyPart
        self.category = category
        self.isCustom = isCustom
        self.weightUnitOverride = weightUnitOverride
        self.barType = barType
        self.focusMetric = focusMetric
        self.notes = notes
    }
}
