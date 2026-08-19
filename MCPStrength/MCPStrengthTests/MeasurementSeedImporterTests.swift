//
//  MeasurementSeedImporterTests.swift
//  MCPStrengthTests
//

import Testing
import Foundation
import SwiftData
@testable import MCPStrength

/// Tests for `MeasurementSeedImporter`. The core upsert is exercised with fixture rows against an
/// in-memory `ModelContainer`, never through bundle plumbing. One extra test loads the real
/// bundled `measurement-seed.json` to keep the shipped file honest.
struct MeasurementSeedImporterTests {

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContext {
        let schema = Schema([
            Exercise.self,
            ExercisePreference.self,
            TemplateFolder.self,
            Template.self,
            TemplateExercise.self,
            TemplateSet.self,
            ProgramDay.self,
            Workout.self,
            WorkoutExercise.self,
            WorkoutSet.self,
            MeasurementType.self,
            MeasurementEntry.self,
            AppSettings.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private static let weightID = UUID(uuidString: "d4982888-f08b-4e32-892c-4a7c36658311")!
    private static let bodyFatID = UUID(uuidString: "5725b6bb-91e7-4ce9-a68f-5f9584f43649")!
    private static let neckID = UUID(uuidString: "fc17fc4a-6e88-4176-9c90-c7d9c3d847fe")!
    private static let chestID = UUID(uuidString: "41bb7a68-8487-4288-8673-c313bb440a84")!

    /// A small, hand-built fixture set (NOT the bundled file) so tests drive the pure core
    /// directly and never depend on bundle plumbing. Groups are numbered independently
    /// from 0, matching the seed-file contract.
    private var fixtureRows: [MeasurementSeedRow] {
        [
            MeasurementSeedRow(id: Self.weightID, name: "Weight", group: .core, unit: "lb", sortOrder: 0),
            MeasurementSeedRow(id: Self.bodyFatID, name: "Body Fat %", group: .core, unit: "%", sortOrder: 1),
            MeasurementSeedRow(id: Self.neckID, name: "Neck", group: .bodyPart, unit: "in", sortOrder: 0),
            MeasurementSeedRow(id: Self.chestID, name: "Chest", group: .bodyPart, unit: "in", sortOrder: 1),
        ]
    }

    private func fetchAll(_ context: ModelContext) throws -> [MeasurementType] {
        try context.fetch(FetchDescriptor<MeasurementType>())
    }

    // MARK: - Required tests

    // (1) Seeding inserts the expected types across BOTH groups.
    @Test func seedingInsertsExpectedTypesAcrossBothGroups() throws {
        let context = try makeContainer()
        try MeasurementSeedImporter.importRows(fixtureRows, into: context)

        let all = try fetchAll(context)
        #expect(all.count == 4)

        let core = all.filter { $0.group == .core }
        let bodyPart = all.filter { $0.group == .bodyPart }
        #expect(core.count == 2)
        #expect(bodyPart.count == 2)

        let weight = try #require(all.first { $0.id == Self.weightID })
        #expect(weight.name == "Weight")
        #expect(weight.group == .core)

        let neck = try #require(all.first { $0.id == Self.neckID })
        #expect(neck.name == "Neck")
        #expect(neck.group == .bodyPart)
    }

    // (2) Re-seeding is idempotent: running twice leaves the count and the ids unchanged.
    @Test func reSeedingIsIdempotentAndKeepsStableIds() throws {
        let context = try makeContainer()
        try MeasurementSeedImporter.importRows(fixtureRows, into: context)
        let afterFirst = try fetchAll(context)
        let firstIDs = Set(afterFirst.map(\.id))

        try MeasurementSeedImporter.importRows(fixtureRows, into: context)
        let afterSecond = try fetchAll(context)
        let secondIDs = Set(afterSecond.map(\.id))

        #expect(afterSecond.count == afterFirst.count)
        #expect(afterSecond.count == 4)
        #expect(secondIDs == firstIDs)
        #expect(secondIDs == Set([Self.weightID, Self.bodyFatID, Self.neckID, Self.chestID]))
    }

    // (3) A user-recorded entry survives a re-seed.
    @Test func userRecordedEntrySurvivesReSeed() throws {
        let context = try makeContainer()
        try MeasurementSeedImporter.importRows(fixtureRows, into: context)

        let weight = try #require(try fetchAll(context).first { $0.id == Self.weightID })
        let entry = MeasurementEntry(
            value: 186.95,
            unit: "lb",
            recordedAt: Date(),
            source: .manual,
            type: weight
        )
        context.insert(entry)
        try context.save()
        let entryID = entry.id

        // Re-seed.
        try MeasurementSeedImporter.importRows(fixtureRows, into: context)

        let allEntries = try context.fetch(FetchDescriptor<MeasurementEntry>())
        #expect(allEntries.count == 1) // the entry is still there
        let survivor = try #require(allEntries.first { $0.id == entryID })
        #expect(survivor.value == 186.95)
        #expect(survivor.unit == "lb")
        #expect(survivor.source == .manual)
        #expect(survivor.type?.id == Self.weightID) // still attached to the seeded type
    }

    // (4) Seeded rows carry the sortOrder from the fixture (groups numbered independently).
    @Test func seedingWritesSortOrderOnInsertedRows() throws {
        let context = try makeContainer()
        try MeasurementSeedImporter.importRows(fixtureRows, into: context)

        let all = try fetchAll(context)
        let weight = try #require(all.first { $0.id == Self.weightID })
        #expect(weight.sortOrder == 0)
        let bodyFat = try #require(all.first { $0.id == Self.bodyFatID })
        #expect(bodyFat.sortOrder == 1)
        // Body-part numbering restarts at 0 — Neck must sort before Chest.
        let neck = try #require(all.first { $0.id == Self.neckID })
        #expect(neck.sortOrder == 0)
        let chest = try #require(all.first { $0.id == Self.chestID })
        #expect(chest.sortOrder == 1)
        #expect(neck.sortOrder < chest.sortOrder)
    }

    // (5) A re-seed refreshes sortOrder on a pre-existing row rather than leaving it stale.
    // This is the upgrade path: types imported before sortOrder existed (or with a wrong
    // value) pick up the corrected order without being re-inserted.
    @Test func reSeedUpdatesStaleSortOrderOnExistingRow() throws {
        let context = try makeContainer()
        let stale = MeasurementType(
            id: Self.weightID,
            name: "Weight",
            group: .core,
            sortOrder: 99
        )
        context.insert(stale)
        try context.save()

        try MeasurementSeedImporter.importRows(fixtureRows, into: context)

        let all = try fetchAll(context)
        #expect(all.count == 4) // matched by id, not duplicated
        let weight = try #require(all.first { $0.id == Self.weightID })
        #expect(weight.sortOrder == 0) // refreshed from the seed, not left at 99
        #expect(weight.id == Self.weightID) // id is the contract; never rewritten
    }

    // MARK: - Bundled seed file (keeps the shipped file honest)

    // The real `measurement-seed.json` decodes, has unique ids, and covers exactly the two groups
    // with the names the docs specify.
    @Test func bundledSeedFileIsValid() throws {
        let url = try #require(Bundle(for: MeasurementType.self).url(forResource: "measurement-seed", withExtension: "json"),
                               "measurement-seed.json must ship in the app bundle")
        let data = try Data(contentsOf: url)
        let rows = try MeasurementSeedImporter.decodeRows(data)

        // 3 core + 15 body part = 18.
        #expect(rows.count == 18)

        // Unique ids.
        let ids = rows.map(\.id)
        #expect(Set(ids).count == ids.count)

        // Unique (case-insensitive) names.
        let lowerNames = rows.map { $0.name.lowercased() }
        #expect(Set(lowerNames).count == lowerNames.count)

        // Core group: Weight, Body Fat %, Caloric Intake.
        let core = rows.filter { $0.group == .core }
        #expect(core.count == 3)
        #expect(Set(core.map(\.name)) == Set(["Weight", "Body Fat %", "Caloric Intake"]))
        // Core units: lb, %, kcal.
        #expect(Set(core.map(\.unit)) == Set(["lb", "%", "kcal"]))

        // Body part group: the 15 names from docs/01-data-model.md § Measurements.
        let bodyPart = rows.filter { $0.group == .bodyPart }
        #expect(bodyPart.count == 15)
        #expect(bodyPart.allSatisfy { $0.unit == "in" })
        let expectedBodyParts: Set<String> = [
            "Neck", "Shoulders", "Chest", "Left Bicep", "Right Bicep",
            "Left Forearm", "Right Forearm", "Upper Abs", "Waist", "Lower Abs",
            "Hips", "Left Thigh", "Right Thigh", "Left Calf", "Right Calf",
        ]
        #expect(Set(bodyPart.map(\.name)) == expectedBodyParts)

        // sortOrder is unique within each group and follows the reference: Weight first
        // in Core; anatomical top-down in Body Part (Neck before Chest).
        let coreOrders = core.map(\.sortOrder)
        #expect(Set(coreOrders).count == coreOrders.count)
        let bodyPartOrders = bodyPart.map(\.sortOrder)
        #expect(Set(bodyPartOrders).count == bodyPartOrders.count)
        let weightRow = try #require(core.first { $0.name == "Weight" })
        #expect(weightRow.sortOrder == 0)
        #expect(weightRow.sortOrder == coreOrders.min())
        let neckRow = try #require(bodyPart.first { $0.name == "Neck" })
        let chestRow = try #require(bodyPart.first { $0.name == "Chest" })
        #expect(neckRow.sortOrder < chestRow.sortOrder)

        // Importing the real bundled file into a fresh context inserts exactly one row per seed.
        let context = try makeContainer()
        try MeasurementSeedImporter.importRows(rows, into: context)
        let all = try fetchAll(context)
        #expect(all.count == rows.count)
        // Persisted sortOrder matches the seed (not left at the model default of 0).
        for row in rows {
            let persisted = try #require(all.first { $0.id == row.id })
            #expect(persisted.sortOrder == row.sortOrder)
        }
    }
}
