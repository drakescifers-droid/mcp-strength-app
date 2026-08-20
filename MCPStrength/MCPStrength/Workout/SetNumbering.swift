//
//  SetNumbering.swift
//  MCPStrength
//
//  Working-set numbering for a set list. Per docs/01-data-model.md § SetType,
//  only `.normal` sets are numbered (1, 2, 3 …); `.warmup`, `.dropSet`,
//  `.restPause`, and `.failure` render a letter (W / D / R / F) and CONSUME NO NUMBER, so the
//  numbering of subsequent `.normal` sets continues past them. This file owns
//  that pure rule so it can be unit-tested without a view and shared by every
//  badge call site — the moment set types become editable, passing the raw
//  list position as the set number becomes visibly wrong.
//

import Foundation

enum SetNumbering {
    /// Returns an array parallel to `types`. For each `.normal` entry, the
    /// next working-set number (1-based, counting only `.normal` entries, in
    /// order). For `.warmup`, `.dropSet`, `.restPause`, and `.failure`, `nil`.
    static func workingNumbers(for types: [SetType]) -> [Int?] {
        var next = 0
        return types.map { type in
            guard type == .normal else { return nil }
            next += 1
            return next
        }
    }

    /// Returns an array parallel to `types`. For each entry, its 0-based
    /// position among the entries of the same KIND, where kind is warm-up vs
    /// everything else.
    ///
    /// This is what the Previous column lines up on, and it is a DIFFERENT
    /// rule from `workingNumbers` above even though both walk the same list.
    /// Working numbering skips every lettered type, because a drop set is not
    /// "set 3", and returns `nil` for the rows it skips. This one skips
    /// nothing: every row has a previous counterpart, warm-ups just count in
    /// their own sequence. Do not collapse them —
    /// `numberingAndPreviousPositionsDisagreeOnDropSets` fails if you do.
    ///
    /// Why kind matters at all: `Add Warm-up Sets` inserts three rows at the
    /// TOP, and Previous used to match on raw list position. So generating a
    /// ramp shifted every row down a slot — the previous WORKING load was drawn
    /// against a 45 lb warm-up, and the working set, now row 4 where last time
    /// had no row 4, read "—". Counting each kind separately makes the column
    /// immune to a ramp appearing or disappearing above it, on either side.
    ///
    /// A drop set and a failure set count as working, not as warm-ups: they are
    /// real performances at that point in the sequence, and `PreviousText`
    /// already annotates them with (D) / (R) / (F) when last time's set at that
    /// position was one.
    static func positionsWithinKind(for types: [SetType]) -> [Int] {
        var nextWarmup = 0
        var nextWorking = 0
        return types.map { type in
            if type == .warmup {
                defer { nextWarmup += 1 }
                return nextWarmup
            }
            defer { nextWorking += 1 }
            return nextWorking
        }
    }
}
