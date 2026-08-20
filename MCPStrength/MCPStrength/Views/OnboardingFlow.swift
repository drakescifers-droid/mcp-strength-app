//
//  OnboardingFlow.swift
//  MCPStrength
//
//  Theme → units → Apple Health → how to connect Claude or ChatGPT.
//  Step lives on `OnboardingStore` so picking a theme (which rebuilds the
//  root view) does not send the user back to the start.
//

import SwiftUI
import SwiftData
import UIKit

struct OnboardingFlow: View {
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(\.modelContext) private var context
    @Environment(HealthStore.self) private var health: HealthStore?

    @Query(
        filter: #Predicate<AppSettings> { $0.deletedAt == nil },
        sort: \AppSettings.createdAt,
        order: .forward
    )
    private var settings: [AppSettings]

    @State private var copiedConnector = false

    private var weightUnit: WeightUnit {
        settings.first?.weightUnit ?? .lbs
    }

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            VStack(spacing: 0) {
                Text(title)
                    .font(Typography.title)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.top, Spacing.spacious)
                    .padding(.bottom, Spacing.comfortable)

                stepBody
            }
        }
    }

    private var title: String {
        switch onboarding.step {
        case .theme:     "Choose a look"
        case .units:     "Weight unit"
        case .health:    "Apple Health"
        case .connector: "Connect Claude or ChatGPT"
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        switch onboarding.step {
        case .theme:
            themeStep
        case .units:
            unitsStep
        case .health:
            healthStep
        case .connector:
            connectorStep
        }
    }

    private var themeStep: some View {
        VStack(spacing: 0) {
            ThemePickerScreen(showsSettingsFooter: false)
            continueBar("Continue") {
                onboarding.step = .units
            }
        }
    }

    private var unitsStep: some View {
        VStack(spacing: 0) {
            WeightUnitPickerScreen(current: weightUnit, popsOnSelect: false) { picked in
                AppSettings.current(in: context).setWeightUnit(picked)
            }
            continueBar("Continue") {
                onboarding.step = .health
            }
        }
    }

    private var healthStep: some View {
        let status = health?.workoutSharingStatus ?? .unavailable
        return VStack(alignment: .leading, spacing: Spacing.comfortable) {
            Text("Workouts you finish can count in Apple Fitness. You can change this later in Settings.")
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Spacing.screenMargin)

            if status == .notDetermined {
                Button("Allow Apple Health") {
                    Task { try? await health?.requestWorkoutAuthorization() }
                }
                .buttonStyle(.tintedAccent)
                .padding(.horizontal, Spacing.screenMargin)
            } else if status == .authorized {
                Toggle("Add finished workouts to Apple Health", isOn: Binding(
                    get: { settings.first?.writeWorkoutsToHealth ?? true },
                    set: { AppSettings.current(in: context).setWriteWorkoutsToHealth($0) }
                ))
                .tint(Theme.accent)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Spacing.screenMargin)
            } else if status == .denied {
                Text("Turned off in Apple’s Health app. You can allow it later under Settings.")
                    .font(Typography.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Spacing.screenMargin)
            } else {
                Text("Apple Health is not available on this device.")
                    .font(Typography.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Spacing.screenMargin)
            }

            Spacer()
            HStack(spacing: Spacing.comfortable) {
                Button("Skip") { onboarding.step = .connector }
                    .buttonStyle(.tintedDestructive)
                Button("Continue") { onboarding.step = .connector }
                    .buttonStyle(.tintedAccent)
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.spacious)
        }
    }

    private var connectorStep: some View {
        VStack(alignment: .leading, spacing: Spacing.comfortable) {
            Text("You log sets on this phone. Claude or ChatGPT can plan and read your history — they cannot log a workout from chat.")
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)

            Text("Add a custom connector and paste:")
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)

            Text("https://mcp.mcpstrength.com")
                .font(Typography.body)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)

            Button(copiedConnector ? "Copied" : "Copy URL") {
                UIPasteboard.general.string = "https://mcp.mcpstrength.com"
                copiedConnector = true
            }
            .buttonStyle(.tintedAccent)

            Button("Open how-to") {
                if let url = URL(string: "https://mcpstrength.com/connect") {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.tintedAccent)

            Spacer()
            HStack(spacing: Spacing.comfortable) {
                Button("Skip") { onboarding.complete() }
                    .buttonStyle(.tintedDestructive)
                Button("Done") { onboarding.complete() }
                    .buttonStyle(.tintedAccent)
            }
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.bottom, Spacing.spacious)
    }

    private func continueBar(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.tintedAccent)
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.comfortable)
            .background(Theme.surface)
    }
}
