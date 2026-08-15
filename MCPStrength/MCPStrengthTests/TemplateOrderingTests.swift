//
//  TemplateOrderingTests.swift
//  MCPStrengthTests
//
//  Covers TemplateOrdering.move — the rule that `index` is the final
//  position in the destination list AFTER `id` has been removed. Lives in
//  Workout/ (no SwiftUI / SwiftData) so it can be tested in isolation.
//

import Testing
import Foundation
@testable import MCPStrength

struct TemplateOrderingTests {

    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let d = UUID()
    private let x = UUID()
    private let y = UUID()

    // The off-by-one case: index is post-removal. Moving A to 2 in
    // [A, B, C, D] must land AFTER C ([B, C, A, D]), not before it.
    @Test func sameListMoveDown() {
        let list = [a, b, c, d]
        let result = TemplateOrdering.move(a, from: list, to: list, at: 2)
        #expect(result.source == [b, c, a, d])
        #expect(result.destination == [b, c, a, d])
    }

    @Test func sameListMoveUp() {
        let list = [a, b, c, d]
        let result = TemplateOrdering.move(d, from: list, to: list, at: 1)
        #expect(result.source == [a, d, b, c])
        #expect(result.destination == [a, d, b, c])
    }

    @Test func crossListInsertAtStart() {
        let result = TemplateOrdering.move(a, from: [a, b], to: [x, y], at: 0)
        #expect(result.source == [b])
        #expect(result.destination == [a, x, y])
    }

    @Test func crossListInsertAtEnd() {
        let result = TemplateOrdering.move(a, from: [a, b], to: [x, y], at: 2)
        #expect(result.source == [b])
        #expect(result.destination == [x, y, a])
    }

    // A drop past the last card is ordinary — clamp, do not crash or no-op.
    @Test func indexBeyondEndIsClamped() {
        let result = TemplateOrdering.move(a, from: [a, b], to: [x, y], at: 99)
        #expect(result.source == [b])
        #expect(result.destination == [x, y, a])
    }

    @Test func emptyDestination() {
        let result = TemplateOrdering.move(a, from: [a], to: [], at: 0)
        #expect(result.source == [])
        #expect(result.destination == [a])
    }

    @Test func idAbsentFromSourceLeavesBothUnchanged() {
        let source = [b, c]
        let destination = [x, y]
        let result = TemplateOrdering.move(a, from: source, to: destination, at: 0)
        #expect(result.source == source)
        #expect(result.destination == destination)
    }
}
