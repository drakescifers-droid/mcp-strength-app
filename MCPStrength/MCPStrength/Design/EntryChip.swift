//
//  EntryChip.swift
//  MCPStrength
//

import SwiftUI

// MARK: - Entry chip
//
// The weight/reps entry fields in the reference are compact chips: a
// `fieldFill` background, a chip-radius rounded rect, centred text. Apply with
// `.entryChipStyle()` to a `Text` or `TextField`.

/// Styles a view as a weight/reps entry chip: `fieldFill` background, chip corner
/// radius, centred content, compact padding.
struct EntryChipStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Typography.chipValue)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.compact)
            .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.chip))
    }
}

extension View {
    /// Apply the weight/reps entry chip look — field fill, chip radius, centred.
    func entryChipStyle() -> some View {
        modifier(EntryChipStyleModifier())
    }
}
