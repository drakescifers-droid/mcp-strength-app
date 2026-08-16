//
//  StartWorkoutTab.swift
//  MCPStrength
//
//  The HOME tab. Absorbs the old TemplatesScreen: a Quick Start action for an
//  empty workout, plus the templates themselves rendered as a two-column grid
//  of cards (grouped under folder headers when folders exist). Tapping a card
//  opens the template overview (Start Workout + Edit). The card menu still
//  reaches the editor directly — Edit lives in both places, matching the
//  reference.
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

    @Query(filter: #Predicate<TemplateFolder> { $0.deletedAt == nil },
           sort: \TemplateFolder.order)
    private var folders: [TemplateFolder]
    @Query(filter: #Predicate<Template> { $0.deletedAt == nil },
           sort: \Template.order)
    private var templates: [Template]

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

    /// Presentation payload for TemplateOverviewSheet. Fresh UUID so identity
    /// is the presentation, matching EditorTarget — not the template's own id.
    private struct OverviewTarget: Identifiable {
        let id = UUID()
        let template: Template
    }

    @State private var overviewTarget: OverviewTarget?

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
            .sheet(item: $overviewTarget) { target in
                TemplateOverviewSheet(template: target.template, onStart: onStartTemplate)
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
                    templateGrid(folder.liveTemplates)
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
            Text("\(folder.name) (\(folder.liveTemplates.count))")
                .font(Typography.secondary.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            folderMenu(folder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.comfortable)
        // Empty folders have no cards to drop onto; the header is the append
        // target so they stay reachable. Also the end-of-list target.
        .dropDestination(for: String.self) { items, _ in
            return handleFolderDrop(items, onto: folder)
        }
    }

    // Trailing Menu — same idiom as SetRow.setTypeMenu: the glyph is the
    // menu's label so the row's look stays a header, not a button cluster.
    private func folderMenu(_ folder: TemplateFolder) -> some View {
        Menu {
            Button(folder.isCollapsed ? "Expand Folder" : "Collapse Folder") {
                folder.isCollapsed.toggle()
                folder.markEdited()
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
        folder.markEdited()
        renamingFolder = nil
    }

    private func applyTemplateRename() {
        guard let template = renamingTemplate,
              let name = NameEditing.normalized(templateRenameText) else {
            renamingTemplate = nil
            return
        }
        template.name = name
        template.markEdited()
        renamingTemplate = nil
    }

    private func deletePendingTemplate() {
        guard let template = templatePendingDelete else { return }
        // Tombstone, never context.delete: a device that was offline when
        // this happened has to learn about it, and a removed row cannot tell
        // it anything. SoftDelete.template walks the .cascade rule by hand and
        // deliberately leaves template.workouts alone — deleting a template
        // must never delete the training performed from it.
        SoftDelete.template(template)
        templatePendingDelete = nil
    }

    private func duplicateTemplate(_ template: Template) {
        let copy = Template(
            name: TemplateEditing.duplicateName(
                of: template.name,
                existing: templates.map(\.name)
            ),
            note: template.note,
            // Per-folder position: land after the last card in THIS folder,
            // not after the global max.
            order: templates.filter { $0.folder?.id == template.folder?.id }.count,
            lastPerformedAt: nil,
            folder: template.folder
        )
        context.insert(copy)

        for sourceExercise in template.liveExercises {
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

            for sourceSet in sourceExercise.liveSets {
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
        // .nullify on templates is enacted by doing nothing: they stay
        // alive and read as unfiled. SoftDelete.folder cascades only to the
        // folder's program days.
        SoftDelete.folder(folder)
        folderPendingDelete = nil
    }

    private func templateGrid(_ templates: [Template]) -> some View {
        LazyVGrid(columns: columns, spacing: Spacing.comfortable) {
            ForEach(templates, id: \.id) { template in
                TemplateCard(
                    template: template,
                    onTap: {
                        overviewTarget = OverviewTarget(template: template)
                    },
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
                // Long-press starts the drag; the card's tap still opens overview.
                .draggable(template.id.uuidString)
                .dropDestination(for: String.self) { items, _ in
                    return handleCardDrop(items, onto: template)
                }
            }
        }
    }

    /// Ids of templates in `folder` (nil = unfiled), sorted by per-folder `order`.
    private func orderedIDs(in folder: TemplateFolder?) -> [UUID] {
        templates
            .filter { $0.folder?.id == folder?.id }
            .sorted { $0.order < $1.order }
            .map(\.id)
    }

    /// Drop onto a card: insert at that card's position in its list after the
    /// dragged id has been removed (the ListOrdering index convention).
    private func handleCardDrop(_ items: [String], onto target: Template) -> Bool {
        guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
        if id == target.id { return true }
        var dest = orderedIDs(in: target.folder)
        dest.removeAll { $0 == id }
        guard let index = dest.firstIndex(of: target.id) else { return false }
        return applyTemplateMove(id, to: target.folder, at: index)
    }

    /// Drop onto a folder header: append. Makes empty folders reachable.
    private func handleFolderDrop(_ items: [String], onto folder: TemplateFolder) -> Bool {
        guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
        var dest = orderedIDs(in: folder)
        dest.removeAll { $0 == id }
        return applyTemplateMove(id, to: folder, at: dest.count)
    }

    private func applyTemplateMove(_ id: UUID, to destFolder: TemplateFolder?, at index: Int) -> Bool {
        guard let moved = templates.first(where: { $0.id == id }) else { return false }
        let source = orderedIDs(in: moved.folder)
        let destination = orderedIDs(in: destFolder)
        let result = ListOrdering.move(id, from: source, to: destination, at: index)
        let byID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
        for (i, tid) in result.source.enumerated() {
            byID[tid]?.order = i
            byID[tid]?.markEdited()
        }
        for (i, tid) in result.destination.enumerated() {
            byID[tid]?.order = i
            byID[tid]?.markEdited()
        }
        moved.folder = destFolder
        moved.markEdited()
        return true
    }
}

// MARK: - TemplateCard

/// One card in the two-column templates grid: the template name, the exercise
/// names joined and truncated to a few lines in `textSecondary`, and — when
/// `lastPerformedAt` is set — a clock icon with a relative last-performed
/// string ("Yesterday", "4 days ago"). Tapping the card opens the overview;
/// the trailing menu owns edit / rename / duplicate / delete. The card itself
/// is dumb — mutations stay in StartWorkoutTab.
private struct TemplateCard: View {
    let template: Template
    var onTap: () -> Void
    var onEdit: () -> Void
    var onRename: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.compact) {
                HStack(alignment: .top, spacing: Spacing.compact) {
                    Text(template.name)
                        .font(Typography.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)

                    cardMenu
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
                        Text(RelativeDate.lastPerformed(from: lastPerformedAt))
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

    /// The exercise names joined by commas. Falls back to a plain count when
    /// there are no named exercises yet.
    private var exerciseSummary: String {
        let sorted = template.liveExercises
        let names = sorted.compactMap { $0.exercise?.name }
        let countWord = sorted.count == 1 ? "exercise" : "exercises"
        if names.isEmpty {
            return "\(sorted.count) \(countWord)"
        }
        return names.joined(separator: ", ")
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
