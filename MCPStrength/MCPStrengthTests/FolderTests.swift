//
//  FolderTests.swift
//  MCPStrengthTests
//
//  Covers FolderEditing.nextOrder, NameEditing.normalized, and the
//  TemplateFolder delete-nullify contract — deleting a folder must leave
//  its templates alive and unfiled. Name validation lives in NameEditing
//  so folders and templates share one definition of a valid name.
//

import Testing
import SwiftData
import Foundation
@testable import MCPStrength

struct FolderTests {

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

    @Test func nextOrderEmpty() {
        #expect(FolderEditing.nextOrder(after: []) == 0)
    }

    @Test func nextOrderContiguous() {
        #expect(FolderEditing.nextOrder(after: [0, 1, 2]) == 3)
    }

    @Test func nextOrderNonContiguous() {
        #expect(FolderEditing.nextOrder(after: [0, 5]) == 6)
    }

    @Test func normalizedNameTrimsWhitespace() {
        #expect(NameEditing.normalized("  Q2 2026\n") == "Q2 2026")
    }

    @Test func normalizedNameRejectsBlank() {
        #expect(NameEditing.normalized("") == nil)
        #expect(NameEditing.normalized("   \n  ") == nil)
    }

    // The load-bearing contract: TemplateFolder.templates uses deleteRule
    // .nullify, so deleting the folder must leave the template alive with
    // folder == nil. A cascade here would silently destroy the user's plans.
    @Test func deletingFolderLeavesTemplatesUnfiled() throws {
        let context = try makeContainer()

        let folder = TemplateFolder(name: "Q2 2026", order: 0, kind: .folder)
        context.insert(folder)

        let template = Template(name: "Push Day", order: 0, folder: folder)
        context.insert(template)
        try context.save()

        // Assert the template is actually IN the folder before deleting it.
        // Without this the test passes vacuously: if the relationship never
        // formed, `folder == nil` after the delete is trivially true and the
        // real regression (Add Template filing nothing) goes unnoticed.
        #expect(template.folder?.id == folder.id)
        #expect(folder.templates.count == 1)

        let templateID = template.id
        context.delete(folder)
        try context.save()

        let fetchedTemplates = try context.fetch(FetchDescriptor<Template>())
        let surviving = try #require(
            fetchedTemplates.first { $0.id == templateID },
            "deleting a folder must not delete the templates inside it"
        )
        #expect(surviving.folder == nil)

        let fetchedFolders = try context.fetch(FetchDescriptor<TemplateFolder>())
        #expect(fetchedFolders.isEmpty)
    }

    @Test func collapseRoundTripPersists() throws {
        let context = try makeContainer()
        let folder = TemplateFolder(name: "Q2 2026", order: 0)
        context.insert(folder)
        try context.save()
        #expect(folder.isCollapsed == false)

        folder.isCollapsed = true
        try context.save()

        let collapsed = try #require(
            try context.fetch(FetchDescriptor<TemplateFolder>()).first { $0.id == folder.id }
        )
        #expect(collapsed.isCollapsed == true)

        collapsed.isCollapsed = false
        try context.save()

        let expanded = try #require(
            try context.fetch(FetchDescriptor<TemplateFolder>()).first { $0.id == folder.id }
        )
        #expect(expanded.isCollapsed == false)
    }
}
