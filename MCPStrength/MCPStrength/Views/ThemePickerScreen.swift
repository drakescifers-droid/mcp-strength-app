//
//  ThemePickerScreen.swift
//  MCPStrength
//
//  Picks the app's look. Every option paints its own preview in its own
//  palette, so the four are compared side by side rather than by switching,
//  looking, switching back — which matters here more than on most settings
//  screens, because applying a theme rebuilds the view tree and closes Settings
//  behind you (see Theme.swift on why). Choose from the previews; the switch
//  itself is then a one-way trip you only take once.
//
//  The preview deliberately shows the pieces that DECIDE a palette rather than
//  the prettiest ones: a W badge, an accent exercise name, an entry chip, a
//  running rest bar, and the three buttons whose colours must never collapse
//  into each other (Finish green, Save accent, Cancel destructive).
//

import SwiftUI

struct ThemePickerScreen: View {
    @Environment(ThemeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Settings warns that a switch closes the sheet. Onboarding must not.
    var showsSettingsFooter: Bool = true

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.comfortable) {
                ForEach(AppTheme.allCases) { theme in
                    Button {
                        store.selected = theme
                    } label: {
                        ThemeOptionCard(
                            palette: theme.palette,
                            isSelected: theme == store.selected
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.name)
                    .accessibilityValue(theme == store.selected ? "Selected" : "")
                    .accessibilityHint(theme.palette.blurb)
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.comfortable)
        }
        .background(Theme.surface)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if showsSettingsFooter {
            // Said before it happens rather than discovered afterwards — the
            // same courtesy the weight-unit picker pays. Nothing is lost, but a
            // screen closing itself is alarming if it was not announced.
            Text("Changing the look repaints the app and closes Settings. Nothing logged is affected.")
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.comfortable)
                .background(Theme.surface)
            }
        }
    }
}

// MARK: - One option

/// A palette rendering itself. Everything inside reads from the `palette`
/// argument and NOT from `Theme` — four cards have to be four looks at once,
/// which is exactly the thing the global token layer cannot do.
private struct ThemeOptionCard: View {
    let palette: Palette
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            header
            miniature
        }
        .padding(Spacing.comfortable)
        .background(palette.surface.color, in: .rect(cornerRadius: Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card)
                // The selected card is ringed in its own accent; the others get
                // a hairline in their own secondary text colour, so a light
                // palette does not float edgeless on a light screen.
                .strokeBorder(
                    isSelected ? palette.accent.color : palette.textSecondary.color.opacity(0.35),
                    lineWidth: isSelected ? 2 : 1
                )
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.compact) {
            VStack(alignment: .leading, spacing: 2) {
                Text(palette.name)
                    .font(Typography.title)
                    .foregroundStyle(palette.textPrimary.color)
                Text(palette.blurb)
                    .font(Typography.secondary)
                    .foregroundStyle(palette.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.compact)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(palette.accent.color)
            }
        }
    }

    /// A workout row, a rest bar and the three buttons — the parts of the app
    /// where a palette either works or does not.
    private var miniature: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            HStack(spacing: Spacing.compact) {
                Text("W")
                    .font(Typography.badge)
                    .foregroundStyle(palette.warmup.color)
                    .frame(width: 26, height: 24)
                    .background(palette.fieldFill.color, in: .rect(cornerRadius: Radius.badge))
                Text("HS Shoulder Press")
                    .font(Typography.secondary.weight(.semibold))
                    .foregroundStyle(palette.accent.color)
                    .lineLimit(1)
                Spacer(minLength: Spacing.compact)
                chip("90")
                chip("10")
            }

            // A rest running: accent fill, textPrimary ring. The ring is white
            // on the dark looks on purpose — accent-on-accent read as leftover
            // fill — and it stays textPrimary here for the same reason.
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Radius.chip)
                    .fill(palette.fieldFill.color)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: Radius.chip)
                        .fill(palette.accent.color)
                        .frame(width: geo.size.width * 0.68)
                }
                RoundedRectangle(cornerRadius: Radius.chip)
                    .strokeBorder(palette.textPrimary.color, lineWidth: 1.5)
                Text("1:28")
                    .font(Typography.secondary.weight(.semibold))
                    .foregroundStyle(palette.textPrimary.color)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 26)

            HStack(spacing: Spacing.compact) {
                pill("Finish", fill: palette.success.color, text: palette.onSolid.color)
                pill("Save", fill: palette.accent.color, text: palette.onSolid.color)
                pill("Cancel", fill: palette.destructiveFill.color, text: palette.destructive.color)
            }
        }
    }

    private func chip(_ value: String) -> some View {
        Text(value)
            .font(Typography.secondary.weight(.semibold))
            .foregroundStyle(palette.textPrimary.color)
            .frame(width: 40, height: 24)
            .background(palette.fieldFill.color, in: .rect(cornerRadius: Radius.chip))
    }

    private func pill(_ title: String, fill: Color, text: Color) -> some View {
        Text(title)
            .font(Typography.secondary.weight(.semibold))
            .foregroundStyle(text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(fill, in: .rect(cornerRadius: Radius.chip))
    }
}

// MARK: - Previews

#Preview("Appearance") {
    NavigationStack {
        ThemePickerScreen()
    }
    .environment(ThemeStore())
}
