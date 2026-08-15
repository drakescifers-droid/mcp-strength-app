//
//  SetRow.swift
//  MCPStrength
//
//  The shared set row. A template is a workout you have not performed yet, so
//  the template editor and the active-workout screen render their set rows with
//  the SAME layout: `Set | Previous | lbs | Reps` columns, the same badge, the
//  same entry chips, the same rest dividers. The only thing that differs is the
//  trailing affordance — a workout row ends in a completion checkmark, a
//  template row ends in a lock glyph. This file owns that shared surface so the
//  two screens cannot drift on the thing the user is actually looking at.
//

import SwiftUI

// MARK: - Trailing affordance

/// What renders in the final column of a set row.
///
/// - `.completion`: the workout-screen row. A checkmark that reflects
///   `isCompleted` and toggles via `onToggle`. The row also tints green when
///   complete so finished rows read differently at a glance.
/// - `.locked`: the template-screen row. A lock glyph with no behaviour — a
///   template has nothing to complete, so the column is an affordance only.
enum SetRowTrailing {
    case completion(isCompleted: Bool, onToggle: () -> Void)
    case locked
}

// MARK: - SetRow

/// One editable set row: badge, previous, weight chip, reps chip, trailing.
///
/// Weight and reps are passed as bindings so the row is decoupled from any
/// particular model type — a `WorkoutSet` and a `TemplateSet` (or an in-memory
/// draft) both plug in by handing over `Binding`s to their `weight` / `reps`.
///
/// Weight/reps are held in local `String` state so the user can type "85."
/// without the field snapping back to "85" mid-keystroke; values commit through
/// to the binding on every change that parses (or clear when empty).
struct SetRow: View {
    let setType: SetType
    let setNumber: Int
    let previousText: String
    @Binding var weight: Double?
    @Binding var reps: Int?
    let trailing: SetRowTrailing

    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @State private var didSync: Bool = false

    var body: some View {
        HStack(spacing: Spacing.compact) {
            SetTypeBadge(setType: setType, setNumber: setNumber)
                .frame(width: 28)

            Text(previousText)
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            TextField("", text: $weightText)
                .keyboardType(.decimalPad)
                .textInputAutocapitalization(.never)
                .foregroundStyle(Theme.textPrimary)
                .entryChipStyle()
                .frame(width: 64)
                .onChange(of: weightText) { _, newValue in commitWeight(newValue) }

            TextField("", text: $repsText)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .foregroundStyle(Theme.textPrimary)
                .entryChipStyle()
                .frame(width: 56)
                .onChange(of: repsText) { _, newValue in commitReps(newValue) }

            trailingView
                .frame(width: 36)
        }
        .padding(.vertical, Spacing.compact)
        .background(rowTint, in: .rect(cornerRadius: Radius.chip))
        .onAppear { syncFromModel() }
    }

    // MARK: - Trailing

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .completion(let isCompleted, let onToggle):
            Button {
                onToggle()
            } label: {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(isCompleted ? Theme.success : Theme.textSecondary)
            }
            .buttonStyle(.plain)

        case .locked:
            Image(systemName: "lock.fill")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// A subtle success tint behind a completed workout set; clear otherwise
    /// (templates never complete).
    private var rowTint: Color {
        switch trailing {
        case .completion(let isCompleted, _):
            return isCompleted ? Theme.success.opacity(0.12) : Color.clear
        case .locked:
            return Color.clear
        }
    }

    // MARK: - Sync / commit

    private func syncFromModel() {
        guard !didSync else { return }
        didSync = true
        if let w = weight {
            weightText = PreviousText.formatWeight(w)
        }
        if let r = reps {
            repsText = String(r)
        }
    }

    private func commitWeight(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            weight = nil
        } else if let value = Double(trimmed) {
            weight = value
        }
        // Unparseable input (e.g. "85.") is left as-is locally without writing,
        // so the user can finish typing the decimal.
    }

    private func commitReps(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            reps = nil
        } else if let value = Int(trimmed) {
            reps = value
        }
    }
}

// MARK: - SetRowColumnHeader

/// The `Set | Previous | lbs | Reps | <trailing>` column header shared by both
/// screens. Only the trailing glyph differs — `checkmark` for the workout, a
/// lock for the template — so the column widths stay identical.
struct SetRowColumnHeader: View {
    let trailingIcon: String

    var body: some View {
        HStack(spacing: Spacing.compact) {
            Text("Set")
                .frame(width: 28, alignment: .leading)
            Text("Previous")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("lbs")
                .frame(width: 64, alignment: .center)
            Text("Reps")
                .frame(width: 56, alignment: .center)
            Image(systemName: trailingIcon)
                .frame(width: 36, alignment: .center)
        }
        .font(Typography.secondary)
        .foregroundStyle(Theme.textSecondary)
    }
}

// MARK: - RestDivider

/// The thin rest divider shown between sets: a hairline, the rest time in
/// `m:ss`, another hairline. The workout screen replaces this with a progress
/// bar while a rest is running; the template screen always uses this static
/// form.
struct RestDivider: View {
    let restSeconds: Int

    var body: some View {
        HStack(spacing: Spacing.compact) {
            Rectangle()
                .fill(Theme.fieldFill)
                .frame(height: 1)
            Text(formatMinutesSeconds(restSeconds))
                .font(Typography.secondary)
                .foregroundStyle(Theme.accent)
                .monospacedDigit()
            Rectangle()
                .fill(Theme.fieldFill)
                .frame(height: 1)
        }
        .padding(.vertical, Spacing.compact)
    }
}

// MARK: - AddSetButton

/// The "+ Add Set" row shared by both screens. The label carries the default
/// rest time; the action is screen-specific.
struct AddSetButton: View {
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Typography.body)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.compact)
                .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.button))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Time formatting

/// `m:ss` for a duration in seconds. Shared by the rest dividers of both
/// screens (and any other duration label) so the two never format differently.
func formatMinutesSeconds(_ total: Int) -> String {
    let m = max(0, total) / 60
    let s = max(0, total) % 60
    return String(format: "%d:%02d", m, s)
}
