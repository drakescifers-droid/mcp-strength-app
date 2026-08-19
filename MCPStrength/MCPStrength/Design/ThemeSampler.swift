//
//  ThemeSampler.swift
//  MCPStrength
//

import SwiftUI

// MARK: - Theme sampler
//
// One screen showing every token and every style in the system so the whole
// vocabulary can be eyeballed at once. This is the deliverable a human reviews.
// Run it in the Xcode preview canvas.

struct ThemeSampler: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.spacious) {
                colorSection
                scaleSection
                buttonSection
                chipSection
                badgeSection
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.spacious)
        }
        .background(Theme.surface)
    }

    // MARK: Colours

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: Spacing.comfortable) {
            sectionHeader("Colour tokens")
            swatchGrid
        }
    }

    private var swatchGrid: some View {
        VStack(spacing: Spacing.compact) {
            swatchRow("surface", Theme.surface, "#293136")
            swatchRow("fieldFill", Theme.fieldFill, "#1F252A")
            swatchRow("accent", Theme.accent, "#35A7FF")
            swatchRow("accentFill", Theme.accentFill, "#2C4E68")
            swatchRow("success", Theme.success, "#2ECD70")
            swatchRow("destructive", Theme.destructive, "#FF5964")
            swatchRow("destructiveFill", Theme.destructiveFill, "#3E353A")
            swatchRow("textPrimary", Theme.textPrimary, "#FFFFFF")
            swatchRow("textSecondary", Theme.textSecondary, "#94989A")
            swatchRow("warmup", Theme.warmup, "#FFA13B")
            swatchRow("dropSet", Theme.dropSet, "#8826FC")
            swatchRow("notice", Theme.notice, "#ECC12E")
            swatchRow("noticeText", Theme.noticeText, "#251E0A")
            // failure is an alias of destructive — show it aliased, not duplicated.
            swatchRow("failure (= destructive)", Theme.failure, "#FF5964")
        }
    }

    private func swatchRow(_ name: String, _ color: Color, _ hex: String) -> some View {
        HStack(spacing: Spacing.comfortable) {
            RoundedRectangle(cornerRadius: Radius.chip)
                .fill(color)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(Typography.body).foregroundStyle(Theme.textPrimary)
                Text(hex).font(Typography.secondary).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: Scales (spacing / radius / typography)

    private var scaleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.comfortable) {
            sectionHeader("Spacing · Radius · Typography")

            HStack(spacing: Spacing.compact) {
                scaleBar("screenMargin", Spacing.screenMargin)
                scaleBar("buttonVertical", Spacing.buttonVertical)
                scaleBar("compact", Spacing.compact)
                scaleBar("comfortable", Spacing.comfortable)
                scaleBar("spacious", Spacing.spacious)
            }

            HStack(spacing: Spacing.compact) {
                radiusBox("button", Radius.button)
                radiusBox("chip", Radius.chip)
                radiusBox("badge", Radius.badge)
                radiusBox("card", Radius.card)
            }

            VStack(alignment: .leading, spacing: Spacing.compact) {
                typeSample("title", Typography.title)
                typeSample("body", Typography.body)
                typeSample("secondary", Typography.secondary)
                typeSample("chipValue", Typography.chipValue)
                typeSample("badge", Typography.badge)
                typeSample("button", Typography.button)
            }
        }
    }

    private func scaleBar(_ name: String, _ value: CGFloat) -> some View {
        VStack(spacing: 4) {
            Rectangle()
                .fill(Theme.accent)
                .frame(width: value, height: 28)
            Text(name).font(Typography.secondary).foregroundStyle(Theme.textSecondary)
                .frame(width: 64)
            Text("\(Int(value))").font(Typography.secondary).foregroundStyle(Theme.textSecondary)
        }
    }

    private func radiusBox(_ name: String, _ value: CGFloat) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: value)
                .stroke(Theme.accent, lineWidth: 1.5)
                .fill(Theme.accentFill)
                .frame(width: 56, height: 56)
            Text("\(name) \(Int(value))").font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func typeSample(_ name: String, _ font: Font) -> some View {
        HStack(spacing: Spacing.comfortable) {
            Text(name).font(Typography.secondary).foregroundStyle(Theme.textSecondary)
                .frame(width: 84, alignment: .leading)
            Text("The quick brown fox").font(font).foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: Buttons

    private var buttonSection: some View {
        VStack(alignment: .leading, spacing: Spacing.comfortable) {
            sectionHeader("Buttons")
            Button("Add Exercises") {}
                .buttonStyle(.tintedAccent)
            Button("Cancel Workout") {}
                .buttonStyle(.tintedDestructive)
            Button("Finish") {}
                .buttonStyle(.primaryAction)
        }
    }

    // MARK: Entry chips

    private var chipSection: some View {
        VStack(alignment: .leading, spacing: Spacing.comfortable) {
            sectionHeader("Entry chips (weight / reps)")
            HStack(spacing: Spacing.compact) {
                Text("225").entryChipStyle().foregroundStyle(Theme.textPrimary)
                Text("8").entryChipStyle().foregroundStyle(Theme.textPrimary)
                Text("RPE 8").entryChipStyle().foregroundStyle(Theme.textPrimary)
            }
            HStack(spacing: Spacing.compact) {
                Text("Previous")
                    .font(Typography.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("245 × 5").entryChipStyle().foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: 90)
            }
        }
    }

    // MARK: Set-type badges

    private var badgeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.comfortable) {
            sectionHeader("Set-type badges")
            HStack(spacing: Spacing.compact) {
                SetTypeBadge(setType: .warmup, setNumber: 0)
                SetTypeBadge(setType: .normal, setNumber: 1)
                SetTypeBadge(setType: .normal, setNumber: 2)
                SetTypeBadge(setType: .normal, setNumber: 3)
                SetTypeBadge(setType: .dropSet, setNumber: 0)
                SetTypeBadge(setType: .failure, setNumber: 0)
            }
            Text("Failure badge uses Theme.failure, an alias of destructive — "
                 + "retuning destructive red moves it automatically.")
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Typography.title)
            .foregroundStyle(Theme.textPrimary)
            .padding(.bottom, 2)
    }
}

#Preview {
    ThemeSampler()
}
