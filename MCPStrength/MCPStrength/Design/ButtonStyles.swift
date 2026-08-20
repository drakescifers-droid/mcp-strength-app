//
//  ButtonStyles.swift
//  MCPStrength
//

import SwiftUI

// MARK: - Tinted button
//
// The core idiom of this UI: a desaturated fill of a hue with saturated text of
// the same hue on top. "Add Exercises" (accent) and "Cancel Workout"
// (destructive) are the *same* style with different arguments — not two
// hand-built buttons.

/// A button rendered as a tinted fill: a desaturated background with saturated
/// text of the same hue. Parameterise with the `(fill, text)` pair so accent and
/// destructive are one style, two arguments.
struct TintedButtonStyle: ButtonStyle {
    let fill: Color
    let text: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.button)
            .foregroundStyle(text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.buttonVertical)
            .background(fill, in: .rect(cornerRadius: Radius.button))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

extension ButtonStyle where Self == TintedButtonStyle {
    /// Accent-tinted button — e.g. "Add Exercises".
    static var tintedAccent: TintedButtonStyle {
        .init(fill: Theme.accentFill, text: Theme.accent)
    }

    /// Destructive-tinted button — e.g. "Cancel Workout".
    static var tintedDestructive: TintedButtonStyle {
        .init(fill: Theme.destructiveFill, text: Theme.destructive)
    }
}

// MARK: - Primary action
//
// A solid saturated fill with `onSolid` text — the affirmative path.
// "Finish" is the reference instance, in `success`.

/// A solid-fill button for the primary affirmative action (e.g. "Finish").
/// Solid `success` fill, `onSolid` text.
struct PrimaryActionButtonStyle: ButtonStyle {
    var fill: Color = Theme.success

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.button)
            // `onSolid`, not `textPrimary`. Identical on every dark palette;
            // the difference only shows up on Blush, where the title colour
            // would vanish into a solid green fill.
            .foregroundStyle(Theme.onSolid)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.buttonVertical)
            .background(fill, in: .rect(cornerRadius: Radius.button))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

extension ButtonStyle where Self == PrimaryActionButtonStyle {
    /// The default primary action — success fill, white text.
    static var primaryAction: PrimaryActionButtonStyle { .init() }
}
