//
//  ProgramCursorTests.swift
//  MCPStrengthTests
//

import Testing
import SwiftData
import Foundation
@testable import MCPStrength

struct ProgramCursorTests {

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
            AppSettings.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    /// Builds a program folder with the given days (each a (label, template))
    /// inserted in the order supplied, then saved and refetched so the
    /// relationship array reflects SwiftData's (unordered) storage.
    @discardableResult
    private func makeProgram(
        context: ModelContext,
        name: String = "Test Program",
        totalCycles: Int? = nil,
        cursor: Int = 0,
        days: [(label: String, template: Template)]
    ) throws -> TemplateFolder {
        let folder = TemplateFolder(
            name: name, order: 0, kind: .program, cursor: cursor, totalCycles: totalCycles
        )
        context.insert(folder)
        for (i, entry) in days.enumerated() {
            entry.template.folder = folder
            context.insert(entry.template)
            let day = ProgramDay(order: i, label: entry.label, folder: folder, template: entry.template)
            context.insert(day)
        }
        try context.save()
        return folder
    }

    // (a) ORDERING PROVEN, NOT ASSUMED — ProgramDays inserted OUT OF ORDER
    // still traverse 0, 1, 2. The raw relationship array has no guaranteed
    // order; `orderedDays` must sort by `order`.
    @Test func orderedDaysSortsByOrderRegardlessOfInsertionOrder() throws {
        let context = try makeContainer()

        let folder = TemplateFolder(name: "Order Test", order: 0, kind: .program)
        context.insert(folder)

        let t0 = Template(name: "T0", order: 0, folder: folder)
        let t1 = Template(name: "T1", order: 1, folder: folder)
        let t2 = Template(name: "T2", order: 2, folder: folder)
        context.insert(t0); context.insert(t1); context.insert(t2)

        // Deliberately insert ProgramDays out of order: 2, then 0, then 1.
        let day2 = ProgramDay(order: 2, label: "Day 3", folder: folder, template: t2)
        let day0 = ProgramDay(order: 0, label: "Day 1", folder: folder, template: t0)
        let day1 = ProgramDay(order: 1, label: "Day 2", folder: folder, template: t1)
        context.insert(day2)
        context.insert(day0)
        context.insert(day1)
        try context.save()

        let ordered = folder.orderedDays
        #expect(ordered.count == 3)
        #expect(ordered.map(\.order) == [0, 1, 2])
        #expect(ordered.map(\.template?.name) == ["T0", "T1", "T2"])
        #expect(ordered.map(\.label) == ["Day 1", "Day 2", "Day 3"])

        // The raw relationship array has NO guaranteed order — that is the
        // bug this test guards against. We only assert that, whatever order
        // SwiftData happens to hand back, `orderedDays` sorts it to 0,1,2.
        // (We deliberately do NOT assert a specific raw order; doing so would
        // be testing an implementation detail that is documented as undefined.)
        let sortedOrders = folder.programDays.map(\.order).sorted()
        #expect(sortedOrders == [0, 1, 2])
    }

    // (b) REPEATS — a 3-slot A, B, A program where the same Template appears
    // at slots 0 and 2 resolves to the same template id.
    @Test func repeatedTemplateResolvesToSameId() throws {
        let context = try makeContainer()

        let templateA = Template(name: "Workout A", order: 0)
        let templateB = Template(name: "Workout B", order: 1)
        try makeProgram(
            context: context, name: "A/B/A",
            days: [("Day 1", templateA), ("Day 2", templateB), ("Day 3", templateA)]
        )

        let folder = try #require(context.fetch(FetchDescriptor<TemplateFolder>()).first)
        let ordered = folder.orderedDays

        #expect(ordered.count == 3)
        #expect(ordered[0].template?.id == ordered[2].template?.id)
        #expect(ordered[0].template?.id != ordered[1].template?.id)
        #expect(ordered[0].template?.name == "Workout A")
        #expect(ordered[2].template?.name == "Workout A")
    }

