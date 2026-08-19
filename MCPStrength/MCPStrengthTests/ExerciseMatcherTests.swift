//
//  ExerciseMatcherTests.swift
//  MCPStrengthTests
//

import Testing
import Foundation
@testable import MCPStrength

/// Pure-function tests for `ExerciseMatcher`. No `ModelContainer` needed: the matcher only reads
/// stored properties, so we build small in-memory arrays of `Exercise` values directly.
struct ExerciseMatcherTests {

    // A tiny helper to keep test bodies readable.
    private func make(
        _ name: String,
        aliases: [String] = [],
        bodyPart: BodyPart,
        category: ExerciseCategory = .machineOther
    ) -> Exercise {
        Exercise(
            name: name,
            aliases: aliases,
            bodyPart: bodyPart,
            category: category
        )
    }

    /// The regression library used across the headline cases. Mirrors the real failures from the
    /// spike: a `Chest Fly (Machine)` aliased "pec deck", a `Leg Press` that wrongly swallowed
    /// "JM Press", and a `Deadlift` filed under `.back` not `.legs`.
    private var library: [Exercise] {
        [
            make("Chest Fly (Machine)", aliases: ["pec deck", "machine fly"], bodyPart: .chest),
            make("Leg Press", bodyPart: .legs, category: .machineOther),
            make("Lateral Raise (Dumbbell)", bodyPart: .shoulders, category: .dumbbell),
            make("Close Grip Bench Press", bodyPart: .arms, category: .barbell),
            make("Deadlift", aliases: ["conventional deadlift"], bodyPart: .back, category: .barbell),
            make("Barbell Row", aliases: ["row"], bodyPart: .back, category: .barbell),
            make("Dumbbell Row", aliases: ["row"], bodyPart: .back, category: .dumbbell),
            make("Seated Cable Row", aliases: ["row"], bodyPart: .back, category: .machineOther),
        ]
    }

    // (a) Word-order variant that already worked and must keep working.
    @Test func dumbbellLateralRaiseRanksLateralRaiseDumbbellFirst() {
        let results = ExerciseMatcher.rank(
            query: "Dumbbell Lateral Raise",
            bodyPartHint: nil,
            in: library
        )
        #expect(results.first?.name == "Lateral Raise (Dumbbell)")
    }

    // (b) Alias resolves a synonym sharing no spelling with the name.
    @Test func pecDeckResolvesToChestFlyMachineViaAlias() {
        let results = ExerciseMatcher.rank(
            query: "Pec Deck",
            bodyPartHint: nil,
            in: library
        )
        #expect(results.first?.name == "Chest Fly (Machine)")
    }

    // (c) The headline bug: "JM Press" must NOT rank Leg Press first when an arms hint is given.
    // The library deliberately contains NO "jm press" name or alias, so the only thing that can
    // lift the arms candidate (Close Grip Bench Press, which shares only "press") above Leg Press
    // (which also shares "press") is the body-part hint boosting the arms entry. This tests the
    // hint's ranking role directly.
    @Test func jmPressWithArmsHintDoesNotRankLegPressFirst() {
        let results = ExerciseMatcher.rank(
            query: "JM Press",
            bodyPartHint: .arms,
            in: library
        )
        #expect(results.first?.name != "Leg Press")
        // The arms candidate, boosted by the hint, wins despite sharing fewer words.
        #expect(results.first?.name == "Close Grip Bench Press")
        // And Leg Press is still present — the hint ranked, it did not filter.
        #expect(results.contains { $0.name == "Leg Press" })
    }

    // (d) The single most important rule: the hint RANKS, it never FILTERS. Deadlift is filed
    // under .back; a .legs hint must still RETURN it, not merely rank it low.
    @Test func legsHintDoesNotFilterOutDeadliftFiledUnderBack() {
        let results = ExerciseMatcher.rank(
            query: "Deadlift",
            bodyPartHint: .legs,
            in: library
        )
        #expect(results.contains { $0.name == "Deadlift" })
    }

    // Ambiguity: an alias shared by several exercises returns multiple candidates rather than
    // silently picking one.
    @Test func ambiguousAliasReturnsMultipleCandidates() {
        let results = ExerciseMatcher.rank(
            query: "row",
            bodyPartHint: nil,
            in: library
        )
        let names = Set(results.map(\.name))
        #expect(names.contains("Barbell Row"))
        #expect(names.contains("Dumbbell Row"))
        #expect(names.contains("Seated Cable Row"))
        #expect(results.count >= 3)
    }

    // A query with no signal in the library returns nothing — an honest "no confident match".
    @Test func nonsenseQueryReturnsNoConfidentMatch() {
        let results = ExerciseMatcher.suggest(
            query: "Zyzzyva",
            bodyPartHint: nil,
            in: library
        )
        #expect(results.isEmpty)
    }

    // Empty query is a no-op.
    @Test func emptyQueryReturnsNothing() {
        let results = ExerciseMatcher.rank(
            query: "   ",
            bodyPartHint: nil,
            in: library
        )
        #expect(results.isEmpty)
    }

    // Deterministic tie-break: two exercises with identical signal sort by name.
    @Test func tiesBreakByNameDeterministically() {
        let a = make("Alpha Press", bodyPart: .chest)
        let b = make("Beta Press", bodyPart: .chest)
        let results = ExerciseMatcher.rank(query: "Press", bodyPartHint: nil, in: [b, a])
        #expect(results.map(\.name) == ["Alpha Press", "Beta Press"])
    }
}
