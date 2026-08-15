//
//  TemplatesScreen.swift
//  MCPStrength
//
//  The flat list of saved templates. A row shows the template name and a short
//  summary line (exercise count, plus the first few exercise names in
//  textSecondary). Tapping a row opens the editor; the + creates a new template
//  and opens the editor on it. Swipe actions offer Start (copies the template
//  into a new workout and opens the active-workout screen) and Delete.
//
//  Out of scope here: folder organisation, programs, reordering. The list is
//  flat — see the task boundary.
//

import SwiftUI
import SwiftData

struct TemplatesScreen: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Template.order) private var templates: [Template]

    /// Called when the user starts a workout from a template. ContentView owns
    /// the active-workout swap, so it handles the copy (via TemplateStarter)
    /// and the root transition.
    var onStart: (Template) -> Void = { _ in }

    @State private var editingTemplate: Template?
    @State private var showingEditor = false

    var body: some View {
        List {
            if templates.isEmpty {
                Text("No templates yet. Tap + to create one.")
                    .font(Typography.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(templates, id: \.id) { template in
                Button {
                    editingTemplate = template
                    showingEditor = true
                } label: {
                    TemplateRow(template: template)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Theme.fieldFill)
                .swipeActions(allowsFullSwipe: false) {
                    Button {
                        onStart(template)
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .tint(Theme.accent)

                    Button(role: .destructive) {
                        delete(template)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingTemplate = nil
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditor, onDismiss: { editingTemplate = nil }) {
            TemplateEditorScreen(template: editingTemplate)
        }
    }

    // MARK: - Actions

    private func delete(_ template: Template) {
        context.delete(template)
    }
}

// MARK: - TemplateRow

/// One row of the templates list: the template name in primary, then a summary
/// line — the exercise count and the first few exercise names in secondary.
private struct TemplateRow: View {
    let template: Template

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(template.name)
                .font(Typography.body.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(summary)
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .padding(.vertical, Spacing.compact)
    }

    /// "3 exercises · Back Squat, Bench Press, Deadlift" — falls back to a plain
    /// count when there are no named exercises yet.
    private var summary: String {
        let sorted = template.exercises.sorted(by: { $0.order < $1.order })
        let names = sorted.compactMap { $0.exercise?.name }
        let countWord = sorted.count == 1 ? "exercise" : "exercises"
        if names.isEmpty {
            return "\(sorted.count) \(countWord)"
        }
        let preview = names.prefix(3).joined(separator: ", ")
        let extra = names.count > 3 ? "…" : ""
        return "\(sorted.count) \(countWord) · \(preview)\(extra)"
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Exercise.self, Template.self, TemplateExercise.self, TemplateSet.self,
        Workout.self, WorkoutExercise.self, WorkoutSet.self,
        configurations: config
    )
    let context = container.mainContext

    let squat = Exercise(name: "Back Squat", bodyPart: .legs, category: .barbell, focusMetric: .totalVolume)
    let bench = Exercise(name: "Bench Press", bodyPart: .chest, category: .barbell, focusMetric: .totalVolume)
    context.insert(squat)
    context.insert(bench)

    let legDay = Template(name: "Leg Day", order: 0)
    context.insert(legDay)
    let tx = TemplateExercise(order: 0, template: legDay, exercise: squat)
    context.insert(tx)
    context.insert(TemplateSet(order: 0, weight: 225, reps: 5, restSeconds: 180, templateExercise: tx))

    let pushDay = Template(name: "Push Day", order: 1)
    context.insert(pushDay)
    let tx2 = TemplateExercise(order: 0, template: pushDay, exercise: bench)
    context.insert(tx2)

    return NavigationStack {
        TemplatesScreen()
    }
    .modelContainer(container)
}
