//
//  UIPreviewFixtures.swift
//  MCPStrength
//
//  Demo content for `-uiPreview 1 -uiPreviewFixtures 1`.
//
//  An empty screen tells you almost nothing about whether a layout works. The
//  bugs this project has actually shipped were about CONTENT: misaligned
//  columns that only appear when some sets have values and others do not, a
//  note long enough to push the sets off the card, a warm-up badge next to a
//  drop set. So the fixture is deliberately awkward rather than tidy — it
//  contains the cases a happy-path demo would miss.
//
//  ## Safety
//
//  The whole file is `#if DEBUG`, so it does not exist in a Release build, and
//  it only runs when BOTH launch arguments are present. It is idempotent: it
//  checks for its own marker and does nothing on a second launch, so repeated
//  previews do not stack up duplicate workouts.
//

import Foundation
import SwiftData

#if DEBUG

enum UIPreviewFixtures {

    /// Recognisable enough that a human scrolling history knows what they are
    /// looking at, and specific enough to search for when clearing up.
    private static let marker = "Preview Session"

    static func install(in container: ModelContainer) {
        let context = ModelContext(container)

        // Idempotent. Relaunching to look at a layout must not append a second
        // copy every time.
        let existing = try? context.fetch(
            FetchDescriptor<Workout>(predicate: #Predicate { $0.name == marker })
        )
        guard (existing ?? []).isEmpty else { return }

        guard let library = try? context.fetch(FetchDescriptor<Exercise>()),
              !library.isEmpty else { return }

        // EXACT, full-name match, and the exactness is the point.
        //
        // This was `localizedCaseInsensitiveContains`, over a fetch with no
        // sort descriptor — so it returned whichever matching row SwiftData
        // happened to hand back first. "Bench Press" matched **Incline Bench
        // Press (Dumbbell)** and "Pull Up" matched **Assisted Pull Up**, which
        // meant the fixture hung 95 lb and 135 lb warm-ups and 185 lb working
        // sets off a DUMBBELL incline press. Nothing failed; the screens just
        // quietly showed nonsense, in the one tool this project uses to judge
        // whether a screen is right (docs/04-status.md).
        //
        // A miss now trips an assertion rather than skipping the block. The
        // silent `if let` meant renaming a seeded exercise would thin the
        // fixtures out instead of saying so, and an emptier preview is exactly
        // the thing nobody notices.
        // Fixture weights are written as POUNDS and converted on the way in,
        // because storage is canonical kilograms and a fixture is not exempt
        // from that. Writing `84` would make the file unreadable — the numbers
        // are chosen to be recognisable barbell loads (a 185 lb bench, a 45 lb
        // bar) and that is what makes a screenshot judgeable at a glance.
        //
        // These do NOT go through `WeightUnitMigration`: it runs at container
        // creation and has already marked the store converted by the time this
        // installs. Anything inserted here has to arrive in kilograms itself.
        func kg(_ pounds: Double) -> Double {
            WeightUnits.kilograms(from: pounds, in: .lbs)
        }

        func exercise(_ name: String) -> Exercise? {
            let match = library.first {
                $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }
            assert(match != nil, "UIPreviewFixtures: no seeded exercise named \(name)")
            return match
        }

        let workout = Workout(
            name: marker,
            startedAt: .now.addingTimeInterval(-3_900),
            completedAt: .now.addingTimeInterval(-600),
            durationSeconds: 3_300,
            // Long on purpose: this is the case that proves the 200-character
            // limit and the More affordance actually do something.
            note: "Deload week. Keep everything at RPE 7 and stop one short of "
                + "failure on every working set — the point is to recover, not "
                + "to test anything. If the bar speed drops, end the set.",
            summary: "Slept about five hours and it showed. Everything felt "
                + "heavier than the numbers suggest, and the gym was packed so "
                + "the rest times ran long.",
            template: nil
        )
        context.insert(workout)

        // A loaded barbell movement: warm-ups, working sets, a drop set, RPE,
        // and one skipped set — every badge and both text colours in one block.
        if let bench = exercise("Bench Press (Barbell)") {
            let block = WorkoutExercise(
                order: 0,
                note: "Elbows tucked, pause on the chest.",
                stickyNote: "Left shoulder — stop if it pinches.",
                workout: workout,
                exercise: bench
            )
            context.insert(block)
            let sets: [(SetType, Double, Int, Double?, Bool)] = [
                (.warmup, 95, 10, nil, true),
                (.warmup, 135, 5, nil, true),
                (.normal, 185, 8, 7, true),
                (.normal, 185, 7, 7.5, true),
                (.dropSet, 155, 6, 8, true),
                (.normal, 185, 6, nil, false),
            ]
            for (i, s) in sets.enumerated() {
                context.insert(WorkoutSet(
                    order: i, setType: s.0, weight: kg(s.1), reps: s.2, rpe: s.3,
                    restSeconds: 120, isCompleted: s.4,
                    completedAt: s.4 ? .now : nil, workoutExercise: block
                ))
            }
        }

        // Bodyweight: the category that gets NO 1RM estimate, so the column
        // heading must be absent rather than sitting over a blank column.
        if let pull = exercise("Pull Up") {
            let block = WorkoutExercise(order: 1, workout: workout, exercise: pull)
            context.insert(block)
            for (i, reps) in [8, 7, 5].enumerated() {
                context.insert(WorkoutSet(
                    order: i, reps: reps, restSeconds: 90,
                    isCompleted: true, workoutExercise: block
                ))
            }
        }

        // High reps: above the Brzycki/Epley crossover, so the estimate comes
        // from the other formula. Worth having one visible.
        if let curl = exercise("Bicep Curl (Dumbbell)") {
            let block = WorkoutExercise(
                order: 2,
                stickyNote: "Slow negatives.",
                workout: workout,
                exercise: curl
            )
            context.insert(block)
            for (i, reps) in [15, 13, 12].enumerated() {
                context.insert(WorkoutSet(
                    order: i, weight: kg(35), reps: reps, restSeconds: 60,
                    isCompleted: true, workoutExercise: block
                ))
            }
        }

        workout.totalVolume = WorkoutStats.totalVolume(for: workout)

        installTemplates(in: context, library: library, exercise: exercise)

        try? context.save()
    }

    /// Two folders with templates in them, so the Start Workout tab has
    /// something to look at.
    ///
    /// It had NOTHING before — the fixtures built a workout and stopped, so the
    /// templates tab was empty in the one mode this project uses to judge
    /// screens, and the only way to see a folder was to make one by hand every
    /// time. Two folders rather than one on purpose: dragging a template
    /// BETWEEN folders is the interaction here, and it takes two to have a
    /// between.
    ///
    /// Guarded on its own marker, not the workout's. The workout fixture and
    /// this one were added in different sessions, so a store that already has
    /// the first must still be able to receive the second.
    private static func installTemplates(
        in context: ModelContext,
        library: [Exercise],
        exercise: (String) -> Exercise?
    ) {
        let existing = try? context.fetch(
            FetchDescriptor<TemplateFolder>(predicate: #Predicate { $0.name == "Preview Push" })
        )
        guard (existing ?? []).isEmpty else { return }

        let push = TemplateFolder(name: "Preview Push", order: 0)
        let pull = TemplateFolder(name: "Preview Pull", order: 1)
        context.insert(push)
        context.insert(pull)

        func template(_ name: String, in folder: TemplateFolder, order: Int, exercises: [String]) {
            let template = Template(name: name, order: order, folder: folder)
            context.insert(template)
            for (index, exerciseName) in exercises.enumerated() {
                guard let match = exercise(exerciseName) else { continue }
                let block = TemplateExercise(
                    order: index,
                    defaultRestSeconds: 90,
                    template: template,
                    exercise: match
                )
                context.insert(block)
                for setIndex in 0..<3 {
                    context.insert(TemplateSet(
                        order: setIndex,
                        reps: 8,
                        restSeconds: 90,
                        templateExercise: block
                    ))
                }
            }
        }

        // Two in the first folder and one in the second, so a drag between
        // them changes both counts visibly and cannot be mistaken for a
        // reorder within one.
        template("Preview Bench Day", in: push, order: 0, exercises: ["Bench Press (Barbell)"])
        template("Preview Shoulder Day", in: push, order: 1, exercises: ["Bicep Curl (Dumbbell)"])
        template("Preview Back Day", in: pull, order: 0, exercises: ["Pull Up"])
    }
}

#endif
