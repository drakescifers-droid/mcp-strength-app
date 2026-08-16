//
//  Program.swift
//  MCPStrength
//

import Foundation
import SwiftData

@Model
final class ProgramDay {
    var id: UUID

    // MARK: Sync metadata
    //
    // Three columns, mirroring the server. The DEFAULTS are the load-bearing
    // part and the reasoning is in Sync/Syncable.swift — in short: declaration
    // -level defaults so SwiftData can lightweight-migrate an existing store,
    // and `needsSync = true` so a migrated or newly created row is PUSHED
    // rather than silently assumed clean.

    /// Wall-clock time of the last local edit. The last-write-wins key.
    var updatedAt: Date = Date.distantPast
    /// Tombstone. Non-nil means deleted; the row stays so the delete can reach
    /// devices that were offline when it happened.
    var deletedAt: Date?
    /// Has local changes the server has not confirmed.
    var needsSync: Bool = true
    var order: Int
    var label: String?

    var folder: TemplateFolder?
    var template: Template?

    init(
        id: UUID = UUID(),
        order: Int,
        label: String? = nil,
        folder: TemplateFolder? = nil,
        template: Template? = nil
    ) {
        self.id = id
        self.order = order
        self.label = label
        self.folder = folder
        self.template = template
    }
}
