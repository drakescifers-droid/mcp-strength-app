//
//  ContentView.swift
//  MCPStrength
//
//  Created by Drake Scifers on 8/14/26.
//

import SwiftUI
import SwiftData

// MARK: - ContentView
//
// The app root: a five-tab TabView. Start Workout is the middle tab and the app
// opens on it. Starting a workout (quick or from a template) overlays the
// ActiveWorkoutScreen on top of the whole shell; finishing or cancelling drops
// back to the tab the user was on. Each tab owns its own NavigationStack so
// drilling into a workout or a measurement type does not disturb the others.
//
// Tab order: Profile | History | Start Workout | Exercises | Measure.

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @State private var activeWorkout: Workout?

    // Start Workout is the middle tab (index 2 of 5) and the app's home.
    // In UI preview mode a launch argument can open straight onto any tab, so
    // screenshotting a screen does not depend on driving taps by coordinate.
    @State private var selectedTab = UIPreviewMode.initialTab ?? 2

    var body: some View {
        ZStack {
            tabView

            if let activeWorkout {
                ActiveWorkoutScreen(
                    workout: activeWorkout,
                    onFinish: { self.activeWorkout = nil },
                    onCancel: { self.activeWorkout = nil }
                )
                .transition(.opacity)
            }
        }
        .animation(.default, value: activeWorkout != nil)
    }

    // MARK: - Tab view

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            ProfileTab()
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
                .tag(0)

            // HistoryScreen sets its own navigationTitle but does not embed a
            // NavigationStack (it relied on being pushed in the old root). As a
            // tab root it needs its own stack so drilling into a workout stays
            // within this tab.
            NavigationStack {
                HistoryScreen()
            }
            .tabItem {
                Label("History", systemImage: "clock")
            }
            .tag(1)

            StartWorkoutTab(
                onStartQuick: { startWorkout() },
                onStartTemplate: { template in startWorkout(from: template) }
            )
            .tabItem {
                Label("Start Workout", systemImage: "plus")
            }
            .tag(2)

            // ExercisesScreen already embeds its own NavigationStack.
            ExercisesScreen()
                .tabItem {
                    Label("Exercises", systemImage: "dumbbell")
                }
                .tag(3)

            // MeasurementsScreen sets its own navigationTitle and pushes a
            // detail screen; as a tab root it needs its own stack.
            NavigationStack {
                MeasurementsScreen()
            }
            .tabItem {
                Label("Measure", systemImage: "ruler")
            }
            .tag(4)
        }
    }

    // MARK: - Actions

    private func startWorkout() {
        let workout = Workout(name: WorkoutNaming.quickWorkoutName(for: Date()), startedAt: Date())
        context.insert(workout)
        activeWorkout = workout
    }

    /// Start a workout from a template. The workout takes the TEMPLATE's name
    /// (copied at start, never read through the relationship), copies the
    /// template's exercises and sets, and opens the active-workout screen.
    private func startWorkout(from template: Template) {
        let workout = TemplateStarter.start(from: template, in: context)
        activeWorkout = workout
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            Exercise.self,
            TemplateFolder.self,
            Template.self,
            TemplateExercise.self,
            TemplateSet.self,
            ProgramDay.self,
            Workout.self,
            WorkoutExercise.self,
            WorkoutSet.self,
            MeasurementType.self,
            MeasurementEntry.self,
        ], inMemory: true)
}
