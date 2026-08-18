//
//  TemplateEditingTests.swift
//  MCPStrengthTests
//
//  Covers TemplateEditing.duplicateName, the deep-copy contract used by
//  the card menu, and the Template delete rules — cascade on exercises/sets,
//  nullify on workouts. The workout-link test asserts the relationship is
//  actually set before the delete; a nil-only assertion after would pass
//  even if the link never formed.
//

import Testing
import SwiftData
import Foundation
@testable import MCPStrength

struct TemplateEditingTests {

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

    private func makeExercise(in context: ModelContext, name: String = "Bench Press") -> Exercise {
        let exercise = Exercise(
            name: name,
            bodyPart: .chest,
            category: .barbell,
            focusMetric: .totalVolume
        )
        context.insert(exercise)
        return exercise
    }

    /// Same field list as StartWorkoutTab.duplicateTemplate — the card menu
    /// and this test must not drift on what a deep copy carries.
    @discardableResult
    private func duplicateTemplate(_ template: Template, among templates: [Template], in context: ModelContext) -> Template {
        let copy = Template(
            name: TemplateEditing.duplicateName(
                of: template.name,
                existing: templates.map(\.name)
            ),
            note: template.note,
            order: FolderEditing.nextOrder(after: templates.map(\.order)),
            lastPerformedAt: nil,
            folder: template.folder
        )
        context.insert(copy)

        for sourceExercise in template.exercises.sorted(by: { $0.order < $1.order }) {
            let copiedExercise = TemplateExercise(
                order: sourceExercise.order,
                supersetGroupID: sourceExercise.supersetGroupID,
                note: sourceExercise.note,
                stickyNote: sourceExercise.stickyNote,
                defaultRestSeconds: sourceExercise.defaultRestSeconds,
                template: copy,
                exercise: sourceExercise.exercise
            )
            context.insert(copiedExercise)

            for sourceSet in sourceExercise.sets.sorted(by: { $0.order < $1.order }) {
                context.insert(TemplateSet(
                    order: sourceSet.order,
                    setType: sourceSet.setType,
                    weight: sourceSet.weight,
                    reps: sourceSet.reps,
                    repRangeStart: sourceSet.repRangeStart,
                    repRangeEnd: sourceSet.repRangeEnd,
                    rpe: sourceSet.rpe,
                    restSeconds: sourceSet.restSeconds,
                    templateExercise: copiedExercise
                ))
            }
        }
        return copy
    }

    @Test func duplicateNameNoCollision() {
        #expect(TemplateEditing.duplicateName(of: "Push Day", existing: []) == "Push Day (copy)")
        #expect(TemplateEditing.duplicateName(of: "Push Day", existing: ["Push Day"]) == "Push Day (copy)")
    }

