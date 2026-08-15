//
//  ExerciseSeedImporterTests.swift
//  MCPStrengthTests
//

import Testing
import Foundation
import SwiftData
@testable import MCPStrength

/// Tests for `ExerciseSeedImporter`. The core upsert is exercised with fixture rows against an
/// in-memory `ModelContainer`, never through bundle plumbing. One extra test loads the real
/// bundled `exercise-seed.json` to keep the shipped file honest.
struct ExerciseSeedImporterTests {

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContext {
        let schema = Schema([
            Exercise.self,
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
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private static let chestFlyID = UUID(uuidString: "8de7cc2a-06ac-40fd-b99c-e5461f67a107")!
    private static let legPressID = UUID(uuidString: "99fb367c-8860-467d-8bc3-05e7545312be")!
    private static let lateralRaiseID = UUID(uuidString: "2aa0a5f0-2a1b-4e0b-83c8-9e3b1578fa5d")!
    private static let deadliftID = UUID(uuidString: "ccd9e6e1-38a5-46d0-bc1b-eca51aed41bc")!

    /// A small, hand-built fixture set (NOT the bundled file) so tests drive the pure core
    /// directly and never depend on bundle plumbing.
    private var fixtureRows: [ExerciseSeedRow] {
        [
            ExerciseSeedRow(id: Self.chestFlyID, name: "Chest Fly (Machine)",
                            bodyPart: .chest, category: .machineOther, aliases: ["pec deck", "machine fly"]),
            ExerciseSeedRow(id: Self.legPressID, name: "Leg Press",
                            bodyPart: .legs, category: .machineOther, aliases: ["leg press"]),
            ExerciseSeedRow(id: Self.lateralRaiseID, name: "Lateral Raise (Dumbbell)",
                            bodyPart: .shoulders, category: .dumbbell, aliases: ["side raise"]),
            ExerciseSeedRow(id: Self.deadliftID, name: "Deadlift (Barbell)",
                            bodyPart: .back, category: .barbell, aliases: ["deadlift"]),
        ]
    }

    private func fetchAll(_ context: ModelContext) throws -> [Exercise] {
        try context.fetch(FetchDescriptor<Exercise>())
    }

    // MARK: - Required tests

    // (1) Importing a fixture set inserts the expected rows, with aliases round-tripping.
    @Test func importInsertsRowsAndRoundTripsAliases() throws {
        let context = try makeContainer()
        try ExerciseSeedImporter.importRows(fixtureRows, into: context)

        let all = try fetchAll(context)
        #expect(all.count == 4)

        let chestFly = try #require(all.first { $0.id == Self.chestFlyID })
        #expect(chestFly.name == "Chest Fly (Machine)")
        #expect(chestFly.bodyPart == .chest)
        #expect(chestFly.category == .machineOther)
        #expect(chestFly.aliases == ["pec deck", "machine fly"])

        let deadlift = try #require(all.first { $0.id == Self.deadliftID })
        #expect(deadlift.name == "Deadlift (Barbell)")
        #expect(deadlift.bodyPart == .back) // deliberately .back, not .legs
        #expect(deadlift.category == .barbell)
    }

    // (2) Importing the SAME set twice leaves the count unchanged (idempotency) and the ids
    // identical (stability).
    @Test func importingTwiceIsIdempotentAndKeepsStableIds() throws {
        let context = try makeContainer()
        try ExerciseSeedImporter.importRows(fixtureRows, into: context)
        let afterFirst = try fetchAll(context)
        let firstIDs = Set(afterFirst.map(\.id))

        try ExerciseSeedImporter.importRows(fixtureRows, into: context)
        let afterSecond = try fetchAll(context)
        let secondIDs = Set(afterSecond.map(\.id))

        #expect(afterSecond.count == afterFirst.count)
        #expect(afterSecond.count == 4)
        #expect(secondIDs == firstIDs)
        #expect(secondIDs == Set([Self.chestFlyID, Self.legPressID, Self.lateralRaiseID, Self.deadliftID]))
    }

    // (3) Importing a set with one extra row adds exactly one.
    @Test func importingAnExtraRowAddsExactlyOne() throws {
        let context = try makeContainer()
        try ExerciseSeedImporter.importRows(fixtureRows, into: context)
        #expect(try fetchAll(context).count == 4)

        let extraID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        var withExtra = fixtureRows
        withExtra.append(
            ExerciseSeedRow(id: extraID, name: "Hammer Curl (Dumbbell)",
                            bodyPart: .arms, category: .dumbbell, aliases: ["hammer curl"])
        )

        try ExerciseSeedImporter.importRows(withExtra, into: context)
        let all = try fetchAll(context)
        #expect(all.count == 5)
        #expect(all.contains { $0.id == extraID })
    }

    // (4) A user-created exercise (isCustom == true) still exists after a re-import.
    @Test func userCreatedExerciseSurvivesReimport() throws {
        let context = try makeContainer()
        let userExercise = Exercise(
            name: "My Custom Move",
            aliases: [],
            bodyPart: .other,
            category: .repsOnly,
            isCustom: true,
            focusMetric: .totalReps,
            notes: "do not delete me"
        )
        context.insert(userExercise)
        try context.save()
        let userID = userExercise.id

        try ExerciseSeedImporter.importRows(fixtureRows, into: context)
        #expect(try fetchAll(context).count == 5)

        try ExerciseSeedImporter.importRows(fixtureRows, into: context)
        let all = try fetchAll(context)
        #expect(all.count == 5) // 4 seeded + 1 user, no dupes

        let survivor = try #require(all.first { $0.id == userID })
        #expect(survivor.isCustom == true)
        #expect(survivor.name == "My Custom Move")
        #expect(survivor.notes == "do not delete me")
    }

    // (5) Seeded rows have isCustom == false.
    @Test func seededRowsAreNotCustom() throws {
        let context = try makeContainer()
        try ExerciseSeedImporter.importRows(fixtureRows, into: context)

        let all = try fetchAll(context)
        #expect(all.count == 4)
        #expect(all.allSatisfy { $0.isCustom == false })
    }

    // MARK: - Extra: contract details worth pinning

    // A name change with the same id updates the name in place (the id wins), and preserves the
    // user's preference fields on that exercise.
    @Test func nameChangeWithSameIdUpdatesInPlaceAndPreservesUserPreferences() throws {
        let context = try makeContainer()
        try ExerciseSeedImporter.importRows(fixtureRows, into: context)

        // Simulate a user customizing a seeded exercise.
        let seeded = try #require(try fetchAll(context).first { $0.id == Self.chestFlyID })
        seeded.focusMetric = .totalReps
        seeded.notes = "favorite machine"
        seeded.barType = .other
        try context.save()

        // Re-import the same id with a renamed exercise and a dropped alias.
        let renamed = [
            ExerciseSeedRow(id: Self.chestFlyID, name: "Pec Fly (Machine)",
                            bodyPart: .chest, category: .machineOther, aliases: ["pec deck"]),
            // also re-import the rest so the set is consistent
        ] + Array(fixtureRows.dropFirst().map { row in
            ExerciseSeedRow(id: row.id, name: row.name, bodyPart: row.bodyPart,
                            category: row.category, aliases: row.aliases)
        })
        try ExerciseSeedImporter.importRows(renamed, into: context)

        let all = try fetchAll(context)
        #expect(all.count == 4) // no new row; updated in place
        let updated = try #require(all.first { $0.id == Self.chestFlyID })
        #expect(updated.name == "Pec Fly (Machine)") // the id won; name updated
        #expect(updated.aliases == ["pec deck"])
        #expect(updated.isCustom == false)
        // User preferences survive the re-seed.
        #expect(updated.focusMetric == .totalReps)
        #expect(updated.notes == "favorite machine")
        #expect(updated.barType == .other)
    }

    // The decoder accepts both the top-level array and the {"exercises": [...]} object form.
    @Test func decoderAcceptsBothSeedShapes() throws {
        let arrayForm = """
        [{"id":"8de7cc2a-06ac-40fd-b99c-e5461f67a107","name":"Chest Fly (Machine)","bodyPart":"chest","category":"machineOther","aliases":["pec deck"]}]
        """.data(using: .utf8)!
        let decodedArray = try ExerciseSeedImporter.decodeRows(arrayForm)
        #expect(decodedArray.count == 1)
        #expect(decodedArray.first?.name == "Chest Fly (Machine)")

        let objectForm = """
        {"exercises":[{"id":"99fb367c-8860-467d-8bc3-05e7545312be","name":"Leg Press","bodyPart":"legs","category":"machineOther"}]}
        """.data(using: .utf8)!
        let decodedObject = try ExerciseSeedImporter.decodeRows(objectForm)
        #expect(decodedObject.count == 1)
        #expect(decodedObject.first?.name == "Leg Press")
        #expect(decodedObject.first?.aliases == nil) // missing aliases key -> nil; importer coalesces to []
    }

    // MARK: - Bundled seed file (keeps the shipped file honest)

    // The real `exercise-seed.json` decodes, covers every category, has unique ids and unique
    // (case-insensitive) names, and contains the entries the rest of the app/docs reference.
    @Test func bundledSeedFileIsValidAndCoversAllCategories() throws {
        let url = try #require(Bundle(for: Exercise.self).url(forResource: "exercise-seed", withExtension: "json"),
                               "exercise-seed.json must ship in the app bundle")
        let data = try Data(contentsOf: url)
        let rows = try ExerciseSeedImporter.decodeRows(data)

        #expect(rows.count >= 20)

        // Unique ids and unique (case-insensitive) names.
        let ids = rows.map(\.id)
        #expect(Set(ids).count == ids.count)
        let lowerNames = rows.map { $0.name.lowercased() }
        #expect(Set(lowerNames).count == lowerNames.count)

        // Every one of the eight categories is present.
        let categories = Set(rows.map(\.category))
        let allCategories: Set<ExerciseCategory> = [
            .barbell, .dumbbell, .machineOther, .weightedBodyweight,
            .assistedBodyweight, .repsOnly, .cardio, .duration,
        ]
        #expect(categories == allCategories)

        // The specific entries the rest of the app and the matcher's tests depend on.
        func find(_ name: String) -> ExerciseSeedRow? {
            rows.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
        let chestFly = try #require(find("Chest Fly (Machine)"))
        #expect(chestFly.aliases?.contains("pec deck") == true)
        #expect(chestFly.bodyPart == .chest)

        let lateralRaise = try #require(find("Lateral Raise (Dumbbell)"))
        #expect(lateralRaise.category == .dumbbell)

        let deadlift = try #require(find("Deadlift (Barbell)"))
        #expect(deadlift.bodyPart == .back) // deliberately back, not legs — matcher depends on it

        let legPress = try #require(find("Leg Press"))
        #expect(legPress.bodyPart == .legs)

        try #require(find("Bench Press (Barbell)"))
        try #require(find("Squat (Barbell)"))

        // Importing the real bundled file into a fresh context inserts exactly one row per seed
        // row and marks them all as non-custom.
        let context = try makeContainer()
        try ExerciseSeedImporter.importRows(rows, into: context)
        let all = try fetchAll(context)
        #expect(all.count == rows.count)
        #expect(all.allSatisfy { $0.isCustom == false })
    }
}
