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
}
