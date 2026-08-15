//
//  MCPStrengthApp.swift
//  MCPStrength
//
//  Created by Drake Scifers on 8/14/26.
//

import SwiftUI
import SwiftData

@main
struct MCPStrengthApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
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
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])

            // Seed the exercise library on every launch. The import is idempotent and matches
            // on the UUIDs baked into exercise-seed.json, so re-running it is a no-op for rows
            // that already exist, adds any newly shipped ones, and never touches exercises the
            // user created (isCustom == true). See docs/01-data-model.md § The seeded library.
            //
            // A failure here is not fatal: the app still works with an empty or partial library,
            // and the next launch retries. Crashing a user's app because a bundled JSON file
            // could not be read would be a much worse outcome than a short exercise list.
            do {
                try ExerciseSeedImporter.loadBundledSeed(into: ModelContext(container))
            } catch {
                assertionFailure("Seed import failed: \(error)")
            }

            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                // The design tokens are a dark-only palette, sampled from the dark reference
                // app (see Design/Theme.swift). System-provided chrome — navigation titles,
                // pickers, keyboards — takes its colours from the environment colour scheme,
                // NOT from our tokens, so without this the title renders black on #293136.
                // Remove this only when a light palette actually exists.
                .preferredColorScheme(.dark)
        }
        .modelContainer(sharedModelContainer)
    }
}
