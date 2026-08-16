//
//  TemplateSaveDiffTests.swift
//  MCPStrengthTests
//
//  Covers TemplateSaveDiff.plan — the identity rule save() uses to update
//  a template in place instead of tombstoning its whole subtree. Lives in
//  Workout/ (no SwiftUI / SwiftData) so it can be tested without a store.
//

import Testing
import Foundation
@testable import MCPStrength

struct TemplateSaveDiffTests {

    private let exA = UUID()
    private let exB = UUID()
    private let exC = UUID()
    private let setA1 = UUID()
    private let setA2 = UUID()
    private let setB1 = UUID()
    private let setNew = UUID()

    // THE regression: an unchanged save must not look like a delete+recreate.
    // Empty added and empty removed, at both levels, is the whole point of
    // carrying real row ids through the drafts.
    @Test func unchangedSaveProducesNoInsertionsOrTombstones() {
        let plan = TemplateSaveDiff.plan(
            drafts: [
                (id: exA, setIDs: [setA1, setA2]),
                (id: exB, setIDs: [setB1]),
            ],
            existing: [
                (id: exA, setIDs: [setA1, setA2]),
                (id: exB, setIDs: [setB1]),
            ]
        )
        #expect(plan.exercises.added.isEmpty)
        #expect(plan.exercises.removed.isEmpty)
        #expect(plan.exercises.kept.map(\.id) == [exA, exB])
        #expect(plan.exercises.kept.map(\.newOrder) == [0, 1])

        let setsA = plan.setsByKeptExercise[exA]
        #expect(setsA?.added.isEmpty == true)
        #expect(setsA?.removed.isEmpty == true)
        #expect(setsA?.kept.map(\.id) == [setA1, setA2])

        let setsB = plan.setsByKeptExercise[exB]
        #expect(setsB?.added.isEmpty == true)
        #expect(setsB?.removed.isEmpty == true)
        #expect(setsB?.kept.map(\.id) == [setB1])
    }

    // A surviving id is KEPT, even when nothing about it moved. That is
    // what makes a no-op save a no-op write.
    @Test func survivingRowIsKeptUnchanged() {
        let plan = TemplateSaveDiff.plan(
            drafts: [(id: exA, setIDs: [setA1])],
            existing: [(id: exA, setIDs: [setA1])]
        )
        #expect(plan.exercises.kept == [TemplateSaveDiff.Placement(id: exA, newOrder: 0)])
        #expect(plan.setsByKeptExercise[exA]?.kept == [TemplateSaveDiff.Placement(id: setA1, newOrder: 0)])
        #expect(plan.exercises.added.isEmpty)
        #expect(plan.exercises.removed.isEmpty)
    }

    // Fields are not an input. An id that survives is KEPT so save() can
    // write a new weight (or a swapped Exercise) onto the existing row.
    // Adding and removing a sibling set must not reclassify the parent
    // as removed+added — that is replace-everything at the other level.
    @Test func survivingRowIsUpdatedInPlace() throws {
        let plan = TemplateSaveDiff.plan(
            drafts: [(id: exA, setIDs: [setA1, setNew])],
            existing: [(id: exA, setIDs: [setA1, setA2])]
        )
        #expect(plan.exercises.kept.map(\.id) == [exA])
        #expect(plan.exercises.added.isEmpty)
        #expect(plan.exercises.removed.isEmpty)

        let sets = try #require(plan.setsByKeptExercise[exA])
        #expect(sets.kept.map(\.id) == [setA1])
        #expect(sets.added.map(\.id) == [setNew])
        #expect(sets.removed == [setA2])
    }

    @Test func newDraftIdIsAdded() {
        let plan = TemplateSaveDiff.plan(
            drafts: [
                (id: exA, setIDs: [setA1]),
                (id: exB, setIDs: [setB1]),
            ],
            existing: [(id: exA, setIDs: [setA1])]
        )
        #expect(plan.exercises.added == [TemplateSaveDiff.Placement(id: exB, newOrder: 1)])
        #expect(plan.exercises.removed.isEmpty)
        #expect(plan.exercises.kept.map(\.id) == [exA])
        // A brand-new exercise has no set-level plan: every set is new and
        // is inserted with the exercise.
        #expect(plan.setsByKeptExercise[exB] == nil)
    }

    @Test func missingExistingIdIsRemoved() {
        let plan = TemplateSaveDiff.plan(
            drafts: [(id: exA, setIDs: [setA1])],
            existing: [
                (id: exA, setIDs: [setA1]),
                (id: exB, setIDs: [setB1]),
            ]
        )
        #expect(plan.exercises.removed == [exB])
        #expect(plan.exercises.added.isEmpty)
        #expect(plan.exercises.kept.map(\.id) == [exA])
        // SoftDelete.templateExercise cascades; the removed exercise must
        // not also appear as a set-level plan.
        #expect(plan.setsByKeptExercise[exB] == nil)
    }

    // Reorder is KEPT with a new index, never a delete plus an insert.
    // Same ids in a different sequence must not produce tombstones.
    @Test func reorderKeepsIdsAndRewritesOrder() throws {
        let plan = TemplateSaveDiff.plan(
            drafts: [
                (id: exB, setIDs: [setB1]),
                (id: exA, setIDs: [setA2, setA1]),
                (id: exC, setIDs: []),
            ],
            existing: [
                (id: exA, setIDs: [setA1, setA2]),
                (id: exB, setIDs: [setB1]),
                (id: exC, setIDs: []),
            ]
        )
        #expect(plan.exercises.added.isEmpty)
        #expect(plan.exercises.removed.isEmpty)
        #expect(plan.exercises.kept.map(\.id) == [exB, exA, exC])
        #expect(plan.exercises.kept.map(\.newOrder) == [0, 1, 2])

        let setsA = try #require(plan.setsByKeptExercise[exA])
        #expect(setsA.added.isEmpty)
        #expect(setsA.removed.isEmpty)
        #expect(setsA.kept.map(\.id) == [setA2, setA1])
        #expect(setsA.kept.map(\.newOrder) == [0, 1])
    }

    // classify is the same rule plan() uses at each level; a lone new id
    // against an empty existing list is how a brand-new template classifies.
    @Test func classifyEmptyExistingAddsEveryDraft() {
        let level = TemplateSaveDiff.classify(
            draftIDs: [exA, exB],
            existingIDs: []
        )
        #expect(level.kept.isEmpty)
        #expect(level.removed.isEmpty)
        #expect(level.added.map(\.id) == [exA, exB])
        #expect(level.added.map(\.newOrder) == [0, 1])
    }
}
