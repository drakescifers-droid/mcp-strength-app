//
//  MeasurementLatestTests.swift
//  MCPStrengthTests
//

import Testing
import Foundation
import SwiftData
@testable import MCPStrength

/// Tests for `MeasurementLatest` — the pure latest-per-type selector. Driven with fixed dates
/// and fixture orderings; never touches a view body. An in-memory container is used only to build
/// `MeasurementEntry` instances that carry a live `type` relationship.
struct MeasurementLatestTests {

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

    // Fixed dates (oldest -> newest).
    private let jan1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let feb1 = Date(timeIntervalSince1970: 1_700_000_000 + 86_400 * 31)
    private let mar1 = Date(timeIntervalSince1970: 1_700_000_000 + 86_400 * 60)

    // (1) latest returns the most recent entry, NOT the first inserted. Fixtures are ordered so a
    // naive "return the first matching entry" implementation fails: the oldest is inserted first.
    @Test func latestReturnsMostRecentNotFirstInserted() throws {
        let context = try makeContainer()
        let type = MeasurementType(name: "Weight", group: .core)
        context.insert(type)

        let oldest = MeasurementEntry(value: 180, unit: "lb", recordedAt: jan1, type: type)
        let newest = MeasurementEntry(value: 186.95, unit: "lb", recordedAt: mar1, type: type)
        let middle = MeasurementEntry(value: 183, unit: "lb", recordedAt: feb1, type: type)
        context.insert(oldest)
        context.insert(newest) // inserted second, but is the latest by date
        context.insert(middle)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<MeasurementEntry>())
        let latest = MeasurementLatest.latest(in: entries)
        #expect(latest?.id == newest.id)
        #expect(latest?.value == 186.95)
    }

    // (2) A type with no entries reports no latest value rather than zero.
    @Test func typeWithNoEntriesHasNoLatest() throws {
        let context = try makeContainer()
        let type = MeasurementType(name: "Left Calf", group: .bodyPart)
        context.insert(type)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<MeasurementEntry>())
        #expect(MeasurementLatest.latest(in: entries) == nil)

        // latestByTypeID has no key for a type with no entries (unknown, not zero).
        let byID = MeasurementLatest.latestByTypeID(entries)
        #expect(byID[type.id] == nil)
    }

    // (3) Ties on the same timestamp break toward the most recently created (later in the input
    // array).
    @Test func tiesBreakTowardMostRecentlyCreated() throws {
        let context = try makeContainer()
        let type = MeasurementType(name: "Waist", group: .bodyPart)
        context.insert(type)

        let first = MeasurementEntry(value: 32.0, unit: "in", recordedAt: feb1, type: type)
        let second = MeasurementEntry(value: 33.5, unit: "in", recordedAt: feb1, type: type)
        context.insert(first)
        context.insert(second) // same date, created later
        try context.save()

        let entries = try context.fetch(FetchDescriptor<MeasurementEntry>())
        // The fetch order is not guaranteed to match insertion order, so pass entries explicitly
        // in creation order to exercise the documented tiebreak contract.
        let ordered = [first, second]
        let latest = MeasurementLatest.latest(in: ordered)
        #expect(latest?.id == second.id)
    }

    // (4) latestByTypeID groups correctly and returns the latest per type.
    @Test func latestByTypeIDGroupsCorrectly() throws {
        let context = try makeContainer()
        let weight = MeasurementType(name: "Weight", group: .core)
        let neck = MeasurementType(name: "Neck", group: .bodyPart)
        context.insert(weight)
        context.insert(neck)

        context.insert(MeasurementEntry(value: 180, unit: "lb", recordedAt: jan1, type: weight))
        context.insert(MeasurementEntry(value: 16.0, unit: "in", recordedAt: jan1, type: neck))
        context.insert(MeasurementEntry(value: 186.95, unit: "lb", recordedAt: mar1, type: weight))
        context.insert(MeasurementEntry(value: 16.5, unit: "in", recordedAt: feb1, type: neck))
        try context.save()

        let entries = try context.fetch(FetchDescriptor<MeasurementEntry>())
        let byID = MeasurementLatest.latestByTypeID(entries)

        #expect(byID.count == 2)
        #expect(byID[weight.id]?.value == 186.95)
        #expect(byID[neck.id]?.value == 16.5)
    }

    // (5) Deleting an entry updates what latest-per-type returns.
    @Test func deletingAnEntryUpdatesLatest() throws {
        let context = try makeContainer()
        let type = MeasurementType(name: "Weight", group: .core)
        context.insert(type)

        let older = MeasurementEntry(value: 180, unit: "lb", recordedAt: feb1, type: type)
        let newer = MeasurementEntry(value: 186.95, unit: "lb", recordedAt: mar1, type: type)
        context.insert(older)
        context.insert(newer)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<MeasurementEntry>())
        #expect(MeasurementLatest.latest(in: entries)?.id == newer.id)

        // Delete the newest; latest should now be the older entry.
        context.delete(newer)
        try context.save()

        let after = try context.fetch(FetchDescriptor<MeasurementEntry>())
        let latest = MeasurementLatest.latest(in: after)
        #expect(latest?.id == older.id)
        #expect(latest?.value == 180)
    }
}