    @Test func duplicateNameCollisionsAreCaseInsensitive() {
        #expect(
            TemplateEditing.duplicateName(
                of: "Push Day",
                existing: ["Push Day", "Push Day (copy)"]
            ) == "Push Day (copy 2)"
        )
        #expect(
            TemplateEditing.duplicateName(
                of: "Push Day",
                existing: ["Push Day", "push day (copy)"]
            ) == "Push Day (copy 2)"
        )
        #expect(
            TemplateEditing.duplicateName(
                of: "Push Day",
                existing: ["Push Day", "Push Day (copy)", "Push Day (copy 2)"]
            ) == "Push Day (copy 3)"
        )
    }

    @Test func deepCopyYieldsDistinctIdsAndLeavesOriginalUntouched() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)
        let folder = TemplateFolder(name: "Q2 2026", order: 0)
        context.insert(folder)

        let original = Template(
            name: "Push Day",
            note: "Keep elbows in",
            order: 0,
            lastPerformedAt: Date(),
            folder: folder
        )
        context.insert(original)
        let tx = TemplateExercise(order: 0, defaultRestSeconds: 180, template: original, exercise: exercise)
        context.insert(tx)
        let set0 = TemplateSet(
            order: 0, setType: .warmup, weight: 135, reps: 8, rpe: 7, restSeconds: 90, templateExercise: tx
        )
        let set1 = TemplateSet(
            order: 1, setType: .normal, weight: 185, reps: nil,
            repRangeStart: 6, repRangeEnd: 8, rpe: 8, restSeconds: 180, templateExercise: tx
        )
        context.insert(set0)
        context.insert(set1)
        try context.save()

        let originalID = original.id
        let originalExerciseID = tx.id
        let originalSetIDs = Set(original.exercises.flatMap(\.sets).map(\.id))
        let originalName = original.name
        let originalSetCount = original.exercises.flatMap(\.sets).count

        let copy = duplicateTemplate(original, among: [original], in: context)
        try context.save()

        #expect(copy.id != originalID)
        #expect(copy.name == "Push Day (copy)")
        #expect(copy.folder?.id == folder.id)
        #expect(copy.lastPerformedAt == nil)
        #expect(copy.exercises.count == 1)

        let copiedExercise = try #require(copy.exercises.first)
        #expect(copiedExercise.id != originalExerciseID)
        #expect(copiedExercise.exercise?.id == exercise.id)
        #expect(copiedExercise.sets.count == 2)

        let copiedSetIDs = Set(copiedExercise.sets.map(\.id))
        #expect(copiedSetIDs.isDisjoint(with: originalSetIDs))

        let fetchedOriginal = try #require(
            try context.fetch(FetchDescriptor<Template>()).first { $0.id == originalID }
        )
        #expect(fetchedOriginal.name == originalName)
        #expect(fetchedOriginal.exercises.count == 1)
        #expect(fetchedOriginal.exercises.flatMap(\.sets).count == originalSetCount)
        #expect(fetchedOriginal.lastPerformedAt != nil)
    }

    // Assert the workout's template link is SET first. A nil-only check
    // after the delete passes even if the relationship never formed — that
    // exact gap hid a real dangling-reference bug.
    @Test func deletingTemplateNullifiesWorkoutLinkAndKeepsHistory() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)

        let template = Template(name: "Push Day", order: 0)
        context.insert(template)
        let tx = TemplateExercise(order: 0, template: template, exercise: exercise)
        context.insert(tx)
        context.insert(TemplateSet(order: 0, weight: 185, reps: 5, restSeconds: 90, templateExercise: tx))
        try context.save()

        let workout = Workout(name: template.name, template: template)
        context.insert(workout)
        try context.save()

        #expect(workout.template?.id == template.id)
        #expect(template.workouts.contains(where: { $0.id == workout.id }))

        let workoutID = workout.id
        context.delete(template)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Workout>())
        let surviving = try #require(
            fetched.first { $0.id == workoutID },
            "deleting a template must not delete workouts already performed from it"
        )
        #expect(surviving.template == nil)
        #expect(surviving.name == "Push Day")
    }

    @Test func deletingTemplateCascadesExercisesAndSets() throws {
        let context = try makeContainer()
        let exercise = makeExercise(in: context)

        let template = Template(name: "Push Day", order: 0)
        context.insert(template)
        let tx = TemplateExercise(order: 0, template: template, exercise: exercise)
        context.insert(tx)
        let set0 = TemplateSet(order: 0, weight: 135, reps: 8, restSeconds: 90, templateExercise: tx)
        let set1 = TemplateSet(order: 1, weight: 185, reps: 5, restSeconds: 180, templateExercise: tx)
        context.insert(set0)
        context.insert(set1)
        try context.save()

        let templateID = template.id
        let exerciseID = tx.id
        let setIDs = Set([set0.id, set1.id])

        context.delete(template)
        try context.save()

        let remainingTemplates = try context.fetch(FetchDescriptor<Template>())
        #expect(remainingTemplates.contains(where: { $0.id == templateID }) == false)

        let remainingExercises = try context.fetch(FetchDescriptor<TemplateExercise>())
        #expect(remainingExercises.contains(where: { $0.id == exerciseID }) == false)

        let remainingSets = try context.fetch(FetchDescriptor<TemplateSet>())
        #expect(remainingSets.contains(where: { setIDs.contains($0.id) }) == false)
    }
}
