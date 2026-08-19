//
//  ProfileTab.swift
//  MCPStrength
//
//  A small, honest profile: a total completed-workout count, a Swift Charts bar
//  chart of workouts per week over the last 8 weeks, and the account card.
//
//  There is still no avatar. The gear in the toolbar opens `SettingsScreen`;
//  the account card is here because sign-out has to live SOMEWHERE — an app you
//  can sign into and not out of is a bug, and this is the only tab that is
//  about you rather than about training.
//
//  The weekly bucketing is the pure `WeeklyWorkoutBuckets.buckets` function in
//  Workout/, never arithmetic inside the chart builder. Weeks with zero
//  workouts still appear as columns because the bucket array always carries
//  every week in the window.
//

import SwiftUI
import SwiftData
import Charts

struct ProfileTab: View {
    @Environment(AuthController.self) private var auth
    @Environment(SyncStatus.self) private var sync
    @Environment(SyncEngine.self) private var engine: SyncEngine?

    @Query(filter: #Predicate<Workout> { $0.deletedAt == nil },
           sort: [SortDescriptor(\Workout.startedAt, order: .reverse)])
    private var allWorkouts: [Workout]

    @State private var confirmingSignOut = false
    @State private var showingSettings = false

    private var completedWorkouts: [Workout] {
        WorkoutStats.completedWorkouts(from: allWorkouts)
    }

    private var weeklyBuckets: [WeeklyBucket] {
        WeeklyWorkoutBuckets.buckets(for: allWorkouts, weeks: 8, now: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.spacious) {
                    totalCard
                    chartCard
                    accountCard
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.spacious)
            }
            .background(Theme.surface)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            // The gear sits above the title in the reference app, which on this
            // platform is the leading toolbar slot. It is the ONLY way into
            // settings — there is no second entry point to keep in step.
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            // `isPresented` rather than `item:` deliberately, and this is the
            // case AGENTS.md rule 6 does NOT cover: the rule is about a sheet
            // that needs a VALUE, where companion `@State` written from inside
            // a `Menu` action is lost. This sheet takes no arguments and the
            // flag is set from an ordinary Button. Do not "fix" it.
            .sheet(isPresented: $showingSettings) {
                SettingsScreen()
            }
            .confirmationDialog(
                "Sign out?",
                isPresented: $confirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    Task { await auth.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(sync.state.signOutMessage)
            }
        }
    }

    // MARK: - Account
    //
    // The reassurance in the dialog is load-bearing, not politeness. Signing out
    // of a local-first app does NOT delete the local store, and the natural
    // assumption is the opposite — "sign out" reads as "log out and lose it".
    // Someone who believes that will never tap it, on the device holding the
    // only copy of their training history.
    //
    // When sync lands, revisit whether signing out should offer to clear local
    // data, and be careful: that turns a reversible action into a destructive
    // one, and the copy above becomes a lie.

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: Spacing.comfortable) {
            Text("Account")
                .font(Typography.secondary.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            if case .signedIn(_, let email) = auth.state, let email {
                Text(email)
                    .font(Typography.body)
                    .foregroundStyle(Theme.textPrimary)
            }

            backupRow

            // BACK UP NOW — Drake asked for it the first time a sync failed,
            // which is exactly the moment it earns its place.
            //
            // Sync is otherwise invisible and untriggerable: it runs on launch,
            // on foreground, and after finishing a workout. When it fails there
            // is no way to retry except backgrounding the app or logging a
            // workout you did not do, and no way to tell "it failed and stayed
            // failed" from "it has not tried since". A control that answers
            // *is it still broken?* in one tap is worth more than the screen
            // real estate.
            //
            // It is also the only way a fix gets confirmed without a rebuild:
            // the run that proved the permission fix landed was started from
            // this button.
            Button {
                Task { await syncNow() }
            } label: {
                // Says what it does to the DATA, not what it does to the app.
                // "Sync" is jargon for a thing whose whole purpose is that your
                // training is not only on this phone.
                Text(sync.state == .syncing ? "Backing Up…" : "Back Up Now")
            }
            .buttonStyle(.tintedAccent)
            // Disabled while a run is in flight, matching the engine, which
            // ignores a second call anyway. Two sources of truth for "busy"
            // would drift; this reads the same state the row above shows.
            .disabled(sync.state == .syncing || engine == nil)

            Button("Sign Out") { confirmingSignOut = true }
                .buttonStyle(.tintedDestructive)
                .disabled(auth.isBusy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.comfortable)
        .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.card))
    }

    /// Run a sync on demand.
    ///
    /// Reads the user from `auth.state` rather than storing one: the engine is
    /// per-device and the account can change underneath it, and a stale id here
    /// would push one person's rows into another's account — the thing the
    /// engine's claim step exists to refuse.
    ///
    /// No completion handling and no alert. The account card above IS the
    /// result — it moves to "Backing up…", then to "Backed up" or "Backup
    /// failed" with the reason. A second channel saying the same thing would
    /// be one more place for the two to disagree.
    private func syncNow() async {
        guard let engine, case .signedIn(let userID, _) = auth.state else { return }
        await engine.run(as: userID)
    }

    // MARK: - Backup state
    //
    // The whole point of docs/02-architecture.md § Observability: a failed push
    // is indistinguishable from a successful one unless something says so. This
    // is the detailed view; a failure ALSO shows a marker on the card title, so
    // it is noticed without coming looking.
    //
    // It stopped reading "Not backed up yet" on 2026-08-18, when sync landed.
    // The failure branch now carries the SERVER'S OWN sentence where there is
    // one ("The server refused it: permission denied for table app_settings"),
    // because the first real failure said "Backup could not finish." and the
    // answer had to be dug out of the project's server logs. See
    // `SyncEngine.failureReason`.

    private var backupRow: some View {
        HStack(alignment: .top, spacing: Spacing.compact) {
            Image(systemName: syncSymbol)
                .font(Typography.secondary)
                .foregroundStyle(sync.state.demandsAttention ? Theme.destructive : Theme.textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(sync.state.title)
                    .font(Typography.secondary.weight(.semibold))
                    .foregroundStyle(sync.state.demandsAttention ? Theme.destructive : Theme.textPrimary)
                Text(sync.state.detail())
                    .font(Typography.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var syncSymbol: String {
        switch sync.state {
        case .never:     "icloud.slash"
        case .syncing:   "arrow.triangle.2.circlepath"
        case .upToDate:  "checkmark.icloud"
        case .pending:   "clock.arrow.circlepath"
        case .failed:    "exclamationmark.icloud"
        }
    }

    // MARK: - Total

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("Total Workouts")
                .font(Typography.secondary.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            Text("\(completedWorkouts.count)")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.comfortable)
        .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.card))
    }

    // MARK: - Weekly chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Spacing.comfortable) {
            Text("Workouts Per Week")
                .font(Typography.secondary.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            Chart(weeklyBuckets) { bucket in
                BarMark(
                    x: .value("Week", bucket.weekStart, unit: .weekOfYear),
                    y: .value("Workouts", bucket.count)
                )
                .foregroundStyle(Theme.accent)
                .cornerRadius(Radius.badge)
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Theme.fieldFill)
                    AxisValueLabel()
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                    AxisValueLabel(format: .dateTime.day())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(height: 180)
        }
        .padding(Spacing.comfortable)
        .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.card))
    }
}

// MARK: - Preview

#Preview {
    ProfileTab()
        .environment(AuthController())
        .environment(SyncStatus())
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
