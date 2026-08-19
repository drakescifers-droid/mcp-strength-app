//
//  TemplateOverviewSheet.swift
//  MCPStrength
//
//  Read-only preview of one template. Tapping a card opens this rather than
//  the editor: starting a workout is the common action and belongs on a
//  full-width button, not a play glyph. Edit is rare and lives here as a
//  nested sheet — handing presentation back to the parent across two sheets
//  is the same timing hazard that silently broke a feature in
//  StartWorkoutTab on 2026-08-15.
//

import SwiftUI
import SwiftData

struct TemplateOverviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let template: Template
    var onStart: (Template) -> Void

    /// Presentation payload for the nested editor. Fresh UUID so identity is
    /// the presentation, matching StartWorkoutTab.EditorTarget.
    private struct EditorTarget: Identifiable {
        let id = UUID()
        let template: Template
    }

    @State private var editorTarget: EditorTarget?

    var body: some View {
        VStack(spacing: 0) {
            header

            if let lastPerformedAt = template.lastPerformedAt {
                Text("Last Performed: \(RelativeDate.lastPerformed(from: lastPerformedAt))")
                    .font(Typography.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.top, Spacing.compact)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.comfortable) {
                    ForEach(orderedExercises, id: \.id) { item in
                        // `orderedExercises` already drops a nil `exercise` —
                        // printing "Unknown" would invent a name we do not have.
                        if let exercise = item.exercise {
                            exerciseRow(item, exercise: exercise)
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.comfortable)
            }

            Button {
                // Dismiss first so finishing the workout does not return to
                // a still-presented overview sitting under the active screen.
                dismiss()
                onStart(template)
            } label: {
                Text("Start Workout")
            }
            .buttonStyle(PrimaryActionButtonStyle(fill: Theme.accent))
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.spacious)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .sheet(item: $editorTarget) { target in
            TemplateEditorScreen(template: target.template)
        }
    }

    // ✕ / template name / Edit. Same header idiom as TemplateEditorScreen so
    // the two sheets feel like one family. Edit owns the nested editor sheet
    // here; do not bounce presentation back to StartWorkoutTab.
    private var header: some View {
        HStack(spacing: Spacing.comfortable) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(Typography.body)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.chip))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(template.name)
                .font(Typography.title)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer()

            Button("Edit") {
                editorTarget = EditorTarget(template: template)
            }
            .font(Typography.body.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.vertical, Spacing.compact)
    }

    private var orderedExercises: [TemplateExercise] {
        template.liveExercises
            .sorted { $0.order < $1.order }
            .filter { $0.exercise != nil }
    }

    private func exerciseRow(_ item: TemplateExercise, exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: Spacing.compact / 2) {
            Text("\(item.liveSets.count) × \(exercise.name)")
                .font(Typography.body.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(exercise.bodyPart.displayName)
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    let raise = Exercise(name: "Lateral Raise (Machine)", bodyPart: .shoulders, category: .machineOther)
    context.insert(raise)

    let template = Template(name: "F Shoulders", order: 0, lastPerformedAt: Date(timeIntervalSinceNow: -86400))
    context.insert(template)
    let tx = TemplateExercise(order: 0, template: template, exercise: raise)
    context.insert(tx)
    context.insert(TemplateSet(order: 0, weight: WeightUnits.kilograms(from: 20, in: .lbs), reps: 12, restSeconds: 90, templateExercise: tx))
    context.insert(TemplateSet(order: 1, weight: WeightUnits.kilograms(from: 20, in: .lbs), reps: 12, restSeconds: 90, templateExercise: tx))
    context.insert(TemplateSet(order: 2, weight: WeightUnits.kilograms(from: 20, in: .lbs), reps: 12, restSeconds: 90, templateExercise: tx))

    return TemplateOverviewSheet(template: template, onStart: { _ in })
        .modelContainer(container)
}
