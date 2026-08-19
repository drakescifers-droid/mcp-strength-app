//
//  NumberKeypadEditing.swift
//  MCPStrength
//
//  The custom number keypad's editing rules, kept pure so the visual keypad
//  cannot invent a second idea of what a key does.
//
//  Measured in the reference app on 2026-08-19:
//
//  * Weight − / + steps by a 2.5 lb change plate (`WeightUnits.keypadStep`).
//  * Reps − / + steps by 1.
//  * Rest − / + steps by 10 seconds.
//  * First input after focusing a field REPLACES the current value. That is
//    also the caret-position trap's fix: tapping a right-aligned chip no
//    longer has a caret to land in the wrong half of.
//  * Next is not "move focus". On the workout screen it completes things —
//    see `advance(from:in:completesSets:)`.
//

import Foundation

// MARK: - Kind

/// Which field the keypad is editing. Decides the extra key, the step, and
/// whether a decimal / hyphen is accepted.
nonisolated enum NumberKeypadKind: Equatable, Sendable {
    /// A weight in the DISPLAY unit. Decimal allowed. Step is `keypadStep`.
    case weight(unit: WeightUnit)
    /// Reps. Integer. A hyphen when `allowRange` (template `6-8`). Step is 1.
    case reps(allowRange: Bool)
    /// Rest duration in SECONDS. Displayed as `m:ss`. Step is 10 seconds.
    case rest
    /// A generic decimal (measurements). Step is 1 of the displayed unit.
    case decimal
}

// MARK: - Input

/// One tap on the keypad, excluding Next / dismiss which the screen owns.
nonisolated enum NumberKeypadInput: Equatable, Sendable {
    case digit(Int)
    case decimalPoint
    case hyphen
    case backspace
    case plus
    case minus
}

// MARK: - Address / layout / Next

/// One entry slot on one set. Identity is the set's id so inserting warm-ups
/// above a focused row cannot silently retarget the keypad.
nonisolated struct NumberKeypadAddress: Equatable, Hashable, Sendable {
    enum Slot: Equatable, Hashable, Sendable {
        case weight
        case reps
        case rest
    }

    var setID: UUID
    var slot: Slot
}

/// The sets on screen, grouped the way Next walks them: one inner array per
/// exercise, in display order.
nonisolated struct NumberKeypadLayout: Equatable, Sendable {
    var exercises: [[UUID]]
}

/// What Next does, given where focus is. The VIEW performs the side effects
/// (tick the set, start or skip rest); this type only says which ones.
nonisolated enum NumberKeypadAdvance: Equatable, Sendable {
    /// Move focus. Weight → reps, and every template-screen walk.
    case focus(NumberKeypadAddress)
    /// Tick the current set. `focusRest` is the non-last-set case: start rest
    /// and put the keypad on that set's timer. Otherwise jump to `then`
    /// (next exercise's weight) or dismiss when `then` is nil.
    case completeSet(focusRest: Bool, then: NumberKeypadAddress?)
    /// Skip a running rest and move to `then` (next set's weight), or dismiss.
    case finishRest(then: NumberKeypadAddress?)
    case dismiss
}

// MARK: - Session

