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

    /// Spelled identically to the Postgres enum value added by
    /// `20260817120000_hammer_strength_category.sql`. A ninth `case` is
    /// the right model — `rawValue` would then be the column value, with
    /// no mapping table (docs/05-database.md § Naming) — but
    /// `OneRepMax.supportsEstimate` is an exhaustive switch this change
    /// is not allowed to edit, and swiftc will not emit the module with
    /// an unhandled case. The category exists on the server; associating
    /// a Swift `Exercise` with it waits on that one-line companion.
    static var hammerStrength: String { "hammerStrength" }
}

enum FocusMetric: String, Codable, CaseIterable, Sendable {
    case totalVolume, volumeIncrease, totalReps, weightPerRep
}

enum WeightUnit: String, Codable, CaseIterable, Sendable {
    case lbs, kg
}

enum BarType: String, Codable, CaseIterable, Sendable {
    case olympicBar, standardBar, ezBar, trapBar, dumbbell, other

    /// Empty-bar weight in pounds.
    ///
    /// Pounds, not kilograms: the app is lbs-first and canonical units are
    /// later work. A kg user will eventually want 20 kg for `olympicBar`
    /// rather than 45 lb, and this property is where that conversion will
    /// have to happen — a caller reading `weight` today is reading pounds.
    ///
    /// `dumbbell` and `other` are 0 because there is no bar. A warm-up
    /// floor must treat 0 as "no floor", the same as a missing preference;
    /// `WarmupSets.plan` does that. Do not rename these cases: they are
    /// values of the live Postgres enum `public.bar_type`.
    var weight: Double {
        switch self {
        case .olympicBar:  45
        case .standardBar: 33
        case .ezBar:       20
        case .trapBar:     75
        case .dumbbell:    0
        case .other:       0
        }
    }
}

@Model
final class Exercise {
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
