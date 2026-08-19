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

    /// Empty-bar weight, in the unit asked for.
    ///
    /// **Two real-world constants per bar, NOT one number converted**, and that
    /// is the whole point of the signature. An Olympic bar is 45 lb in a pounds
    /// gym and 20 kg in a metric one. Those are different masses — 45 lb is
    /// 20.41 kg — and both are right, because they are different bars made to
    /// different standards, not two spellings of one bar. Store one and convert
    /// and somebody always gets the wrong answer: a metric lifter told to load a
    /// 20.41 kg bar, or a pounds lifter told 44.09.
    ///
    /// This is why the units decision in `01-data-model.md` explicitly carves
    /// bars out. Canonical storage converts the numbers a user TYPED; it must
    /// not convert the constants the app supplies on their behalf.
    ///
    /// The kg values for `olympicBar` and `standardBar` are the actual gym
    /// standards (20 kg, 15 kg). `ezBar` at 10 kg likewise. **`trapBar` at 34 kg
    /// is the metric counterpart of the reference app's 75 lb, not a surveyed
    /// standard** — hex bars genuinely vary from about 45 to 75 lb, so this is a
    /// default to be edited rather than a fact.
    ///
    /// `dumbbell` and `other` are 0 in every unit because there is no bar. A
    /// warm-up floor must treat 0 as "no floor", the same as a missing
    /// preference; `WarmupSets.plan` does that.
    ///
    /// Do not rename these cases: they are values of the live Postgres enum
    /// `public.bar_type`.
    func weight(in unit: WeightUnit) -> Double {
        switch self {
        case .olympicBar:  unit == .kg ? 20 : 45
        case .standardBar: unit == .kg ? 15 : 33
        case .ezBar:       unit == .kg ? 10 : 20
        case .trapBar:     unit == .kg ? 34 : 75
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

    /// Other body parts this exercise also trains, beyond `bodyPart`.
    ///
    /// **Additive to an existing model, so this one — unlike `bodyPart` above
    /// — needs the declaration-level default** (`var x: T = v`, AGENTS.md
    /// rule 2). `bodyPart` predates every store this app has ever written;
    /// `secondaryBodyParts` does not, and `ModelContainer(for:)` throws on
    /// launch against an older store without one.
    ///
    /// `bodyPart` stays the PRIMARY and is never redundantly repeated here —
    /// Deadlift is `bodyPart: .back, secondaryBodyParts: [.legs]`, not
    /// `[.back, .legs]`. `ExercisesScreen`'s Legs/Back filter pills and
    /// `ExerciseMatcher`'s body-part hint both check primary OR secondary, so
    /// an exercise trained under either pill shows up under both — see
    /// `Exercise.trains(_:)`.
    var secondaryBodyParts: [BodyPart] = []

    /// Per-user settings for this exercise. Nil until the user sets one —
    /// the table stays sparse by construction (docs/06-sync.md).
    ///
    /// Optional on both sides so adding this to a store that already has
    /// `Exercise` rows is a lightweight migration. A non-optional
    /// relationship would kill the app on launch. The inverse lives
    /// here because `Exercise` is the parent: every other parent in
    /// this codebase (`Workout`, `Template`, `MeasurementType`)
    /// declares `@Relationship(inverse:)`, and display sites start
    /// from the exercise (`exercise.preference?.weightUnitOverride`).
    @Relationship(inverse: \ExercisePreference.exercise)
    var preference: ExercisePreference?

    init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        bodyPart: BodyPart,
        secondaryBodyParts: [BodyPart] = [],
        category: ExerciseCategory,
        isCustom: Bool = false
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.bodyPart = bodyPart
        self.secondaryBodyParts = secondaryBodyParts
        self.category = category
        self.isCustom = isCustom
    }
}

extension Exercise {
    /// Whether this exercise trains `part`, as PRIMARY or SECONDARY.
    ///
    /// The one predicate both the library filter pills and the matcher's
    /// body-part hint should use, so "does Deadlift count as Legs" has
    /// exactly one answer in the app rather than two call sites that could
    /// drift apart.
    func trains(_ part: BodyPart) -> Bool {
        bodyPart == part || secondaryBodyParts.contains(part)
    }
}
