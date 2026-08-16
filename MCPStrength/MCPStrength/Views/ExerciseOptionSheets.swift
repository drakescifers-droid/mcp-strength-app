//
//  ExerciseOptionSheets.swift
//  MCPStrength
//
//  The small editors the options menu opens: a note, a sticky note, and the
//  default rest timer.
//
//  Shared for the same reason the menu is: the template editor and the live
//  workout ask the identical question, and two copies would drift the moment
//  one gained a field.
//

import SwiftUI

// MARK: - Note editor

/// A sheet for editing a note or a sticky note.
///
/// One view for both, because the only difference is the wording. A separate
/// `StickyNoteSheet` would be the same file with two strings changed, which is
/// how `BodyPart.displayName` ended up defined twice.
struct ExerciseNoteSheet: View {
    /// A sticky note stays pinned under the exercise while logging; a plain
    /// note lives behind the menu. Only the copy differs.
    let isSticky: Bool
    let exerciseName: String
    @State private var text: String
    let onSave: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        isSticky: Bool,
        exerciseName: String,
        initialText: String?,
        onSave: @escaping (String?) -> Void
    ) {
        self.isSticky = isSticky
        self.exerciseName = exerciseName
        self._text = State(initialValue: initialText ?? "")
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.comfortable) {
                Text(exerciseName)
                    .font(Typography.secondary)
                    .foregroundStyle(Theme.textSecondary)

                TextEditor(text: $text)
                    .font(Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.compact)
                    .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.chip))
                    .frame(minHeight: 140)

                if isSticky {
                    Text("A sticky note stays visible under the exercise while you log.")
                        .font(Typography.secondary)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()
            }
            .padding(Spacing.screenMargin)
            .background(Theme.surface)
            .navigationTitle(isSticky ? "Sticky Note" : "Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        // Empty means REMOVED, not an empty string. An empty
                        // note that still counts as "has a note" would leave the
                        // menu reading "Edit Note" forever with nothing to edit.
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? nil : trimmed)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Rest timer editor

/// Picks a rest duration, for either of the two things rest can mean.
///
/// Deliberately a list of common values rather than a free-text field. Rest is
/// chosen from a handful of habits — 60, 90, two minutes — and a keyboard for a
/// number you pick from six options is friction mid-session, which is precisely
/// when this gets used.
struct RestTimerSheet: View {
    /// WHICH rest is being set. The two are different values on different rows
    /// and the sheet must say which one it is about: `defaultRestSeconds` is
    /// what new sets inherit, `restSeconds` is one set's own rest. The menu
    /// edits the first, tapping a divider edits the second, and telling a user
    /// "new sets will use this" while editing an existing set is simply false.
    enum Scope {
        case newSets(exerciseName: String)
        case oneSet

        var explanation: String {
            switch self {
            case .newSets(let name):
                "New sets in \(name) will use this."
            case .oneSet:
                "Sets the rest after this set. Other sets keep theirs."
            }
        }
    }

    let scope: Scope
    let current: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Seconds. Includes 0 because "no rest timer" is a real preference, not an
    /// absence of one — a superset accessory does not want a countdown.
    private let options = [0, 30, 45, 60, 90, 120, 150, 180, 240, 300]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(options, id: \.self) { seconds in
                        Button {
                            onSelect(seconds)
                            dismiss()
                        } label: {
                            HStack {
                                Text(seconds == 0 ? "No rest timer" : formatMinutesSeconds(seconds))
                                    .font(Typography.body)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if seconds == current {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(.vertical, Spacing.comfortable)
                            .padding(.horizontal, Spacing.screenMargin)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if seconds != options.last {
                            Rectangle()
                                .fill(Theme.fieldFill)
                                .frame(height: 1)
                                .padding(.leading, Spacing.screenMargin)
                        }
                    }
                }
            }
            .background(Theme.surface)
            .navigationTitle("Rest Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top) {
                Text(scope.explanation)
                    .font(Typography.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.vertical, Spacing.compact)
                    .background(Theme.surface)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Note") {
    ExerciseNoteSheet(
        isSticky: true,
        exerciseName: "Bench Press (Barbell)",
        initialText: "Elbows tucked",
        onSave: { _ in }
    )
}

#Preview("Rest — new sets") {
    RestTimerSheet(
        scope: .newSets(exerciseName: "Bench Press (Barbell)"),
        current: 90,
        onSelect: { _ in }
    )
}

#Preview("Rest — one set") {
    RestTimerSheet(scope: .oneSet, current: 120, onSelect: { _ in })
}
