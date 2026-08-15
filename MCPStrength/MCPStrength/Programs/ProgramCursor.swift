//
//  ProgramCursor.swift
//  MCPStrength
//
//  Program cursor logic. A program is a rotation, not a schedule: the list of
//  ProgramDays IS the cycle, and the cycle repeats. `cursor` is a single
//  monotonic counter that NEVER wraps; everything else (position, completed
//  cycles, completion) is derived from it. See docs/01-data-model.md § "A
//  rotation, not a schedule".
//
//  CRITICAL: `TemplateFolder.programDays` is a SwiftData relationship array
//  whose element order is NOT guaranteed to match `ProgramDay.order`. Every
//  access must sort by `order` before indexing — `orderedDays` is the only
//  safe entry point.
//

import Foundation

extension TemplateFolder {

    // MARK: - Derived state

    /// `true` when this folder has been promoted to a program. All program
    /// fields are meaningless for a plain folder, so every computed property
    /// and cursor mutation guards on this.
    var isProgram: Bool { kind == .program }

    /// The program days sorted by `order`. This is the ONLY safe way to read
    /// the day sequence — the raw `programDays` relationship array has no
    /// guaranteed ordering and will silently reorder somebody's training block.
    var orderedDays: [ProgramDay] {
        programDays.sorted { $0.order < $1.order }
    }

    /// Number of slots in one cycle. Zero for a non-program or a program with
    /// no days. Exposed for the presentation layer; week numbers are NOT
    /// computed here (a cycle is not always one week and the schema carries
    /// no days-per-week notion).
    var cycleLength: Int {
        guard isProgram else { return 0 }
        return programDays.count
    }

    /// Which slot in the list the cursor points at. Derived as
    /// `cursor % dayCount`. Zero when there are no days or this isn't a
    /// program — never divides by zero.
    var position: Int {
        guard isProgram, cycleLength > 0 else { return 0 }
        return cursor % cycleLength
    }

    /// How many full cycles have been started. Derived as
    /// `cursor / dayCount` (integer division). Zero when there are no days.
    var completedCycles: Int {
        guard isProgram, cycleLength > 0 else { return 0 }
        return cursor / cycleLength
    }

    /// `true` once a finite program has run its allotted cycles.
    /// `totalCycles == nil` means run indefinitely and never completes.
    var isComplete: Bool {
        guard isProgram, let total = totalCycles else { return false }
        return completedCycles >= total
    }

    /// The day the user should train next. `nil` when the program is complete,
    /// has no days, or this folder isn't a program.
    var currentDay: ProgramDay? {
        guard isProgram, !isComplete, cycleLength > 0 else { return nil }
        let days = orderedDays
        guard position < days.count else { return nil }
        return days[position]
    }

    // MARK: - Cursor mutations
    //
    // The cursor is the single source of truth. There is deliberately NO
    // jump-to-arbitrary-slot API: a user who wants a specific session today
    // opens that template and trains it directly, which must NOT move the
    // cursor. Only advance / skip / rewind touch it.

    /// The workout was performed. Moves the cursor forward one slot.
    /// No-op on a complete program, a non-program folder, or a program with
    /// no days (there is no workout to perform).
    func advance() {
        guard isProgram, !isComplete, cycleLength > 0 else { return }
        cursor += 1
    }

    /// The user skipped this one. The cursor effect is identical to
    /// `advance()` (cursor += 1), but the INTENT differs: callers log a
    /// workout in one case and not the other. No-op on a complete program, a
    /// non-program folder, or a program with no days.
    func skip() {
        guard isProgram, !isComplete, cycleLength > 0 else { return }
        cursor += 1
    }

    /// Undo the last advance/skip: cursor -= 1, floored at 0 and never
    /// negative. This is the immediate undo the docs call for on a mis-tapped
    /// skip in a finite program, where otherwise a mis-tap cannot be walked
    /// back without cycling the whole block. It is NOT a jump-to-slot API.
    func rewind() {
        guard isProgram else { return }
        cursor = max(0, cursor - 1)
    }
}
