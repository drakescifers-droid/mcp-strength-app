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

/// One editable set row: badge, previous, weight chip, reps chip, RPE chip,
/// trailing.
///
/// Weight is passed as a binding to `Double?`. Reps is passed as a binding to a
/// `RepRange?` prescription: the template screen may carry a range ("6-8") or a
/// fixed target ("8"); the workout screen carries only a fixed number. The
/// `allowRange` flag controls whether a dashed form is accepted — the workout
/// screen sets it false (a performance has a number, not a range).
///
/// RPE is optional everywhere and lives behind a compact Menu chip: empty shows
/// the label "RPE" (discoverable, never invisible); set shows the value. An
/// empty RPE never blocks anything.
///
/// Weight/reps text are held in local `String` state so the user can type "85."
/// or "6-8" without the field snapping back mid-keystroke; values commit through
/// to the binding on every change that parses (or clear when empty). Invalid
/// reps text is left as-is and flagged with a destructive tint so the user can
/// fix the typo — nothing wrong is ever written.
struct SetRow: View {
    @Binding var setType: SetType
    let setNumber: Int?
    let previousText: String
    @Binding var weight: Double?
    @Binding var prescription: RepRange?
    let allowRange: Bool
    @Binding var rpe: Double?
    let trailing: SetRowTrailing

    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @State private var repsValid: Bool = true
    @State private var didSync: Bool = false

    var body: some View {
        HStack(spacing: Spacing.compact) {
            setTypeMenu
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
                .frame(width: 56)
                .onChange(of: weightText) { _, newValue in commitWeight(newValue) }

            repsField
                .frame(width: 52)

            rpeField
                .frame(width: 44)

            trailingView
                .frame(width: 32)
        }
        .padding(.vertical, Spacing.compact)
        .background(rowTint, in: .rect(cornerRadius: Radius.chip))
        .onAppear { syncFromModel() }
    }

    // MARK: - Set-type menu

    // The leading badge is also a Menu: tapping it offers all four set types
    // with a checkmark on the current value. Same idiom as `rpeField` below —
    // the badge itself is the menu's label so the row's look is unchanged.
    private var setTypeMenu: some View {
        Menu {
            ForEach(SetType.allCases, id: \.self) { type in
                Button {
                    setType = type
                } label: {
                    if type == setType {
                        Label(setTypeLabel(type), systemImage: "checkmark")
                    } else {
                        Text(setTypeLabel(type))
                    }
                }
            }
        } label: {
            SetTypeBadge(setType: setType, setNumber: setNumber)
        }
    }

    private func setTypeLabel(_ type: SetType) -> String {
        switch type {
        case .normal:  return "Normal"
        case .warmup:  return "Warm up"
        case .dropSet: return "Drop set"
        case .failure: return "Failure"
        }
    }

    // MARK: - Reps field

    // Accepts "8" (a fixed target) on both screens, and "6-8" (a range) on the
    // template screen. A fixed target clears any range; a range clears any
    // fixed target — the two are mutually exclusive (see RepRange.templateFields).
    // Invalid text is kept locally and tinted destructive; a wrong value is
    // never written.
    private var repsField: some View {
        TextField("", text: $repsText)
            .keyboardType(allowRange ? .default : .numberPad)
            .textInputAutocapitalization(.never)
            .foregroundStyle(repsValid ? Theme.textPrimary : Theme.destructive)
            .entryChipStyle()
            .overlay {
                if !repsValid {
                    RoundedRectangle(cornerRadius: Radius.chip)
                        .stroke(Theme.destructive, lineWidth: 1)
                }
            }
            .onChange(of: repsText) { _, newValue in commitReps(newValue) }
    }

    // MARK: - RPE field

    // A compact optional column. Empty shows the "RPE" label (secondary) so the
    // field is discoverable, not invisible; set shows the value (primary). Tapping
    // opens a Menu of the allowed steps plus "None" to clear. RPE is optional
    // everywhere, so empty is completely normal and never blocks anything.
    private var rpeField: some View {
        Menu {
            Button {
                rpe = nil
            } label: {
                if rpe == nil {
                    Label("None", systemImage: "checkmark")
                } else {
                    Text("None")
                }
            }
            ForEach(RPE.allowedValues, id: \.self) { value in
                Button {
                    rpe = value
                } label: {
                    if rpe == value {
                        Label(RPE.format(value), systemImage: "checkmark")
                    } else {
                        Text(RPE.format(value))
                    }
                }
            }
        } label: {
            Text(rpe.map { RPE.format($0) } ?? "RPE")
                .font(Typography.chipValue)
                .foregroundStyle(rpe == nil ? Theme.textSecondary : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.compact)
                .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.chip))
        }
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
        if let p = prescription {
            repsText = RepRangeParser.format(p)
            repsValid = true
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
        switch RepRangeParser.parse(text, allowRange: allowRange) {
        case .unset:
            repsValid = true
            prescription = nil
        case .valid(let range):
            repsValid = true
            // Setting a fixed target clears any existing range; setting a range
            // clears any fixed target — enforced by RepRange.templateFields().
            prescription = range
        case .invalid:
            // Keep the user's text locally (non-destructive) and flag it; do
            // NOT write a wrong value to the prescription.
            repsValid = false
        }
    }
}

// MARK: - SetRowColumnHeader

/// The `Set | Previous | lbs | Reps | RPE | <trailing>` column header shared by
/// both screens. Only the trailing glyph differs — `checkmark` for the workout,
/// a lock for the template — so the column widths stay identical.
struct SetRowColumnHeader: View {
    let trailingIcon: String

    var body: some View {
        HStack(spacing: Spacing.compact) {
            Text("Set")
                .frame(width: 28, alignment: .leading)
            Text("Previous")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("lbs")
                .frame(width: 56, alignment: .center)
            Text("Reps")
                .frame(width: 52, alignment: .center)
            Text("RPE")
                .frame(width: 44, alignment: .center)
            Image(systemName: trailingIcon)
                .frame(width: 32, alignment: .center)
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
///
/// Tapping it edits THIS set's `restSeconds`. That is a different value from
/// the exercise's `defaultRestSeconds`, which the options menu edits and which
/// only new sets inherit — changing one has never changed the other, so the
/// number shown here needs its own way in.
struct RestDivider: View {
    let restSeconds: Int

    /// Optional so the divider stays usable as pure display. When nil it has no
    /// tap target at all, rather than a dead one.
    var onTap: (() -> Void)?

    var body: some View {
        if let onTap {
            Button(action: onTap) { divider }
                .buttonStyle(.plain)
                // A hairline is far below the 44pt minimum target, and the row
                // cannot simply be made taller without changing the spacing
                // between every pair of sets. Pad out, claim that area as the
                // hit shape, then remove the padding again from layout: the
                // divider looks identical and is comfortably tappable.
                .padding(.vertical, Spacing.comfortable)
                .contentShape(Rectangle())
                .padding(.vertical, -Spacing.comfortable)
                .accessibilityLabel("Rest \(formatMinutesSeconds(restSeconds))")
                .accessibilityHint("Edit this set's rest")
        } else {
            divider
        }
    }

    private var divider: some View {
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