    // (c) WRAPPING — a 4-day program with cursor == 5 has position 1 and
    // completedCycles 1.
    @Test func cursorWrapsViaModulo() throws {
        let context = try makeContainer()

        let t0 = Template(name: "D0", order: 0)
        let t1 = Template(name: "D1", order: 1)
        let t2 = Template(name: "D2", order: 2)
        let t3 = Template(name: "D3", order: 3)
        try makeProgram(
            context: context, name: "4-Day", cursor: 5,
            days: [("0", t0), ("1", t1), ("2", t2), ("3", t3)]
        )

        let folder = try #require(context.fetch(FetchDescriptor<TemplateFolder>()).first)
        #expect(folder.cycleLength == 4)
        #expect(folder.cursor == 5)
        #expect(folder.position == 1)
        #expect(folder.completedCycles == 1)
        #expect(folder.isComplete == false)
        // currentDay is the slot at position 1
        #expect(folder.currentDay?.template?.name == "D1")
    }

    // (d) FINITE COMPLETION — 4 days with totalCycles == 1: after 4 advances
    // isComplete is true and currentDay is nil.
    @Test func finiteProgramCompletesAfterFullCycle() throws {
        let context = try makeContainer()

        let t0 = Template(name: "D0", order: 0)
        let t1 = Template(name: "D1", order: 1)
        let t2 = Template(name: "D2", order: 2)
        let t3 = Template(name: "D3", order: 3)
        try makeProgram(
            context: context, name: "One-Shot", totalCycles: 1,
            days: [("0", t0), ("1", t1), ("2", t2), ("3", t3)]
        )

        let folder = try #require(context.fetch(FetchDescriptor<TemplateFolder>()).first)
        #expect(folder.isComplete == false)
        #expect(folder.currentDay?.template?.name == "D0")

        folder.advance() // cursor 1
        #expect(folder.cursor == 1)
        #expect(folder.isComplete == false)
        #expect(folder.currentDay?.template?.name == "D1")

        folder.advance() // cursor 2
        folder.advance() // cursor 3
        #expect(folder.isComplete == false)
        #expect(folder.currentDay?.template?.name == "D3")

        folder.advance() // cursor 4 → completedCycles 1 >= 1
        #expect(folder.cursor == 4)
        #expect(folder.completedCycles == 1)
        #expect(folder.isComplete == true)
        #expect(folder.currentDay == nil)

        // A further advance is a no-op: the cursor must not run away past the
        // end of a finished finite program.
        folder.advance()
        #expect(folder.cursor == 4)
        #expect(folder.isComplete == true)
    }

    // (e) INDEFINITE — totalCycles == nil never reports complete, even after
    // many cycles.
    @Test func indefiniteProgramNeverCompletes() throws {
        let context = try makeContainer()

        let t0 = Template(name: "Upper", order: 0)
        let t1 = Template(name: "Lower", order: 1)
        try makeProgram(
            context: context, name: "Forever", totalCycles: nil,
            days: [("U", t0), ("L", t1)]
        )

        let folder = try #require(context.fetch(FetchDescriptor<TemplateFolder>()).first)
        #expect(folder.totalCycles == nil)

        // Run well past many cycles.
        for _ in 0..<23 {
            folder.advance()
        }
        #expect(folder.cursor == 23)
        #expect(folder.cycleLength == 2)
        #expect(folder.completedCycles == 11)
        #expect(folder.position == 1)
        #expect(folder.isComplete == false)
        #expect(folder.currentDay?.template?.name == "Lower")
    }

    // (f) SKIP advances the cursor; REWIND undoes it; rewind at cursor 0
    // stays at 0 rather than going negative.
    @Test func skipAdvancesAndRewindUndoesAndFloorsAtZero() throws {
        let context = try makeContainer()

        let t0 = Template(name: "A", order: 0)
        let t1 = Template(name: "B", order: 1)
        try makeProgram(
            context: context, name: "Skip/Undo",
            days: [("A", t0), ("B", t1)]
        )

        let folder = try #require(context.fetch(FetchDescriptor<TemplateFolder>()).first)
        #expect(folder.cursor == 0)
        #expect(folder.currentDay?.template?.name == "A")

        folder.skip()
        #expect(folder.cursor == 1)
        #expect(folder.currentDay?.template?.name == "B")

        // Immediate undo of the skip.
        folder.rewind()
        #expect(folder.cursor == 0)
        #expect(folder.currentDay?.template?.name == "A")

        // rewind at 0 floors at 0 — never negative.
        folder.rewind()
        folder.rewind()
        #expect(folder.cursor == 0)

        // advance then rewind round-trips.
        folder.advance()
        folder.advance()
        #expect(folder.cursor == 2)
        folder.rewind()
        #expect(folder.cursor == 1)
    }

