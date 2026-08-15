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
        let workout = Workout(name: workoutName(for: Date()), startedAt: Date())
        context.insert(workout)
        activeWorkout = workout
    }

    /// "Afternoon Workout" style name from the time of day.
    private func workoutName(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let part: String
        switch hour {
        case 5..<12:  part = "Morning"
        case 12..<17: part = "Afternoon"
        case 17..<21: part = "Evening"
        default:      part = "Night"
        }
        return "\(part) Workout"
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Exercise.self, inMemory: true)
}
