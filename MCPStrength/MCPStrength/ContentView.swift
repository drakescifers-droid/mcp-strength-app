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

    /// Optional because `MCPStrengthApp` creates the engine in a `.task`, so
    /// it is absent on the first frame (see `optionalEnvironment` there).
    @Environment(SyncEngine.self) private var engine: SyncEngine?
    @Environment(HealthStore.self) private var health: HealthStore?
    @Environment(AuthController.self) private var auth

    // Start Workout is the middle tab (index 2 of 5) and the app's home.
    // In UI preview mode a launch argument can open straight onto any tab, so
    // screenshotting a screen does not depend on driving taps by coordinate.
    @State private var selectedTab = UIPreviewMode.initialTab ?? 2

    /// The settings row, so the user's weight unit can be published into the
    /// environment for every screen below. See `Views/DisplayUnit.swift` for
    /// why this is read HERE and not on each screen that shows a weight.
    ///
    /// Sorted and taken first for the same reason `AppSettings.current(in:)`
    /// sorts: "the oldest live row wins" has to be the answer everywhere, or
    /// two readers can disagree about which row is authoritative. A query
    /// rather than that call because a view must not insert a row while
    /// rendering; `MCPStrengthApp` guarantees one exists before this runs.
    /// Who schedules the rest alert. A do-nothing implementation under test or
    /// in UI preview mode: a test host would block on an authorization prompt
    /// nobody can tap, and a preview launch is for looking at layout, not for
    /// buzzing the device. Same reasoning as the sync guard in
    /// `AutomatedLaunch`.
    private var restNotifications: any RestNotificationScheduling {
        if AutomatedLaunch.isRunningTests || UIPreviewMode.isEnabled {
            return NoRestNotifications()
        }
        return RestNotifications()
    }

    @Query(
        filter: #Predicate<AppSettings> { $0.deletedAt == nil },
        sort: \AppSettings.createdAt,
        order: .forward
    )
    private var settings: [AppSettings]

    var body: some View {
        ZStack {
            tabView

            if let activeWorkout {
                ActiveWorkoutScreen(
                    restNotifications: restNotifications,
                    workout: activeWorkout,
                    onFinish: {
                        // Capture BEFORE clearing. `activeWorkout` here is
                        // the unwrapped binding from the `if let` above, and
                        // `self.activeWorkout` goes nil on the next line — the
                        // Health write needs the workout that was just finished.
                        let finished = activeWorkout
                        self.activeWorkout = nil
                        syncAfterFinish()
                        writeFinishedWorkoutToHealth(finished)
                    },
                    onCancel: { self.activeWorkout = nil }
                )
                .transition(.opacity)
            }
        }
        .animation(.default, value: activeWorkout != nil)
        // Both branches of the ZStack, so the overlaid workout screen reads the
        // same unit as the tabs underneath it. The fallback is unreachable in
        // practice — `MCPStrengthApp` creates the row before any view exists —
        // and matches both `AppSettings.weightUnit` and the environment key's
        // own default, because three places disagreeing about "what does a bare
        // number mean" is the failure this whole change is removing.
        .environment(\.weightUnit, settings.first?.weightUnit ?? .lbs)
    }

    /// The third sync trigger, alongside launch and foreground in
    /// `MCPStrengthApp`. It belongs here rather than inside
    /// `ActiveWorkoutScreen` for the same reason the mutations do: the screen
    /// reports that it finished and this view decides what that means, so the
    /// logging screen stays ignorant of whether a backend exists at all.
    ///
    /// Finishing is the ONLY moment a workout becomes eligible to push —
    /// `PushFilter` blocks an unfinished one and everything under it — so
    /// without this trigger a session just logged would sit on the phone until
    /// the app was next backgrounded and reopened. That is precisely the window
    /// docs/06-sync.md exists to close: the app has the only copy and says
    /// nothing about it.
    ///
    /// Cancel deliberately does NOT sync. A cancelled workout is hard-deleted
    /// and never left the device, so there is nothing to send.
    private func syncAfterFinish() {
        // Same two reasons as the launch trigger in `MCPStrengthApp`, in the
        // same order. See AutomatedLaunch for why a test run must not sync.
        guard !AutomatedLaunch.isRunningTests else { return }
        guard !UIPreviewMode.isEnabled else { return }
        guard let engine else { return }
        guard case .signedIn(let userID, _) = auth.state else { return }
        Task { await engine.run(as: userID) }
    }

    /// Add the finished workout to Apple Health.
    ///
    /// Alongside the sync trigger rather than inside it, because they answer to
    /// different things: sync needs an account, Health needs a per-device
    /// permission, and either can be unavailable while the other works. Folding
    /// them together would make a signed-out user's Health write fail for a
    /// reason that has nothing to do with Health.
    ///
    /// Same two guards at the top for the same reasons: a test run must not
    /// reach outside the process (AutomatedLaunch — it is what put rows in the
    /// live project), and preview mode is fixtures rather than training.
    ///
    /// SILENT ON PURPOSE when there is no permission. `writeWorkout` returns
    /// false rather than throwing, and nothing is surfaced: a person who has
    /// not granted Health access has not asked for this, and interrupting the
    /// end of a workout to say so would be nagging for a feature they did not
    /// turn on. The Settings screen is where the state is legible.
    private func writeFinishedWorkoutToHealth(_ workout: Workout) {
        guard !AutomatedLaunch.isRunningTests else { return }
        guard !UIPreviewMode.isEnabled else { return }
        guard let health else { return }
        // The rate comes from the SAME query the weight unit is read from, and
        // falls back the same way: `MCPStrengthApp` makes the row before any
        // view exists, and `.medium` matches both the model's declaration
        // default and the server's column default. Three places disagreeing
        // about what a bare setting means is the failure canonical storage
        // exists to remove.
        let rate = settings.first?.workoutCalorieRate ?? .medium
        guard case .success(let plan) = HealthWorkoutRule.plan(for: workout, rate: rate)
        else { return }
        Task { try? await health.writeWorkout(plan) }
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
                // "Start", not "Start Workout", and this is a DELIBERATE
                // divergence from the reference — which does say "Start
                // Workout" (`Home screen/Home Screen.PNG`).
                //
                // The reference's tab bar is flat, full-width, and marks the
                // selected tab with tint alone. This platform's bar floats and
                // draws a capsule sized to the selected LABEL, so the longest
                // label in the middle slot pushes that capsule out into its
                // neighbours and "History" and "Exercises" end up pressed
                // against it. Same string, different bar, worse result.
                //
                // Shortening restores what the reference actually shows — five
                // evenly spaced tabs — rather than the string it uses to show
                // it. The screen's own title is still "Start Workout", so the
                // full name is never lost; it is one line away from reverting
                // if a future OS stops drawing the capsule.
                Label("Start", systemImage: "plus")
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
        // Non-optional in the view, so a preview that finishes a workout would
        // trap without it. The SyncEngine is deliberately NOT injected: it is
        // optional by design, and a preview has no session for it to sync with.
        .environment(AuthController())
}
