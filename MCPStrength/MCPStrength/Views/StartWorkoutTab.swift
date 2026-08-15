//
//  StartWorkoutTab.swift
//  MCPStrength
//
//  The HOME tab. Absorbs the old TemplatesScreen: a Quick Start action for an
//  empty workout, plus the templates themselves rendered as a two-column grid
//  of cards (grouped under folder headers when folders exist). Tapping a card
//  opens the existing TemplateEditorScreen; an explicit Start affordance on
//  each card starts a workout from that template without losing the reachability
//  the old swipe-to-Start row provided.
//
//  Folder CREATION and management is out of scope here — this view only
//  DISPLAYS grouping. When no TemplateFolder rows exist the grid is flat with
//  no header, rather than an "Ungrouped" heading that says nothing.
//

import SwiftUI
import SwiftData

struct StartWorkoutTab: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \TemplateFolder.order) private var folders: [TemplateFolder]
    @Query(sort: \Template.order) private var templates: [Template]

    /// Start a quick (no-template) workout. ContentView owns the active-workout
    /// swap, so it handles the insert and the root transition.
    var onStartQuick: () -> Void = {}

    /// Start a workout from a template. ContentView owns the copy (via
    /// TemplateStarter) and the root transition.
    var onStartTemplate: (Template) -> Void = { _ in }

    @State private var editingTemplate: Template?
    @State private var showingEditor = false

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.comfortable),
        GridItem(.flexible(), spacing: Spacing.comfortable),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.spacious) {
                    quickStartSection
                    templatesSection
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.spacious)
            }
            .background(Theme.surface)
            .navigationTitle("Start Workout")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingEditor, onDismiss: { editingTemplate = nil }) {
                TemplateEditorScreen(template: editingTemplate)
            }
        }
    }

    // MARK: - Quick Start

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: Spacing.comfortable) {
            Text("Quick Start")
                .font(Typography.secondary.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            Button {
                onStartQuick()
            } label: {
                Text("Start an Empty Workout")
            }
            .buttonStyle(PrimaryActionButtonStyle(fill: Theme.accent))
        }
    }

    // MARK: - Templates

    @ViewBuilder
    private var templatesSection: some View {
        // The "Templates" section header always carries the "+ Template" action
        // so the create path is reachable whether or not any templates exist yet.
        sectionHeader(title: "Templates") {
            editingTemplate = nil
            showingEditor = true
        }

        if templates.isEmpty {
            Text("No templates yet. Tap + Template to create one.")
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
        } else if folders.isEmpty {
            // Flat grid, no header — an "Ungrouped" heading would say nothing.
            templateGrid(templates)
        } else {
            ForEach(folders, id: \.id) { folder in
                let folderTemplates = folder.templates.sorted { $0.order < $1.order }
                if !folderTemplates.isEmpty {
                    folderHeader(name: folder.name, count: folderTemplates.count)
                    templateGrid(folderTemplates)
                }
            }
            // Templates with no folder (when folders exist) get a trailing
            // headerless grid rather than being hidden or mislabelled.
            let unfiled = templates.filter { $0.folder == nil }
            if !unfiled.isEmpty {
                templateGrid(unfiled)
            }
        }
    }

    private func sectionHeader(title: String, onNewTemplate: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(Typography.secondary.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button {
                onNewTemplate()
            } label: {
                Label("Template", systemImage: "plus")
                    .font(Typography.secondary.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func folderHeader(name: String, count: Int) -> some View {
        Text("\(name) (\(count))")
            .font(Typography.secondary.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.comfortable)
    }

    private func templateGrid(_ templates: [Template]) -> some View {
        LazyVGrid(columns: columns, spacing: Spacing.comfortable) {
            ForEach(templates, id: \.id) { template in
                TemplateCard(
                    template: template,
                    onTap: {
                        editingTemplate = template
                        showingEditor = true
                    },
                    onStart: { onStartTemplate(template) }
                )
            }
        }
    }
}

// MARK: - TemplateCard

/// One card in the two-column templates grid: the template name, the exercise
/// names joined and truncated to a few lines in `textSecondary`, and — when
/// `lastPerformedAt` is set — a clock icon with a relative last-performed
/// string ("Yesterday", "4 days ago"). Tapping the card opens the editor; the
/// trailing play button starts a workout from it.
private struct TemplateCard: View {
    let template: Template
    var onTap: () -> Void
    var onStart: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.compact) {
                HStack(alignment: .top, spacing: Spacing.compact) {
                    Text(template.name)
                        .font(Typography.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)

                    startButton
                }

                Text(exerciseSummary)
                    .font(Typography.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                if let lastPerformedAt = template.lastPerformedAt {
                    HStack(spacing: Spacing.compact / 2) {
                        Image(systemName: "clock")
                            .font(Typography.secondary)
                        Text(relativeLastPerformed(from: lastPerformedAt))
                            .font(Typography.secondary)
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.comfortable)
            .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
    }

    private var startButton: some View {
        Button(action: onStart) {
            Image(systemName: "play.fill")
                .font(Typography.body.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Theme.accentFill, in: .circle)
        }
        .buttonStyle(.plain)
    }

    /// The exercise names joined by commas. Falls back to a plain count when
    /// there are no named exercises yet.
    private var exerciseSummary: String {
        let sorted = template.exercises.sorted { $0.order < $1.order }
        let names = sorted.compactMap { $0.exercise?.name }
        let countWord = sorted.count == 1 ? "exercise" : "exercises"
        if names.isEmpty {
            return "\(sorted.count) \(countWord)"
        }
        return names.joined(separator: ", ")
    }

    /// "Yesterday", "4 days ago", etc. Coarse on purpose — the card shows a
    /// hint, not a precise timestamp.
    private func relativeLastPerformed(from date: Date) -> String {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfDay = calendar.startOfDay(for: date)
        let dayDiff = calendar.dateComponents([.day], from: startOfDay, to: startOfToday).day ?? 0

        switch dayDiff {
        case 0:      return "Today"
        case 1:      return "Yesterday"
        case 2...6:  return "\(dayDiff) days ago"
        case 7...13: return "Last week"
        case 14...29: return "\(dayDiff / 7) weeks ago"
        case 30...364: return "\(dayDiff / 30) months ago"
        default:     return "\(dayDiff / 365) years ago"
        }
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

    let legDay = Template(name: "Leg Day", order: 0, lastPerformedAt: Date(timeIntervalSinceNow: -86400))
    context.insert(legDay)
    let tx = TemplateExercise(order: 0, template: legDay, exercise: squat)
    context.insert(tx)
    context.insert(TemplateSet(order: 0, weight: 225, reps: 5, restSeconds: 180, templateExercise: tx))

    let pushDay = Template(name: "Push Day", order: 1)
    context.insert(pushDay)
    let tx2 = TemplateExercise(order: 0, template: pushDay, exercise: bench)
    context.insert(tx2)

    return StartWorkoutTab()
        .modelContainer(container)
}