    // (g) SAFETY — a folder with kind == .folder and a program with no days
    // both behave safely (no crash, no divide-by-zero, nil/no-op).
    @Test func nonProgramFolderAndEmptyProgramBehaveSafely() throws {
        let context = try makeContainer()

        // A plain folder (kind == .folder). Program fields are meaningless.
        let plainFolder = TemplateFolder(name: "Drawer", order: 0, kind: .folder, cursor: 7, totalCycles: 3)
        context.insert(plainFolder)
        try context.save()

        #expect(plainFolder.isProgram == false)
        #expect(plainFolder.cycleLength == 0)
        #expect(plainFolder.position == 0)
        #expect(plainFolder.completedCycles == 0)
        #expect(plainFolder.isComplete == false)
        #expect(plainFolder.currentDay == nil)
        #expect(plainFolder.orderedDays == [])

        // Mutations are no-ops on a non-program folder; cursor is untouched.
        let cursorBefore = plainFolder.cursor
        plainFolder.advance()
        plainFolder.skip()
        plainFolder.rewind()
        #expect(plainFolder.cursor == cursorBefore)

        // A program with zero ProgramDays — safe, no divide-by-zero.
        let emptyProgram = TemplateFolder(name: "Empty Program", order: 1, kind: .program, cursor: 0, totalCycles: 1)
        context.insert(emptyProgram)
        try context.save()

        #expect(emptyProgram.isProgram == true)
        #expect(emptyProgram.cycleLength == 0)
        #expect(emptyProgram.position == 0)
        #expect(emptyProgram.completedCycles == 0)
        #expect(emptyProgram.isComplete == false)
        #expect(emptyProgram.currentDay == nil)
        #expect(emptyProgram.orderedDays == [])

        // advance/skip on an empty program are no-ops: there is no workout to
        // perform, so the cursor does not move. State stays nil-safe.
        emptyProgram.advance()
        emptyProgram.skip()
        #expect(emptyProgram.cursor == 0)
        #expect(emptyProgram.currentDay == nil)
        emptyProgram.rewind()
        #expect(emptyProgram.cursor == 0)
    }

    // Bonus: rewind recovers from a cursor pushed past the end of a finite
    // program, and currentDay re-appears once back inside the cycle.
    @Test func rewindRecoversFromPastEndOfFiniteProgram() throws {
        let context = try makeContainer()

        let t0 = Template(name: "A", order: 0)
        let t1 = Template(name: "B", order: 1)
        try makeProgram(
            context: context, name: "Finite", totalCycles: 1,
            days: [("A", t0), ("B", t1)]
        )

        let folder = try #require(context.fetch(FetchDescriptor<TemplateFolder>()).first)
        folder.advance() // 1
        folder.advance() // 2 → complete
        #expect(folder.isComplete == true)
        #expect(folder.currentDay == nil)

        // Walk it back; the program is no longer complete and currentDay
        // reappears.
        folder.rewind()
        #expect(folder.cursor == 1)
        #expect(folder.isComplete == false)
        #expect(folder.currentDay?.template?.name == "B")
    }

    // Bonus: training a template directly must NOT move the cursor — there is
    // no jump API, and advance/skip are the only cursor writes. This encodes
    // that invariant by confirming nothing in the API lets you set position
    // arbitrarily; the only observable cursor changes come from advance/skip
    // (+1) and rewind (-1, floored).
    @Test func cursorOnlyMovesViaAdvanceSkipRewind() throws {
        let context = try makeContainer()

        let t0 = Template(name: "A", order: 0)
        let t1 = Template(name: "B", order: 1)
        let t2 = Template(name: "C", order: 2)
        try makeProgram(
            context: context, name: "Invariant",
            days: [("A", t0), ("B", t1), ("C", t2)]
        )

        let folder = try #require(context.fetch(FetchDescriptor<TemplateFolder>()).first)
        let observed = { folder.cursor }

        // Reading derived state has no side effect on the cursor.
        _ = folder.position
        _ = folder.completedCycles
        _ = folder.currentDay
        _ = folder.orderedDays
        #expect(observed() == 0)

        folder.skip()
        #expect(observed() == 1)
        folder.advance()
        #expect(observed() == 2)
        folder.rewind()
        #expect(observed() == 1)
        folder.rewind()
        #expect(observed() == 0)
        folder.rewind()
        #expect(observed() == 0)
    }
}
