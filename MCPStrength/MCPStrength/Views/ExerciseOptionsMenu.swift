//
//  ExerciseOptionsMenu.swift
//  MCPStrength
//
//  The per-exercise options menu. ONE component, two callers: the template
//  editor and the live workout.
//
//  ## Why it is shared rather than written twice
//
//  The menu is identical in both places — same items, same order, same
//  wording — and this codebase has already learned twice what happens when
//  something identical is written twice. `BodyPart.displayName` was duplicated
//  and had to be pulled into `Design/EnumLabels.swift`; `TemplateOrdering` was
//  renamed to `ListOrdering` the moment workout exercises became its second
//  caller. Two menus that happen to match today would be the third instance,
//  and they would stop matching the first time one of them gained an item.
//
//  Making it shared also forced a real fix: `WorkoutExercise` did not have
//  `stickyNote` or `defaultRestSeconds`, so two items would have been greyed
//  out mid-workout. The claim "the menu is the same in both places" was not
//  true until the data could back it.
//
//  ## All eight items are here now
//
//  **Preferences** was the last one, and it was absent rather than disabled
//  for two phases — a permanently grey row reads as a broken feature, which is
//  worse than a menu that is honestly shorter. It landed once the four
//  per-user fields moved off `Exercise` onto `ExercisePreference`
//  (docs/06-sync.md), because until then a preference could not be stored in a
//  way that could ever sync. `ExercisePreferencesSheet` is the editor and
//  `ExercisePreference.current(for:in:)` is the write path.
//
//  **Add Warm-up Sets** was the one before it. It was blocked on "a settings
//  model for percentages and rounding", which turned out not to exist as a
//  requirement at all: the reference app offers no way to adjust them. You
//  generate the sets and edit the SETS. So the ramp is hard-coded in
//  `WarmupSets` and the whole settings model evaporated.
//
//  > **Both of those absences were right, and both were resolved by fixing the
//  > thing underneath rather than by shipping the item greyed out.** That is
//  > the pattern worth keeping when the ninth item shows up.
//

import SwiftUI

/// What the caller is being asked to do. The menu itself owns no behaviour —
/// the two screens store different types and delete through different paths, so
/// each handles the action its own way.
enum ExerciseOption: Equatable, Sendable {
    case addNote
    case addStickyNote
    case addWarmupSets
    case updateRestTimers
    case preferences
    case replaceExercise
    case createSuperset
    case removeExercise
}

/// The `⋯` button and its menu, for one exercise.
struct ExerciseOptionsMenu: View {
    /// Whether this exercise already carries a note, so the item can read
    /// "Edit Note" rather than offering to add a second one.
    var hasNote: Bool = false
    var hasStickyNote: Bool = false
    /// Whether this exercise is already part of a superset group.
    var isInSuperset: Bool = false

    let onSelect: (ExerciseOption) -> Void

    var body: some View {
        Menu {
            Button {
                onSelect(.addNote)
            } label: {
                Label(hasNote ? "Edit Note" : "Add Note", systemImage: "doc.text")
            }

            Button {
                onSelect(.addStickyNote)
            } label: {
                Label(
                    hasStickyNote ? "Edit Sticky Note" : "Add Sticky Note",
                    systemImage: "pin"
                )
            }

            // "Add", not "Update", even though a second tap REPLACES the
            // warm-ups already there. The neighbouring "Update Rest Timers"
            // made "Update Warm-up Sets" look like the parallel name, and it
            // is not what the reference app calls it — the user is adding
            // warm-up sets to an exercise, and the replacement is how a second
            // tap corrects a working weight typed after the first one.
            Button {
                onSelect(.addWarmupSets)
            } label: {
                Label("Add Warm-up Sets", systemImage: "flame")
            }

            Button {
                onSelect(.updateRestTimers)
            } label: {
                Label("Update Rest Timers", systemImage: "timer")
            }

            Button {
                onSelect(.preferences)
            } label: {
                Label("Preferences", systemImage: "slider.horizontal.3")
            }

            Button {
                onSelect(.replaceExercise)
            } label: {
                Label("Replace Exercise", systemImage: "arrow.2.squarepath")
            }

            Button {
                onSelect(.createSuperset)
            } label: {
                Label(
                    isInSuperset ? "Leave Superset" : "Create Superset",
                    systemImage: "list.bullet.indent"
                )
            }

            // `role: .destructive` so the system renders it red and last,
            // matching every other destructive action in the app rather than
            // this menu inventing its own treatment.
            Button(role: .destructive) {
                onSelect(.removeExercise)
            } label: {
                Label("Remove Exercise", systemImage: "xmark")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(Typography.secondary.weight(.semibold))
                .foregroundStyle(Theme.accent)
                // A bare glyph is a ~10pt tap target. The padded shape is what
                // makes this hittable with a thumb mid-set, which is the only
                // time it gets used.
                .padding(.horizontal, Spacing.compact)
                .padding(.vertical, 4)
                .background(Theme.accentFill, in: .rect(cornerRadius: Radius.badge))
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Exercise options")
    }
}

#Preview {
    VStack(spacing: Spacing.spacious) {
        ExerciseOptionsMenu { _ in }
        ExerciseOptionsMenu(hasNote: true, hasStickyNote: true, isInSuperset: true) { _ in }
    }
    .padding()
    .background(Theme.surface)
    .preferredColorScheme(.dark)
}
