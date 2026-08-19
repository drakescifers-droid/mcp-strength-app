//
//  ExercisesScreen.swift
//  MCPStrength
//

import SwiftUI
import SwiftData

// MARK: - ExercisesScreen

/// The exercise library screen: a searchable, filterable list of every exercise in the store.
///
/// Search and filter are deliberately separate:
/// - The two pills are HARD filters — the user asked to see only that body part or category, so
///   they narrow the candidate list.
/// - The search field RANKS the (already filtered) candidates via `ExerciseMatcher.rank`. The
///   matcher's `bodyPartHint` is a ranking signal for programmatic callers and is NOT used here,
///   because the filter already happened. With empty search text the filtered list is shown
///   sorted alphabetically by name.
struct ExercisesScreen: View {
    @Query(filter: #Predicate<Exercise> { $0.deletedAt == nil },
           sort: \Exercise.name)
    private var exercises: [Exercise]

    @State private var searchText = ""
    @State private var bodyPartFilter: BodyPart?
    @State private var categoryFilter: ExerciseCategory?

    @Environment(\.dismiss) private var dismiss

    /// When non-nil the screen acts as an exercise picker: rows are tappable and
    /// invoke this callback instead of being inert. "Add Exercises" in the
    /// active-workout flow uses this; the library screen on its own leaves it
    /// nil. This is the only addition needed to reuse the screen as a picker —
    /// no second exercise list is built.
    var onSelect: ((Exercise) -> Void)? = nil

    private var pickerMode: Bool { onSelect != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.bottom, Spacing.compact)

                filterRow
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.bottom, Spacing.compact)

                hairline

                exerciseList
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface)
            .navigationTitle(pickerMode ? "Add Exercises" : "Exercises")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if pickerMode {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    // MARK: - Derived list

    /// Filters the full library by the active pills, then ranks by search text when present.
    /// With empty search text the filtered candidates are returned in alphabetical order (the
    /// `@Query` already sorts by name, and `filter` preserves order).
    private var visibleExercises: [Exercise] {
        var candidates = exercises
        if let bodyPartFilter {
            candidates = candidates.filter { $0.bodyPart == bodyPartFilter }
        }
        if let categoryFilter {
            candidates = candidates.filter { $0.category == categoryFilter }
        }

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return candidates }
        return ExerciseMatcher.rank(query: trimmed, bodyPartHint: nil, in: candidates)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: Spacing.compact) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
            TextField("Search", text: $searchText)
                .font(Typography.body)
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, Spacing.comfortable)
        .padding(.vertical, Spacing.compact)
        .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.button))
    }

    // MARK: - Filter pills

    private var filterRow: some View {
        HStack(spacing: Spacing.compact) {
            bodyPartPill
            categoryPill
            Spacer()
        }
    }

    private var bodyPartPill: some View {
        Menu {
            Button("Any Body Part") { bodyPartFilter = nil }
            ForEach(BodyPart.allCases, id: \.self) { part in
                Button(part.displayName) { bodyPartFilter = part }
            }
        } label: {
            pillLabel(
                bodyPartFilter?.displayName ?? "Any Body Part",
                isSelected: bodyPartFilter != nil
            )
        }
    }

    private var categoryPill: some View {
        Menu {
            Button("Any Category") { categoryFilter = nil }
            ForEach(ExerciseCategory.allCases, id: \.self) { category in
                Button(category.displayName) { categoryFilter = category }
            }
        } label: {
            pillLabel(
                categoryFilter?.displayName ?? "Any Category",
                isSelected: categoryFilter != nil
            )
        }
    }

    private func pillLabel(_ text: String, isSelected: Bool) -> some View {
        Text(text)
            .font(Typography.secondary)
            .foregroundStyle(isSelected ? Theme.accent : Theme.textPrimary)
            .padding(.horizontal, Spacing.comfortable)
            .padding(.vertical, Spacing.compact)
            .background(
                isSelected ? Theme.accentFill : Theme.fieldFill,
                in: .rect(cornerRadius: Radius.button)
            )
    }

    // MARK: - List

    private var exerciseList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(visibleExercises.enumerated()), id: \.element.id) { index, exercise in
                    if pickerMode {
                        Button {
                            onSelect?(exercise)
                        } label: {
                            ExerciseRow(exercise: exercise)
                        }
                        .buttonStyle(.plain)
                    } else {
                        ExerciseRow(exercise: exercise)
                    }
                    if index < visibleExercises.count - 1 {
                        rowDivider
                    }
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.compact)
        }
    }

    /// A hairline divider for the top of the list (between the filters and the rows).
    private var hairline: some View {
        Rectangle()
            .fill(Theme.fieldFill)
            .frame(height: 1)
    }

    /// A row separator inset to align with the exercise name text, not the avatar. The avatar is
    /// `avatarSize` wide plus `Spacing.comfortable` to the text, so the divider starts there.
    private var rowDivider: some View {
        Rectangle()
            .fill(Theme.fieldFill)
            .frame(height: 1)
            .padding(.leading, ExerciseRow.avatarSize + Spacing.comfortable)
    }
}

// MARK: - ExerciseRow

/// A single exercise row: a leading letter avatar, then the name (semibold) and body part
/// (secondary) stacked beneath it. The trailing side is intentionally empty — there is no workout
/// history yet, so a "last performed" column is out of scope.
private struct ExerciseRow: View {
    static let avatarSize: CGFloat = 44

    let exercise: Exercise

    var body: some View {
        HStack(spacing: Spacing.comfortable) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(exercise.bodyPart.displayName)
                    .font(Typography.secondary)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.compact)
    }

    private var avatar: some View {
        // First letter of the name, large and light, on the subtle fieldFill background. The
        // Typography scale has no large-light role, so a system font is used directly here.
        Text(String(exercise.name.prefix(1)).uppercased())
            .font(.system(size: 24, weight: .light))
            .foregroundStyle(Theme.textSecondary)
            .frame(width: Self.avatarSize, height: Self.avatarSize)
            .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.chip))
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Exercise.self, configurations: config)
    let context = container.mainContext

    let samples: [Exercise] = [
        Exercise(name: "Back Squat", aliases: ["Squat"], bodyPart: .legs, category: .barbell),
        Exercise(name: "Bench Press", aliases: ["Flat Bench"], bodyPart: .chest, category: .barbell),
        Exercise(name: "Deadlift", aliases: ["Conventional Deadlift"], bodyPart: .back, category: .barbell),
        Exercise(name: "Overhead Press", aliases: ["OHP", "Military Press"], bodyPart: .shoulders, category: .barbell),
        Exercise(name: "Dumbbell Lateral Raise", aliases: ["Lateral Raise"], bodyPart: .shoulders, category: .dumbbell),
        Exercise(name: "Pull Up", bodyPart: .back, category: .weightedBodyweight),
        Exercise(name: "Leg Press", bodyPart: .legs, category: .machineOther),
        Exercise(name: "Cable Fly", aliases: ["Pec Fly"], bodyPart: .chest, category: .machineOther),
        Exercise(name: "Plank", bodyPart: .core, category: .repsOnly),
        Exercise(name: "Rowing", aliases: ["Erg"], bodyPart: .cardio, category: .cardio),
    ]
    for exercise in samples {
        context.insert(exercise)
    }

    return ExercisesScreen()
        .modelContainer(container)
}
