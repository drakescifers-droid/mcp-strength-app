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
// The app root. Minimal: a "Start Workout" entry point alongside a link to the
// existing exercise library. Starting a workout swaps the root for the
// ActiveWorkoutScreen; finishing or cancelling swaps it back. The workout
// object lives in the store either way (Finish keeps it, Cancel deletes it).

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @State private var activeWorkout: Workout?

    var body: some View {
        Group {
            if let activeWorkout {
                ActiveWorkoutScreen(
                    workout: activeWorkout,
                    onFinish: { self.activeWorkout = nil },
                    onCancel: { self.activeWorkout = nil }
                )
                .transition(.opacity)
            } else {
                homeScreen
            }
        }
        .animation(.default, value: activeWorkout != nil)
    }

    // MARK: - Home

    private var homeScreen: some View {
        NavigationStack {
            VStack(spacing: Spacing.comfortable) {
                Spacer()

                Button("Start Workout") { startWorkout() }
                    .buttonStyle(.primaryAction)
                    .padding(.horizontal, Spacing.screenMargin)

                NavigationLink {
                    TemplatesScreen(onStart: { template in startWorkout(from: template) })
                } label: {
                    Text("Templates")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tintedAccent)
                .padding(.horizontal, Spacing.screenMargin)

                NavigationLink {
                    ExercisesScreen()
                } label: {
                    Text("Exercise Library")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tintedAccent)
                .padding(.horizontal, Spacing.screenMargin)

                Spacer()
            }
            .navigationTitle("MCPStrength")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface)
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
        ], inMemory: true)
}
