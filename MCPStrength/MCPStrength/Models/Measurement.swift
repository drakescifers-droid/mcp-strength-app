//
//  Measurement.swift
//  MCPStrength
//

import Foundation
import SwiftData

enum MeasurementGroup: String, Codable, CaseIterable, Sendable {
    case core, bodyPart
}

enum MeasurementSource: String, Codable, CaseIterable, Sendable {
    case manual, healthKit
}

@Model
final class MeasurementType {
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
    var group: MeasurementGroup
    /// Display order within `group`. Seeded, not alphabetical: the reference is
    /// anatomical, and that order becomes muscle memory (see measurement-seed.json).
    ///
    /// **The `= 0` is load-bearing, do not remove it.** A default on the DECLARATION is
    /// what lets SwiftData lightweight-migrate a store written before this property
    /// existed; a default only in `init` is invisible to migration, and opening an older
    /// store then throws from `ModelContainer(for:)` — which crashed the app on launch
    /// before this was fixed. Rows migrated in at 0 are corrected on the next launch,
    /// because the seed importer rewrites sortOrder on existing rows too.
    var sortOrder: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \MeasurementEntry.type)
    var entries: [MeasurementEntry] = []

    init(
        id: UUID = UUID(),
        name: String,
        group: MeasurementGroup = .core,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.group = group
        self.sortOrder = sortOrder
    }
}

@Model
final class MeasurementEntry {
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
    var value: Double
    var unit: String
    var recordedAt: Date
    var source: MeasurementSource

    var type: MeasurementType?

    init(
        id: UUID = UUID(),
        value: Double,
        unit: String,
        recordedAt: Date = Date(),
        source: MeasurementSource = .manual,
        type: MeasurementType? = nil
    ) {
        self.id = id
        self.value = value
        self.unit = unit
        self.recordedAt = recordedAt
        self.source = source
        self.type = type
    }
}
