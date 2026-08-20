//
//  OnboardingStore.swift
//  MCPStrength
//
//  First-run setup after sign-in. Per-device: theme and Health permission
//  are per-device, so this is UserDefaults, not AppSettings.
//
//  Observable so finishing setup rebuilds AuthGate. A static flag would write
//  and leave the user stuck on the last onboarding page.
//

import Foundation
import Observation

enum OnboardingStep: String, CaseIterable, Equatable {
    case theme
    case units
    case health
    case connector
}

@Observable
final class OnboardingStore {

    static let completedKey = "onboardingCompleted"
    static let stepKey = "onboardingStep"

    private let defaults: UserDefaults

    var isComplete: Bool {
        didSet { defaults.set(isComplete, forKey: Self.completedKey) }
    }

    var step: OnboardingStep {
        didSet { defaults.set(step.rawValue, forKey: Self.stepKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isComplete = defaults.bool(forKey: Self.completedKey)
        let raw = defaults.string(forKey: Self.stepKey) ?? ""
        self.step = OnboardingStep(rawValue: raw) ?? .theme
    }

    func complete() {
        isComplete = true
    }

    /// A new account on this phone should see setup again.
    func reset() {
        isComplete = false
        step = .theme
    }
}
