//
//  FolderEditing.swift
//  MCPStrength
//
//  Ordering rules for TemplateFolder writes. A folder created from
//  the Templates section header must land after every existing folder (order is
//  what StartWorkoutTab sorts on). Name validation lives in NameEditing so
//  folders and templates share one definition of a valid name.
//

import Foundation

enum FolderEditing {
    /// Next `TemplateFolder.order`: one past the current max, or `0` when the
    /// list is empty. Gaps are left alone — order is an append position, not a
    /// dense rank, so `[0, 5]` yields `6` rather than filling `1`.
    static func nextOrder(after existing: [Int]) -> Int {
        guard let max = existing.max() else { return 0 }
        return max + 1
    }
}
