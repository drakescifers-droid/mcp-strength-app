//
//  SetNumbering.swift
//  MCPStrength
//
//  Working-set numbering for a set list. Per docs/01-data-model.md § SetType,
//  only `.normal` sets are numbered (1, 2, 3 …); `.warmup`, `.dropSet`, and
//  `.failure` render a letter (W / D / F) and CONSUME NO NUMBER, so the
//  numbering of subsequent `.normal` sets continues past them. This file owns
//  that pure rule so it can be unit-tested without a view and shared by every
//  badge call site — the moment set types become editable, passing the raw
//  list position as the set number becomes visibly wrong.
//

import Foundation

enum SetNumbering {
    /// Returns an array parallel to `types`. For each `.normal` entry, the
    /// next working-set number (1-based, counting only `.normal` entries, in
    /// order). For `.warmup`, `.dropSet`, and `.failure`, `nil`.
    static func workingNumbers(for types: [SetType]) -> [Int?] {
        var next = 0
        return types.map { type in
            guard type == .normal else { return nil }
            next += 1
            return next
        }
    }

    /// Returns an array parallel to `types`. For each entry that is NOT a
    /// warm-up, its 0-based position among the non-warm-up entries; `nil` for
    /// a warm-up.
    ///
    /// This is what the Previous column lines up on, and it is a DIFFERENT
    /// rule from `workingNumbers` above even though both skip rows. Working
    /// numbering skips every lettered type, because a drop set is not "set 3".
    /// Previous skips only warm-ups, because a drop set IS a performance at
    /// that point in the sequence and last time's load for it is worth showing.
    ///
    /// Why warm-ups are excluded at all: `Add Warm-up Sets` inserts three rows
    /// at the TOP, and the Previous column used to match on raw list position.
    /// So generating a ramp moved "135 lb × 5" onto a 45 lb warm-up and left
    /// the working set showing "—" — the one number the user needs in order to
    /// pick today's load, displayed against a row the app chose for them and
    /// missing from the row they choose. A generated warm-up has no history to
    /// report; the set it leads up to does.
    static func positionsIgnoringWarmups(for types: [SetType]) -> [Int?] {
        var next = 0
        return types.map { type in
            guard type != .warmup else { return nil }
            defer { next += 1 }
            return next
        }
    }
}
