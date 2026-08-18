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
            AppSettings.self,
            StoreMigrations.self,
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

            // Canonical units. Two jobs, one context, in this order:
            //
            //   1. Make sure the settings row exists, because `ContentView`
            //      READS it to publish the display unit and a view must not
            //      insert a row while rendering. `current(in:)` creates it on
            //      first ask and is a no-op afterwards.
            //   2. Convert any pounds already in this store to kilograms,
            //      exactly once. See WeightUnitMigration for why running twice
            //      is the thing to be afraid of.
            //
            // BEFORE ANY VIEW EXISTS, deliberately. The screens now divide a
            // stored weight by 0.45359237 to display it, so a frame rendered
            // between launch and conversion would show every lift at 2.2× —
            // briefly, plausibly, and long enough to be typed over.
            //
            // A failure here is fatal in DEBUG and survivable in release, which
            // is the opposite call from the seed importers above and the
            // opposite for a reason: a partial library is a short exercise
            // list, whereas a store this could not convert is a store whose
            // numbers do not mean what the screens will claim. It is left
            // UNCONVERTED rather than half-converted (one save, see the file),
            // so the next launch retries — which is the best available outcome
            // and still not a good one.
            do {
                let context = ModelContext(container)
                _ = AppSettings.current(in: context)
                try WeightUnitMigration.run(in: context)
                // The migration commits its own work in one save and returns
                // early once the store is already converted — which is every
                // launch after the first. This save is what persists a
                // newly-created settings row on that path, and a no-op on the
                // other.
                try context.save()
            } catch {
                assertionFailure("Weight unit migration failed: \(error)")
            }

            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    /// Owns "who is signed in". Created here rather than inside a view so it
    /// survives every view rebuild — a controller recreated by SwiftUI would
    /// restart its session observation and drop back to `.loading` mid-use.
    @State private var auth = AuthController()

    /// The backup state the Profile tab reads. Owned here for the same reason
    /// as `auth`: it holds a per-user cursor that must survive view rebuilds.
    @State private var sync = SyncStatus()

    /// The run loop. Optional only because it needs the container's main
    /// context, which a property initializer cannot see; created once in
    /// `.task` below. A third trigger — sync right after Finish — belongs
    /// at the finish site in ActiveWorkoutScreen, which another worker
    /// owns this round.
    @State private var engine: SyncEngine?

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // AuthGate, not ContentView: the app proper is unreachable until a
            // session exists. Every row the backend accepts must be stamped
            // with an owner, so there is nothing to sync before the app knows
            // who you are. THE LOCAL STORE IS UNAFFECTED — SwiftData and the
            // seed importers above run regardless of sign-in state, so the
            // library is ready the moment the gate opens.
            AuthGate()
                .environment(auth)
                .environment(sync)
                .optionalEnvironment(engine)
                // The design tokens are a dark-only palette, sampled from the dark reference
                // app (see Design/Theme.swift). System-provided chrome — navigation titles,
                // pickers, keyboards — takes its colours from the environment colour scheme,
                // NOT from our tokens, so without this the title renders black on #293136.
                // Remove this only when a light palette actually exists.
                .preferredColorScheme(.dark)
                .task {
                    // Idempotent — guarded inside, so the re-run SwiftUI may
                    // perform on reattach cannot start a second observer.
                    auth.start()
                }
                .task {
                    // Preview launches have no session, so nothing would ever
                    // point the sync status at a user. Do it here so the
                    // Profile tab's backup card renders like a signed-in one.
                    if UIPreviewMode.isEnabled {
                        sync.adopt(userID: UIPreviewMode.previewUserID)
                        #if DEBUG
                        if UIPreviewMode.wantsFixtures {
                            UIPreviewFixtures.install(in: sharedModelContainer)
                        }
                        #endif
                    }
                }
                .task {
                    if engine == nil {
                        engine = SyncEngine(
                            context: sharedModelContainer.mainContext,
                            transport: SupabaseSyncClient(),
                            status: sync
                        )
                    }
                    // Launch trigger. Preview has no session; RLS would
                    // reject everything, so we do not run there.
                    triggerSyncIfSignedIn()
                }
                .onChange(of: auth.state) { _, state in
                    // The sync cursor is per-account: pointing it at the signed
                    // -in user is what stops one person resuming from another
                    // person's position and skipping everything before it.
                    switch state {
                    case .signedIn(let userID, _):
                        sync.adopt(userID: userID)
                        triggerSyncIfSignedIn()
                    default:
                        sync.clearSession()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    // Foreground trigger. `.onChange` does not fire for the
                    // initial `.active`, which is why launch has its own .task.
                    if phase == .active {
                        triggerSyncIfSignedIn()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }

    /// Pull on launch and on foreground, only when there is a session.
    /// The engine itself no-ops if a run is already in flight.
    private func triggerSyncIfSignedIn() {
        guard !UIPreviewMode.isEnabled else { return }
        guard let engine else { return }
        guard case .signedIn(let userID, _) = auth.state else { return }
        Task { await engine.run(as: userID) }
    }
}

private extension View {
    /// `.environment` does not take an optional; a missing engine on the
    /// first frame (before `.task` creates it) must not hide AuthGate.
    @ViewBuilder
    func optionalEnvironment(_ engine: SyncEngine?) -> some View {
        if let engine {
            self.environment(engine)
        } else {
            self
        }
    }
}
