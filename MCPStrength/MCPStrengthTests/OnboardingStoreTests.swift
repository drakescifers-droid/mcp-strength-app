//
//  OnboardingStoreTests.swift
//  MCPStrengthTests
//

import Testing
import Foundation
@testable import MCPStrength

struct OnboardingStoreTests {

    @Test func freshStoreStartsOnThemeAndIncomplete() {
        let defaults = UserDefaults(suiteName: "onboarding-fresh-\(UUID().uuidString)")!
        let store = OnboardingStore(defaults: defaults)
        #expect(store.isComplete == false)
        #expect(store.step == .theme)
    }

    @Test func completePersists() {
        let name = "onboarding-complete-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let store = OnboardingStore(defaults: defaults)
        store.complete()
        #expect(store.isComplete)

        let again = OnboardingStore(defaults: UserDefaults(suiteName: name)!)
        #expect(again.isComplete)
    }

    @Test func resetReturnsToTheme() {
        let defaults = UserDefaults(suiteName: "onboarding-reset-\(UUID().uuidString)")!
        let store = OnboardingStore(defaults: defaults)
        store.step = .connector
        store.complete()
        store.reset()
        #expect(store.isComplete == false)
        #expect(store.step == .theme)
    }

    @Test func stepSurvivesRelaunch() {
        let name = "onboarding-step-\(UUID().uuidString)"
        let first = OnboardingStore(defaults: UserDefaults(suiteName: name)!)
        first.step = .health
        let second = OnboardingStore(defaults: UserDefaults(suiteName: name)!)
        #expect(second.step == .health)
        #expect(second.isComplete == false)
    }
}
