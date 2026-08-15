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

            // Seed the exercise and measurement-type libraries on every launch. Both
            // imports are idempotent and match on the UUIDs baked into their seed JSON,
            // so re-running them is a no-op for rows that already exist, adds any newly
            // shipped ones, and never touches user-created rows. See docs/01-data-model.md
            // § The seeded library and § Measurements.
            //
            // A failure here is not fatal: the app still works with an empty or partial
            // library, and the next launch retries. Crashing a user's app because a
            // bundled JSON file could not be read would be a much worse outcome than a
            // short exercise list or a missing measurement type.
            //
            // THE TWO SEEDS ARE INDEPENDENT, and are kept that way deliberately: each gets
            // its own do/catch so one failing cannot skip the other, and its own
            // ModelContext so a partial write from a failed import cannot ride along on the
            // other's save. They were separate call sites before they moved here together;
            // sharing a context and a catch would have quietly turned one bad JSON file
            // into two missing libraries, which is exactly what the paragraph above says
            // this code is trying not to do.
            do {
                try ExerciseSeedImporter.loadBundledSeed(into: ModelContext(container))
            } catch {
                assertionFailure("Exercise seed import failed: \(error)")
            }
            do {
                try MeasurementSeedImporter.loadBundledSeed(into: ModelContext(container))
            } catch {
                assertionFailure("Measurement seed import failed: \(error)")
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
