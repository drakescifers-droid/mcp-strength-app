//
//  ExerciseTests.swift
//  MCPStrengthTests
//
//  `Exercise.trains(_:)` — the one predicate the library filter pills, the
//  matcher's body-part hint, and (via the same shape on the server) the MCP
//  tools all read, so "does Deadlift count as Legs" has exactly one answer
//  in the app. See docs/01-data-model.md § "Secondary body parts".
//

import Testing
import Foundation
@testable import MCPStrength

struct ExerciseTests {

    private func exercise(
        bodyPart: BodyPart,
        secondaryBodyParts: [BodyPart] = []
    ) -> Exercise {
        Exercise(
            name: "Test Exercise",
            bodyPart: bodyPart,
            secondaryBodyParts: secondaryBodyParts,
            category: .barbell
        )
    }

    @Test func trainsIsTrueForThePrimaryBodyPart() {
        let bench = exercise(bodyPart: .chest)
        #expect(bench.trains(.chest))
    }

    @Test func trainsIsFalseForAnUnrelatedBodyPart() {
        let bench = exercise(bodyPart: .chest)
        #expect(!bench.trains(.legs))
    }

    // THE WORKED EXAMPLE. Deadlift is filed primarily under Back — that
    // does not change — but it also trains Legs, and the app should say so.
    @Test func deadliftTrainsBothBackAndLegs() {
        let deadlift = exercise(bodyPart: .back, secondaryBodyParts: [.legs])
        #expect(deadlift.trains(.back), "primary is unchanged")
        #expect(deadlift.trains(.legs), "secondary is what this whole feature is for")
        #expect(!deadlift.trains(.chest))
    }

    // A fresh exercise with no secondaries set must not accidentally claim
    // every body part or none at all — the empty-array default has to mean
    // "no secondaries", not "untested" or "all of them".
    @Test func noSecondariesMeansOnlyThePrimaryTrains() {
        let squat = exercise(bodyPart: .legs)
        #expect(squat.secondaryBodyParts.isEmpty)
        for part in BodyPart.allCases where part != .legs {
            #expect(!squat.trains(part), "\(part) should not be trained by a legs-only exercise")
        }
    }

    // Multiple secondaries, not just one — the type is an array on purpose.
    @Test func anExerciseCanTrainMoreThanTwoBodyParts() {
        let cleanAndJerk = exercise(bodyPart: .olympic, secondaryBodyParts: [.legs, .back, .shoulders])
        #expect(cleanAndJerk.trains(.olympic))
        #expect(cleanAndJerk.trains(.legs))
        #expect(cleanAndJerk.trains(.back))
        #expect(cleanAndJerk.trains(.shoulders))
        #expect(!cleanAndJerk.trains(.arms))
    }

    // MARK: - Display

    @Test func bodyPartsDisplayNameListsPrimaryFirstThenSecondaries() {
        let deadlift = exercise(bodyPart: .back, secondaryBodyParts: [.legs])
        #expect(deadlift.bodyPartsDisplayName == "Back, Legs")
    }

    @Test func bodyPartsDisplayNameWithNoSecondariesIsJustThePrimary() {
        let squat = exercise(bodyPart: .legs)
        #expect(squat.bodyPartsDisplayName == "Legs")
    }
}
