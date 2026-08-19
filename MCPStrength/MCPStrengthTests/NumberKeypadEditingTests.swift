//
//  NumberKeypadEditingTests.swift
//  MCPStrengthTests
//
//  The keypad's editing rules and Next walk. The view is a grid of buttons;
//  a wrong step size or a Next that forgets to tick a set would pass every
//  snapshot and fail in the gym.
//

import Testing
import Foundation
@testable import MCPStrength

struct NumberKeypadEditingTests {

    // MARK: - Replace on first input

    @Test func firstDigitReplacesTheFocusedValue() {
        var editing = NumberKeypadEditing.focusing(kind: .weight(unit: .lbs), display: "90")
        editing.apply(.digit(1))
        editing.apply(.digit(3))
        editing.apply(.digit(5))
        #expect(editing.text == "135")
    }

    @Test func backspaceOnAFocusedValueClearsItRatherThanDeletingOneCharacter() {
        var editing = NumberKeypadEditing.focusing(kind: .weight(unit: .lbs), display: "90")
        editing.apply(.backspace)
        #expect(editing.text == "")
    }

    @Test func decimalOnAFocusedWeightStartsAFractionalValue() {
        var editing = NumberKeypadEditing.focusing(kind: .weight(unit: .lbs), display: "135")
        editing.apply(.decimalPoint)
        editing.apply(.digit(5))
        #expect(editing.text == "0.5")
    }

    // MARK: - Extra keys

    @Test func weightOffersADecimalAndRepsDoNot() {
        let weight = NumberKeypadEditing.focusing(kind: .weight(unit: .lbs), display: "")
        let reps = NumberKeypadEditing.focusing(kind: .reps(allowRange: false), display: "")
        let range = NumberKeypadEditing.focusing(kind: .reps(allowRange: true), display: "")
        let rest = NumberKeypadEditing.focusing(kind: .rest, display: "90")
        #expect(weight.extraKey == .decimalPoint)
        #expect(reps.extraKey == nil)
        #expect(range.extraKey == .hyphen)
        #expect(rest.extraKey == nil)
    }

    @Test func decimalIsIgnoredOnRepsAndRest() {
        var reps = NumberKeypadEditing.focusing(kind: .reps(allowRange: false), display: "8")
        reps.replaceOnNextInput = false
        reps.apply(.decimalPoint)
        #expect(reps.text == "8")

        var rest = NumberKeypadEditing.focusing(kind: .rest, display: "90")
        rest.replaceOnNextInput = false
        rest.apply(.decimalPoint)
        #expect(rest.text == "90")
    }

    @Test func hyphenOnATemplateRepsFieldStartsARangeFromTheCurrentValue() {
        var editing = NumberKeypadEditing.focusing(kind: .reps(allowRange: true), display: "6")
        editing.apply(.hyphen)
        editing.apply(.digit(8))
        #expect(editing.text == "6-8")
    }

    @Test func hyphenIsIgnoredWhenRangesAreNotAllowed() {
        var editing = NumberKeypadEditing.focusing(kind: .reps(allowRange: false), display: "8")
        editing.apply(.hyphen)
        #expect(editing.text == "8")
    }

    // MARK: - Stepping

    @Test func weightStepsByATwoAndAHalfPoundPlate() {
        var editing = NumberKeypadEditing.focusing(kind: .weight(unit: .lbs), display: "135")
        editing.apply(.plus)
        #expect(editing.text == "137.5")
        editing.apply(.minus)
        #expect(editing.text == "135")
    }

    @Test func weightStepsByAKiloChangePlateWhenMetric() {
        var editing = NumberKeypadEditing.focusing(kind: .weight(unit: .kg), display: "60")
        editing.apply(.plus)
        #expect(editing.text == "61.25")
    }

    @Test func plusOnAnEmptyWeightStartsAtThePlate() {
        var editing = NumberKeypadEditing.focusing(kind: .weight(unit: .lbs), display: "")
        editing.apply(.plus)
        #expect(editing.text == "2.5")
    }

    @Test func minusWillNotTakeAWeightBelowZero() {
        var editing = NumberKeypadEditing.focusing(kind: .weight(unit: .lbs), display: "2.5")
        editing.apply(.minus)
        #expect(editing.text == "")
        editing.apply(.minus)
        #expect(editing.text == "")
    }

    @Test func repsStepByOne() {
        var editing = NumberKeypadEditing.focusing(kind: .reps(allowRange: false), display: "8")
        editing.apply(.plus)
        #expect(editing.text == "9")
        editing.apply(.minus)
        editing.apply(.minus)
        #expect(editing.text == "7")
    }

