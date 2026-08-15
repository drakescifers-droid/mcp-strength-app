//
//  ProfileTab.swift
//  MCPStrength
//
//  A small, honest profile. This app has no accounts, no auth and no photos,
//  so there is no avatar, no username and no settings screen — just a total
//  completed-workout count and a Swift Charts bar chart of workouts per week
//  over the last 8 weeks.
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
    @Query(sort: [SortDescriptor(\Workout.startedAt, order: .reverse)])
    private var allWorkouts: [Workout]

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
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.spacious)
            }
            .background(Theme.surface)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
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
