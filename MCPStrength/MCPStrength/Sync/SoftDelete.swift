//
//  SoftDelete.swift
//  MCPStrength
//
//  Deleting, once deletes have to survive being offline.
//
//  `context.delete(...)` removes a row and with it every trace that it ever
//  existed — which is exactly wrong for a synced store. A device that was
//  offline when the delete happened has no way to learn about it, so the row
//  comes back on the next pull. Hence tombstones: the row stays, `deletedAt` is
//  set, and the delete propagates like any other edit. docs/06-sync.md.
//
//  ## Cascade is manual now, and that is the whole reason this file exists
//
//  SwiftData's `@Relationship(deleteRule:)` fires on REAL deletes. None of it
//  runs for a tombstone. So every rule the models declare has to be performed
//  by hand here, and the two kinds behave very differently:
//
//    * `.cascade` — must be walked explicitly. Tombstoning a Template without
//      tombstoning its exercises and sets leaves orphans that are live on the
//      server, belong to a deleted parent, and will be pulled back down as
//      real rows by every other device.
//
//    * `.nullify` — is performed by doing NOTHING, and that is not laziness.
//      A tombstoned template's workouts keep pointing at it; history reads its
//      own stored `name` (docs/01-data-model.md § Workouts), so nothing breaks.
//      The link goes nil when the server purges the tombstone at 90 days and
//      nulls `template_id` — a write that moves `server_updated_at` without
//      touching `updated_at`, so it reaches every device and can never outrank
//      a real user edit. Those two halves were built for each other in
//      docs/05-database.md.
//
//  Each function below states which rule it is enacting. When a delete rule on
//  a model changes, the matching function here has to change with it — they are
//  two halves of one decision, and nothing but this comment connects them.
//

import Foundation
import SwiftData

enum SoftDelete {

    // MARK: - Templates

    /// Tombstone a template and everything beneath it.
    ///
    /// CASCADE to exercises and their sets. NULLIFY to `workouts` and
    /// `programDays` — deliberately untouched. Deleting a template must never
    /// delete the workouts performed from it; that is the single most important
    /// delete rule in the app.
    static func template(_ template: Template, at date: Date = .now) {
        for exercise in template.exercises {
            templateExercise(exercise, at: date)
        }
        template.markDeleted(at: date)
    }

    /// CASCADE to sets.
    static func templateExercise(_ exercise: TemplateExercise, at date: Date = .now) {
        for set in exercise.sets {
            set.markDeleted(at: date)
        }
        exercise.markDeleted(at: date)
    }

    /// Tombstone a folder.
    ///
    /// CASCADE to its program days, NULLIFY to its templates — the templates
    /// survive and become unfiled, matching what `context.delete(folder)` did
    /// before. Their `folder` reference is left pointing at the tombstone and
    /// resolves the same way every other nullify does; see the file comment.
    static func folder(_ folder: TemplateFolder, at date: Date = .now) {
        for day in folder.programDays {
            day.markDeleted(at: date)
        }
        folder.markDeleted(at: date)
    }

    // MARK: - Workouts

    /// CASCADE to exercises and their sets.
    static func workout(_ workout: Workout, at date: Date = .now) {
        for exercise in workout.exercises {
            workoutExercise(exercise, at: date)
        }
        workout.markDeleted(at: date)
    }

    /// CASCADE to sets.
    static func workoutExercise(_ exercise: WorkoutExercise, at date: Date = .now) {
        for set in exercise.sets {
            set.markDeleted(at: date)
        }
        exercise.markDeleted(at: date)
    }

    // MARK: - Measurements

    /// A leaf. Nothing hangs off an entry.
    static func measurementEntry(_ entry: MeasurementEntry, at date: Date = .now) {
        entry.markDeleted(at: date)
    }
}

// MARK: - Reading past tombstones
//
// Every relationship read in the app has to skip tombstones, and a missed one
// shows the user something they deleted last week. Rather than leave
// `.filter { !$0.isTombstoned }` to be remembered at thirty call sites, each
// relationship gets a `live…` accessor that filters AND sorts.
//
// Folding the sort in is deliberate: the call sites were already writing
// `.sorted { $0.order < $1.order }` by hand, so this removes a duplicated rule
// rather than adding a layer. The raw relationships stay reachable — sync needs
// tombstones, and it is the only thing that does.

extension Template {
    /// Live exercises, in order. Sync reads `exercises`; everything else reads this.
    var liveExercises: [TemplateExercise] {
        exercises.filter { !$0.isTombstoned }.sorted { $0.order < $1.order }
    }
}

extension TemplateExercise {
    var liveSets: [TemplateSet] {
        sets.filter { !$0.isTombstoned }.sorted { $0.order < $1.order }
    }
}

extension TemplateFolder {
    var liveTemplates: [Template] {
        templates.filter { !$0.isTombstoned }.sorted { $0.order < $1.order }
    }

    var liveProgramDays: [ProgramDay] {
        programDays.filter { !$0.isTombstoned }.sorted { $0.order < $1.order }
    }
}

extension Workout {
    var liveExercises: [WorkoutExercise] {
        exercises.filter { !$0.isTombstoned }.sorted { $0.order < $1.order }
    }
}

extension WorkoutExercise {
    var liveSets: [WorkoutSet] {
        sets.filter { !$0.isTombstoned }.sorted { $0.order < $1.order }
    }
}

extension MeasurementType {
    /// Live entries, newest first — a measurement's natural order is time, not
    /// a stored position, so this one sorts by `recordedAt` rather than `order`.
    var liveEntries: [MeasurementEntry] {
        entries.filter { !$0.isTombstoned }.sorted { $0.recordedAt > $1.recordedAt }
    }
}
