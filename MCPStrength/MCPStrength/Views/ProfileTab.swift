//
//  ProfileTab.swift
//  MCPStrength
//
//  A small, honest profile: a total completed-workout count, a Swift Charts bar
//  chart of workouts per week over the last 8 weeks, and the account card.
//
//  There is still no avatar and no settings screen. The account card is here
//  because sign-out has to live SOMEWHERE — an app you can sign into and not
//  out of is a bug, and this is the only tab that is about you rather than
//  about training.
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

    @Query(filter: #Predicate<Workout> { $0.deletedAt == nil },
           sort: [SortDescriptor(\Workout.startedAt, order: .reverse)])
    private var allWorkouts: [Workout]

    @State private var confirmingSignOut = false

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
                Text("Your workouts stay on this phone.")
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

            Button("Sign Out") { confirmingSignOut = true }
                .buttonStyle(.tintedDestructive)
                .disabled(auth.isBusy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.comfortable)
        .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.card))
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
