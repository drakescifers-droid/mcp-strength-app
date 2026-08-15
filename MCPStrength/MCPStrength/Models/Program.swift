//
//  Program.swift
//  MCPStrength
//

import Foundation
import SwiftData

@Model
final class ProgramDay {
    var id: UUID
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
