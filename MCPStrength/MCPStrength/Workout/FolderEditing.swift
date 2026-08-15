//
//  FolderEditing.swift
//  MCPStrength
//
//  Naming and ordering rules for TemplateFolder writes. A folder created from
//  the Templates section header must land after every existing folder (order is
//  what StartWorkoutTab sorts on), and a blank or whitespace-only name must
//  never become a row — the view treats a nil normalized name as "do nothing."
//  This file owns those two rules so they can be unit-tested without a view
//  and shared by the create and rename paths, which would otherwise drift.
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

    /// Trim leading/trailing whitespace and newlines. `nil` when nothing
    /// remains — the only signal the view should refuse to write a folder.
    static func normalizedName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
