//
//  SetNumberingTests.swift
//  MCPStrengthTests
//
//  Covers SetNumbering.workingNumbers — the rule that only `.normal` sets
//  consume a working-set number, while `.warmup` / `.dropSet` / `.restPause`
//  / `.failure` render a letter and are skipped. Lives in Workout/ (no SwiftUI)
//  so it can be tested in isolation; see docs/01-data-model.md § SetType.
//

import Testing
import Foundation
@testable import MCPStrength

struct SetNumberingTests {

    @Test func allNormal() {
        #expect(SetNumbering.workingNumbers(for: [.normal, .normal, .normal]) == [1, 2, 3])
    }

    @Test func warmupFirst() {
        #expect(SetNumbering.workingNumbers(for: [.warmup, .normal, .normal]) == [nil, 1, 2])
    }

    @Test func warmupInterleaved() {
        #expect(SetNumbering.workingNumbers(for: [.normal, .warmup, .normal]) == [1, nil, 2])
    }

    @Test func dropSetConsumesNoNumber() {
        // Reference case from the screenshot: [normal, normal, dropSet] -> 1, 2, D.
        #expect(SetNumbering.workingNumbers(for: [.normal, .normal, .dropSet]) == [1, 2, nil])
    }

    @Test func emptyArray() {
        #expect(SetNumbering.workingNumbers(for: []).isEmpty)
    }

    @Test func allLettered() {
        #expect(
            SetNumbering.workingNumbers(for: [.warmup, .dropSet, .restPause, .failure])
            == [nil, nil, nil, nil]
        )
    }

    @Test func restPauseConsumesNoNumber() {
        #expect(
            SetNumbering.workingNumbers(for: [.normal, .restPause, .normal])
            == [1, nil, 2]
        )
    }

    @Test func numberingContinuesPastLettered() {
        #expect(
            SetNumbering.workingNumbers(for: [.normal, .dropSet, .normal, .failure, .normal])
            == [1, nil, 2, nil, 3]
        )
    }

    @Test func theFiveLivePostgresCasesAreUnchanged() {
        // Postgres can ADD a value; it cannot drop one without recreating
        // the type. The Swift raw value IS the column value — a mapping
        // table is how Phase 0 silently rewrote an unknown set_type.
        #expect(SetType.allCases.map(\.rawValue) == [
            "normal", "warmup", "dropSet", "restPause", "failure",
        ])
    }
}
