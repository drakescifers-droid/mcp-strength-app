//
//  NameEditing.swift
//  MCPStrength
//
//  One definition of a usable name. Folders and templates both refuse a
//  blank or whitespace-only string; keeping the trim-or-nil rule here
//  means the two write paths cannot drift on validity. The view treats a
//  nil normalized name as "do nothing."
//

import Foundation

enum NameEditing {
    /// Trim leading/trailing whitespace and newlines. `nil` when nothing
    /// remains — the only signal the view should refuse to write a name.
    static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