    @Test func minusOnOneRepClearsTheFieldRatherThanWritingZero() {
        var editing = NumberKeypadEditing.focusing(kind: .reps(allowRange: false), display: "1")
        editing.apply(.minus)
        #expect(editing.text == "")
        #expect(RepRangeParser.parse(editing.text, allowRange: false) == .unset)
    }

    @Test func restStepsByTenSecondsAndTheChipShowsMinutes() {
        var editing = NumberKeypadEditing.focusing(kind: .rest, display: "90")
        #expect(editing.chipText == "1:30")
        editing.apply(.plus)
        #expect(editing.text == "100")
        #expect(editing.chipText == "1:40")
        editing.apply(.minus)
        editing.apply(.minus)
        #expect(editing.chipText == "1:20")
    }

    @Test func plusOnEmptyRestStartsAtTenSeconds() {
        var editing = NumberKeypadEditing.focusing(kind: .rest, display: "")
        editing.apply(.plus)
        #expect(editing.chipText == "0:10")
    }

    @Test func aStepLeavesTheNextDigitAsAReplacement() {
        var editing = NumberKeypadEditing.focusing(kind: .weight(unit: .lbs), display: "135")
        editing.apply(.plus)
        editing.apply(.digit(2))
        #expect(editing.text == "2")
    }

    // MARK: - Next walk (workout)

    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let d = UUID()

    /// Two exercises, two sets each: [a, b] then [c, d].
    private var twoByTwo: NumberKeypadLayout {
        NumberKeypadLayout(exercises: [[a, b], [c, d]])
    }

    @Test func nextOnWeightMovesToRepsWithoutCompleting() {
        let from = NumberKeypadAddress(setID: a, slot: .weight)
        let result = NumberKeypadEditing.advance(from: from, in: twoByTwo, completesSets: true)
        #expect(result == .focus(NumberKeypadAddress(setID: a, slot: .reps)))
    }

    @Test func nextOnRepsOfANonLastSetTicksItAndFocusesRest() {
        let from = NumberKeypadAddress(setID: a, slot: .reps)
        let result = NumberKeypadEditing.advance(from: from, in: twoByTwo, completesSets: true)
        #expect(result == .completeSet(
            focusRest: true,
            then: NumberKeypadAddress(setID: a, slot: .rest)
        ))
    }

    @Test func nextOnRepsOfAnExerciseLastSetJumpsToTheNextExerciseWeight() {
        let from = NumberKeypadAddress(setID: b, slot: .reps)
        let result = NumberKeypadEditing.advance(from: from, in: twoByTwo, completesSets: true)
        #expect(result == .completeSet(
            focusRest: false,
            then: NumberKeypadAddress(setID: c, slot: .weight)
        ))
    }

    @Test func nextOnRepsOfTheLastSetOfTheLastExerciseDismisses() {
        let from = NumberKeypadAddress(setID: d, slot: .reps)
        let result = NumberKeypadEditing.advance(from: from, in: twoByTwo, completesSets: true)
        #expect(result == .completeSet(focusRest: false, then: nil))
    }

    @Test func nextOnRestSkipsItAndMovesToTheNextSetWeight() {
        let from = NumberKeypadAddress(setID: a, slot: .rest)
        let result = NumberKeypadEditing.advance(from: from, in: twoByTwo, completesSets: true)
        #expect(result == .finishRest(then: NumberKeypadAddress(setID: b, slot: .weight)))
    }

    @Test func nextOnRestOfTheLastSetCrossesToTheNextExercise() {
        let from = NumberKeypadAddress(setID: b, slot: .rest)
        let result = NumberKeypadEditing.advance(from: from, in: twoByTwo, completesSets: true)
        #expect(result == .finishRest(then: NumberKeypadAddress(setID: c, slot: .weight)))
    }

    // MARK: - Next walk (template — no ticks)

    @Test func templateNextOnRepsMovesToTheNextSetWithoutCompleting() {
        let from = NumberKeypadAddress(setID: a, slot: .reps)
        let result = NumberKeypadEditing.advance(from: from, in: twoByTwo, completesSets: false)
        #expect(result == .focus(NumberKeypadAddress(setID: b, slot: .weight)))
    }

    @Test func templateNextOnTheLastRepsDismisses() {
        let from = NumberKeypadAddress(setID: d, slot: .reps)
        let result = NumberKeypadEditing.advance(from: from, in: twoByTwo, completesSets: false)
        #expect(result == .dismiss)
    }

    @Test func aUnknownSetDismissesRatherThanGuessing() {
        let from = NumberKeypadAddress(setID: UUID(), slot: .weight)
        let result = NumberKeypadEditing.advance(from: from, in: twoByTwo, completesSets: true)
        #expect(result == .dismiss)
    }
}
