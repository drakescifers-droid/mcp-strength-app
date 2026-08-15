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
//  Folder lifecycle (create, rename, delete, collapse, and filing a new
//  template into a folder) lives here. Template cards carry a per-card menu
//  (edit, rename, duplicate, delete) — the only place a template can be
//  deleted. Empty folders still render — a new folder has no templates, and
//  hiding it would make create look like a no-op. When no TemplateFolder
//  rows exist the grid is flat with no header, rather than an "Ungrouped"
//  heading that says nothing.
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

    /// Presentation payload for TemplateEditorScreen. `id` is a fresh UUID
    /// because identity is the presentation, not the template — a new
    /// template has no id to key `.sheet(item:)` off of.
    private struct EditorTarget: Identifiable {
        let id = UUID()
        let template: Template?
        let folder: TemplateFolder?
    }

    /// Destination for the template editor. `folder` is set when opened
    /// from a folder menu; `nil` on the section-header "+ Template" path.
    @State private var editorTarget: EditorTarget?

    @State private var showingAddFolder = false
    @State private var newFolderName = ""

    @State private var renamingFolder: TemplateFolder?
    @State private var renameText = ""

    @State private var folderPendingDelete: TemplateFolder?

    @State private var renamingTemplate: Template?
    @State private var templateRenameText = ""

    @State private var templatePendingDelete: Template?

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
            // item: so the folder travels with the binding. A boolean
            // isPresented flip from a Menu action races dismissal, and
            // the sheet can build against stale companion state (folder nil).
            .sheet(item: $editorTarget) { target in
                TemplateEditorScreen(template: target.template, folder: target.folder)
            }
            .alert("Rename Folder", isPresented: Binding(
                get: { renamingFolder != nil },
                set: { if !$0 { renamingFolder = nil } }
            )) {
                TextField("New Folder", text: $renameText)
                Button("Cancel", role: .cancel) { renamingFolder = nil }
                Button("Save") { applyRename() }
            }
            .confirmationDialog(
                "Delete this folder? Its templates will be kept and become unfiled.",
                isPresented: Binding(
                    get: { folderPendingDelete != nil },
                    set: { if !$0 { folderPendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Folder", role: .destructive) { deletePendingFolder() }
                Button("Cancel", role: .cancel) { folderPendingDelete = nil }
            }
            .alert("Rename Template", isPresented: Binding(
                get: { renamingTemplate != nil },
                set: { if !$0 { renamingTemplate = nil } }
            )) {
                TextField("Template name", text: $templateRenameText)
                Button("Cancel", role: .cancel) { renamingTemplate = nil }
                Button("Save") { applyTemplateRename() }
            }
            .confirmationDialog(
                "Delete this template? Workout history is kept.",
                isPresented: Binding(
                    get: { templatePendingDelete != nil },
                    set: { if !$0 { templatePendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Template", role: .destructive) { deletePendingTemplate() }
                Button("Cancel", role: .cancel) { templatePendingDelete = nil }
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
        // The "Templates" section header always carries create actions so both
        // paths stay reachable whether or not any rows exist yet.
        sectionHeader(title: "Templates") {
            newFolderName = ""
            showingAddFolder = true
        } onNewTemplate: {
            editorTarget = EditorTarget(template: nil, folder: nil)
        }

        if folders.isEmpty && templates.isEmpty {
            Text("No templates yet. Tap + Template to create one.")
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
        } else if folders.isEmpty {
            // Flat grid, no header — an "Ungrouped" heading would say nothing.
            templateGrid(templates)
        } else {
            ForEach(folders, id: \.id) { folder in
                folderHeader(folder)
                // Empty folders still render their header (count 0, menu
                // reachable). A newly created folder has no templates; the
                // old `if !folderTemplates.isEmpty` guard made Save look
                // like a no-op.
                if !folder.isCollapsed {
                    templateGrid(folder.templates.sorted { $0.order < $1.order })
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

    private func sectionHeader(
        title: String,
        onNewFolder: @escaping () -> Void,
        onNewTemplate: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(Typography.secondary.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button(action: onNewTemplate) {
                Label("Template", systemImage: "plus")
                    .font(Typography.secondary.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            Button(action: onNewFolder) {
                Image(systemName: "folder.badge.plus")
                    .font(Typography.secondary.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Add New Folder", isPresented: $showingAddFolder) {
            TextField("New Folder", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Save") { createFolder() }
        }
    }

    private func folderHeader(_ folder: TemplateFolder) -> some View {
        HStack(spacing: Spacing.compact) {
            Image(systemName: "folder")
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
            Text("\(folder.name) (\(folder.templates.count))")
                .font(Typography.secondary.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            folderMenu(folder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.comfortable)
    }

    // Trailing Menu — same idiom as SetRow.setTypeMenu: the glyph is the
    // menu's label so the row's look stays a header, not a button cluster.
    private func folderMenu(_ folder: TemplateFolder) -> some View {
        Menu {
            Button(folder.isCollapsed ? "Expand Folder" : "Collapse Folder") {
                folder.isCollapsed.toggle()
            }
            Button("Add Template") {
                editorTarget = EditorTarget(template: nil, folder: folder)
            }
            Button("Rename") {
                renameText = folder.name
                renamingFolder = folder
            }
            Button("Delete", role: .destructive) {
                folderPendingDelete = folder
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(Typography.secondary.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background(Theme.accentFill, in: .rect(cornerRadius: Radius.chip))
        }
    }

    private func createFolder() {
        guard let name = NameEditing.normalized(newFolderName) else {
            newFolderName = ""
            return
        }
        let folder = TemplateFolder(
            name: name,
            order: FolderEditing.nextOrder(after: folders.map(\.order)),
            kind: .folder
        )
        context.insert(folder)
        newFolderName = ""
    }

    private func applyRename() {
        guard let folder = renamingFolder,
              let name = NameEditing.normalized(renameText) else {
            renamingFolder = nil
            return
        }
        folder.name = name
        renamingFolder = nil
    }

    private func applyTemplateRename() {
        guard let template = renamingTemplate,
              let name = NameEditing.normalized(templateRenameText) else {
            renamingTemplate = nil
            return
        }
        template.name = name
        renamingTemplate = nil
    }

    private func deletePendingTemplate() {
        guard let template = templatePendingDelete else { return }
        // deleteRule: .cascade on exercises/sets, .nullify on workouts.
        // context.delete(template) is sufficient. Do not loop over
        // template.workouts — that would destroy training history.
        context.delete(template)
        templatePendingDelete = nil
    }

    private func duplicateTemplate(_ template: Template) {
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
    }

    private func deletePendingFolder() {
        guard let folder = folderPendingDelete else { return }
        // deleteRule: .nullify — context.delete(folder) leaves templates
        // alive and unfiled. Do not loop over folder.templates.
        context.delete(folder)
        folderPendingDelete = nil
    }

    private func templateGrid(_ templates: [Template]) -> some View {
        LazyVGrid(columns: columns, spacing: Spacing.comfortable) {
            ForEach(templates, id: \.id) { template in
                TemplateCard(
                    template: template,
                    onTap: {
                        editorTarget = EditorTarget(template: template, folder: nil)
                    },
                    onStart: { onStartTemplate(template) },
                    onEdit: {
                        editorTarget = EditorTarget(template: template, folder: nil)
                    },
                    onRename: {
                        templateRenameText = template.name
                        renamingTemplate = template
                    },
                    onDuplicate: { duplicateTemplate(template) },
                    onDelete: { templatePendingDelete = template }
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
/// trailing play button starts a workout from it; the trailing menu owns
/// edit / rename / duplicate / delete. The card itself is dumb — mutations
/// stay in StartWorkoutTab.
private struct TemplateCard: View {
    let template: Template
    var onTap: () -> Void
    var onStart: () -> Void
    var onEdit: () -> Void
    var onRename: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

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

                    cardMenu
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

    // Trailing Menu — same idiom as folderMenu: the glyph is the menu's
    // label so the card stays a card, not a button cluster.
    private var cardMenu: some View {
        Menu {
            Button("Edit Template") { onEdit() }
            Button("Rename") { onRename() }
            Button("Duplicate") { onDuplicate() }
            Button("Delete", role: .destructive) { onDelete() }
        } label: {
            Image(systemName: "ellipsis")
                .font(Typography.secondary.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background(Theme.accentFill, in: .rect(cornerRadius: Radius.chip))
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