/// The in-progress edit: the buffer, whether the next key replaces it, and
/// the field kind. Mutated only through `apply(_:)`.
nonisolated struct NumberKeypadEditing: Equatable, Sendable {
    var kind: NumberKeypadKind
    var text: String
    var replaceOnNextInput: Bool

    /// Rest − / +, in seconds. Measured in the reference, not chosen.
    static let restStep: Int = 10

    static func focusing(kind: NumberKeypadKind, display: String) -> NumberKeypadEditing {
        NumberKeypadEditing(kind: kind, text: display, replaceOnNextInput: true)
    }

    /// Bottom-left extra key. `nil` leaves a blank so `0` stays centred.
    var extraKey: NumberKeypadInput? {
        switch kind {
        case .weight, .decimal: return .decimalPoint
        case .reps(let allowRange) where allowRange: return .hyphen
        case .reps, .rest: return nil
        }
    }

    /// What the chip should show. Rest is `m:ss` of the seconds buffer; every
    /// other kind is the buffer itself (so `"135."` can exist mid-keystroke).
    var chipText: String {
        switch kind {
        case .rest:
            return Self.formatRest(parsedRestSeconds)
        case .weight, .reps, .decimal:
            return text
        }
    }

    mutating func apply(_ input: NumberKeypadInput) {
        switch input {
        case .digit(let d):
            guard (0...9).contains(d) else { return }
            typeDigit(d)
        case .decimalPoint:
            typeDecimal()
        case .hyphen:
            typeHyphen()
        case .backspace:
            deleteBackward()
        case .plus:
            step(by: 1)
        case .minus:
            step(by: -1)
        }
    }

    // MARK: Typing

    private mutating func typeDigit(_ digit: Int) {
        if replaceOnNextInput {
            text = String(digit)
            replaceOnNextInput = false
            return
        }
        text.append(String(digit))
    }

    private mutating func typeDecimal() {
        switch kind {
        case .weight, .decimal:
            break
        case .reps, .rest:
            return
        }
        if replaceOnNextInput {
            text = "0."
            replaceOnNextInput = false
            return
        }
        guard !text.contains(".") else { return }
        text.append(text.isEmpty ? "0." : ".")
    }

    private mutating func typeHyphen() {
        guard case .reps(let allowRange) = kind, allowRange else { return }
        if replaceOnNextInput {
            // Hyphen never replaces. Focused "8" then `−` starts a range
            // from the current value rather than wiping it to "-".
            replaceOnNextInput = false
        }
        guard !text.isEmpty, !text.contains("-"), !text.contains("–") else { return }
        text.append("-")
    }

    private mutating func deleteBackward() {
        if replaceOnNextInput {
            text = ""
            replaceOnNextInput = false
            return
        }
        if !text.isEmpty {
            text.removeLast()
        }
    }

    // MARK: − / +

    private mutating func step(by direction: Int) {
        switch kind {
        case .weight(let unit):
            let current = Double(text) ?? 0
            let next = max(0, current + Double(direction) * WeightUnits.keypadStep(for: unit))
            text = next == 0 ? "" : PreviousText.formatWeight(next)
        case .reps(let allowRange):
            stepReps(by: direction, allowRange: allowRange)
        case .rest:
            let current = parsedRestSeconds
            let next = max(0, current + direction * Self.restStep)
            text = next == 0 ? "" : String(next)
        case .decimal:
            let current = Double(text) ?? 0
            let next = max(0, current + Double(direction))
            text = next == 0 ? "" : PreviousText.formatWeight(next)
        }
        replaceOnNextInput = true
    }

    private mutating func stepReps(by direction: Int, allowRange: Bool) {
        switch RepRangeParser.parse(text, allowRange: allowRange) {
        case .valid(.fixed(let n)):
            let next = n + direction
            text = next < 1 ? "" : String(next)
        case .valid(.range(let start, let end)):
            let nextEnd = end + direction
            if nextEnd < start {
                text = String(start)
            } else {
                text = RepRangeParser.format(.range(start: start, end: nextEnd))
            }
        case .unset, .invalid:
            if direction > 0 {
                text = "1"
            }
        }
    }

    private var parsedRestSeconds: Int {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Int(trimmed), value >= 0 else { return 0 }
        return value
    }

    /// `m:ss` for a rest duration. Same spelling as `formatMinutesSeconds`.
    static func formatRest(_ seconds: Int) -> String {
        let m = max(0, seconds) / 60
        let s = max(0, seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Next

extension NumberKeypadEditing {

    /// Where Next takes the keypad, given the sets on screen.
    ///
    /// Workout (`completesSets: true`), measured in the reference:
    /// * weight → reps of the same set (no tick);
    /// * reps of a non-last set → tick, start rest, focus that rest;
    /// * reps of an exercise's last set → tick, jump to the next exercise's
    ///   weight (or dismiss if there is no next exercise);
    /// * rest → skip the running rest, next set's weight (crossing into the
    ///   next exercise when this was the last set).
    ///
    /// Template (`completesSets: false`) has nothing to complete, so Next only
    /// walks: weight → reps → next set's weight, and rest (tapped, not tabbed
    /// onto) → next set's weight.
    static func advance(
        from address: NumberKeypadAddress,
        in layout: NumberKeypadLayout,
        completesSets: Bool
    ) -> NumberKeypadAdvance {
        guard let place = layout.place(of: address.setID) else { return .dismiss }
        switch address.slot {
        case .weight:
            return .focus(NumberKeypadAddress(setID: address.setID, slot: .reps))
        case .reps:
            if completesSets {
                if layout.isLastSet(at: place) {
                    return .completeSet(focusRest: false, then: layout.firstWeight(afterExercise: place.exercise))
                }
                return .completeSet(
                    focusRest: true,
                    then: NumberKeypadAddress(setID: address.setID, slot: .rest)
                )
            }
            return layout.nextWeight(after: place).map { .focus($0) } ?? .dismiss
        case .rest:
            let next = layout.nextWeight(after: place)
            if completesSets {
                return .finishRest(then: next)
            }
            return next.map { .focus($0) } ?? .dismiss
        }
    }
}

extension NumberKeypadLayout {

    fileprivate func place(of setID: UUID) -> (exercise: Int, set: Int)? {
        for (e, sets) in exercises.enumerated() {
            if let s = sets.firstIndex(of: setID) {
                return (e, s)
            }
        }
        return nil
    }

    fileprivate func isLastSet(at place: (exercise: Int, set: Int)) -> Bool {
        guard exercises.indices.contains(place.exercise) else { return true }
        return place.set == exercises[place.exercise].count - 1
    }

    /// Next set's weight in this exercise, or the next exercise's first weight.
    fileprivate func nextWeight(after place: (exercise: Int, set: Int)) -> NumberKeypadAddress? {
        let sets = exercises[place.exercise]
        if place.set + 1 < sets.count {
            return NumberKeypadAddress(setID: sets[place.set + 1], slot: .weight)
        }
        return firstWeight(afterExercise: place.exercise)
    }

    fileprivate func firstWeight(afterExercise exercise: Int) -> NumberKeypadAddress? {
        var i = exercise + 1
        while i < exercises.count {
            if let first = exercises[i].first {
                return NumberKeypadAddress(setID: first, slot: .weight)
            }
            i += 1
        }
        return nil
    }
}
