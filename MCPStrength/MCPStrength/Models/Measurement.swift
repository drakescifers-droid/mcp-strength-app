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
    var name: String
    var group: MeasurementGroup

    @Relationship(deleteRule: .nullify, inverse: \MeasurementEntry.type)
    var entries: [MeasurementEntry] = []

    init(
        id: UUID = UUID(),
        name: String,
        group: MeasurementGroup = .core
    ) {
        self.id = id
        self.name = name
        self.group = group
    }
}

@Model
final class MeasurementEntry {
    var id: UUID
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
