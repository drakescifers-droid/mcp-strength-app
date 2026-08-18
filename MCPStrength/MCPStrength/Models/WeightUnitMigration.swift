//
//  WeightUnitMigration.swift
//  MCPStrength
//
//  The one-shot conversion of every stored weight from pounds to kilograms.
//
//  Storage became canonical kilograms in the same change that rewired the
//  screens to convert on the way in and out (docs/01-data-model.md § Units
//  decision). This is the other half of it: the numbers already in the store
//  were typed as pounds and mean nothing until they are converted.
//
//  ## Why this and the rewiring had to land together
//
//  Neither half is safe alone, and the failure is silent in both directions:
//
//    * **Rewired, not converted** — the screens divide a stored pound value as
//      if it were kilograms, so a 135 lb bench reads as 298.
//    * **Converted, not rewired** — the screens print a stored kilogram value
//      raw, so the same lift reads as 61.
//
//  There is no intermediate commit that leaves the app correct, which is why
//  the pure conversion layer (`WeightUnits`) and the settings row were landed
//  separately first: those two ARE safe alone, because nothing called them.
//
//  ## Running twice is the thing to be afraid of
//
//  A second pass multiplies kilograms by 0.45359237 again and quietly halves
//  every lift ever logged. Nothing throws, nothing looks broken, and the number
//  is plausible — a 315 lb deadlift becomes 143, which is a real weight
//  somebody could lift. There is no way to detect it after the fact, because a
//  converted store and a twice-converted store are the same shape.
//
//  So the guard is not a nicety. Two things make it hold:
//
//    1. **The marker lives in the store** (`StoreMigrations`), so it cannot get
//       out of step with the rows it describes — see that file for why not
//       UserDefaults and why not `AppSettings`.
//    2. **The rows and the marker are written in ONE save.** A crash between
//       "converted the weights" and "recorded that I did" would otherwise leave
//       a converted store marked unconverted, which is the twice-converted case
//       arriving by a different route. One `context.save()` at the end makes
//       that window not exist.
//
//  ## Why it does not mark anything edited
//
//  Converting is not a user edit, and `markEdited()` here would be wrong twice.
//  It would push kilograms up to a server that is converting its own rows in
//  the same release (`supabase/migrations`), which — if the client got there
//  first — would hand the SQL migration an already-converted row to halve. And
//  it would dirty the entire history on every device for a change that produces
//  identical values on both ends. Both sides convert independently and agree.
//
//  > **Ordering, once, for the live project:** apply the SQL migration BEFORE
//  > running a build of this app against it. Rows that were already dirty when
//  > the local conversion ran are the one class that pushes kilograms without
//  > being marked here, and a server that has not converted yet would then
//  > convert them a second time.
//

import Foundation
import SwiftData

enum WeightUnitMigration {

    /// What a run did, so a caller (and a test) can tell "converted nothing
    /// because it was already done" from "converted nothing because there was
    /// nothing to convert". Those look identical from the outside and mean
    /// completely different things.
    enum Outcome: Equatable, Sendable {
        /// The marker said this store was already converted. Nothing was read
        /// and nothing was written.
        case alreadyConverted
        /// The conversion ran. Counts are rows actually changed: sets whose
        /// weight was non-nil, and workouts whose volume was non-zero.
        case converted(workoutSets: Int, templateSets: Int, workouts: Int)
    }

    /// Convert every stored weight in `context` from pounds to kilograms, at
    /// most once per store.
    ///
    /// Covers three columns, and the third is the one that hides:
    ///
    ///   * `WorkoutSet.weight` and `TemplateSet.weight` — the loads themselves.
    ///   * **`Workout.totalVolume`** — a stored, SYNCED `weight × reps` total,
    ///     computed once at Finish (`WorkoutFinishing`) and never recomputed on
    ///     read. It is a weight in disguise: nothing about it is named `weight`,
    ///     no screen writes it, and it is the number the history card and the
    ///     detail header actually display. Converting the sets under it and not
    ///     the total leaves every finished session reporting 2.2× its own sets.
    ///
    /// Body measurements are NOT included: a `MeasurementEntry` carries its own
    /// unit string per entry (`MeasurementSeedImporter`), so it was never in the
    /// pounds-by-assumption group this converts.
    ///
    /// **Tombstoned rows are converted too.** They are excluded from every
    /// screen, but they are still rows the server has, and a store where the
    /// live weights are kilograms and the deleted ones are pounds is a store
    /// with two meanings for one column.
    ///
    /// Throws only if the save fails, in which case nothing is committed — the
    /// weights and the marker are in the same transaction — and the next launch
    /// tries again.
    @discardableResult
    static func run(in context: ModelContext) throws -> Outcome {
        let record = StoreMigrations.current(in: context)
        guard !record.didConvertWeightsToKilograms else { return .alreadyConverted }

        let workoutSets = try context.fetch(FetchDescriptor<WorkoutSet>())
        let templateSets = try context.fetch(FetchDescriptor<TemplateSet>())
        let workouts = try context.fetch(FetchDescriptor<Workout>())

        var convertedWorkoutSets = 0
        for set in workoutSets {
            guard let pounds = set.weight else { continue }
            set.weight = WeightUnits.kilograms(from: pounds, in: .lbs)
            convertedWorkoutSets += 1
        }

        var convertedTemplateSets = 0
        for set in templateSets {
            guard let pounds = set.weight else { continue }
            set.weight = WeightUnits.kilograms(from: pounds, in: .lbs)
            convertedTemplateSets += 1
        }

        // A volume is `weight × reps`, so it scales by exactly the same factor
        // as the weights that produced it. `0` is left alone rather than
        // multiplied: it is the untouched default on a workout that was never
        // finished, and counting it would make the outcome say work was done.
        var convertedWorkouts = 0
        for workout in workouts where workout.totalVolume != 0 {
            workout.totalVolume = WeightUnits.kilograms(from: workout.totalVolume, in: .lbs)
            convertedWorkouts += 1
        }

        record.didConvertWeightsToKilograms = true

        // One save, deliberately. See the file comment: a crash between the
        // rows and the marker is the twice-converted case wearing a disguise.
        try context.save()

        return .converted(
            workoutSets: convertedWorkoutSets,
            templateSets: convertedTemplateSets,
            workouts: convertedWorkouts
        )
    }
}
