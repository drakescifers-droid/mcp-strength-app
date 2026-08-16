//
//  WorkoutFinishing.swift
//  MCPStrength
//
//  What happens to the sets you never ticked when you tap Finish.
//
//  ## The decision: they are discarded
//
//  A workout is a record of what you DID. An unticked set was not performed —
//  it is a row the template put there, or one you added and did not get to. Two
//  things went wrong while it was kept:
//
//    * History showed work that never happened. A session read as five
//      exercises when two of them were never touched.
//    * The volume total read 0 lb next to visible numbers, because volume counts
//      completed sets only. Correct, and baffling.
//
//  Keeping them also stores — and, once sync lands, UPLOADS — rows describing
//  training that did not occur.
//
//  ## Why this is a REAL delete and not a tombstone
//
//  Everything else in this app soft-deletes, so an offline device can learn
//  about the removal (docs/06-sync.md). Not here, and the exception is the
//  whole point of the decision: a tombstone still stores the row and still
//  syncs it. Tombstoning to avoid storing unnecessary data stores the
//  unnecessary data.
//
//  That is only safe because an unticked set has NEVER LEFT THE DEVICE, and
//  that is GUARANTEED rather than merely arranged: `PushFilter.shouldPush`
//  makes an unfinished workout — and everything under it — ineligible to
//  upload. So no scheduling accident, foreground event or manual sync can put
//  these rows on the server before Finish decides their fate.
//
//  The weaker version of this rule was "sync never runs during a workout",
//  which someone has to remember and a background/foreground cycle can break by
//  accident. If that filter is ever relaxed, this hard delete becomes unsafe:
//  the rows could exist on the server and deleting them locally would strand
//  them there, alive, on every other device.
//
//  ## Empty exercises go too
//
//  An exercise whose sets were all unticked is an exercise you did not do, and
//  the same argument applies to it. An exercise that keeps SOME sets stays,
//  with the sets you completed.
//
//  ## What this deliberately does NOT decide
//
//  Whether to ask first. Discarding silently destroys numbers the user may have
//  typed and simply forgotten to tick, which is data loss from a mis-tap. The
//  caller decides whether to confirm; `discardableSummary` exists to let it ask
//  a specific question rather than a vague one.
//

import Foundation
import SwiftData

enum WorkoutFinishing {

    /// What would be thrown away, so the caller can ask before doing it.
    struct DiscardSummary: Equatable, Sendable {
        /// Sets that were never ticked.
        var setCount: Int
        /// Exercises that would be left with nothing.
        var exerciseCount: Int
        /// Whether any of the doomed sets had numbers typed into them.
        ///
        /// The difference between "you skipped the last set" and "you typed
        /// 135 × 6 and forgot to tick it". Only the second is worth
        /// interrupting someone over.
        var hasEnteredValues: Bool

        var isEmpty: Bool { setCount == 0 && exerciseCount == 0 }
    }

    /// Inspect without changing anything.
    static func discardSummary(for workout: Workout) -> DiscardSummary {
        var sets = 0
        var exercises = 0
        var entered = false

        for exercise in workout.liveExercises {
            let live = exercise.liveSets
            let doomed = live.filter { !$0.isCompleted }
            sets += doomed.count
            if doomed.contains(where: { $0.weight != nil || $0.reps != nil
                                        || $0.distance != nil || $0.duration != nil }) {
                entered = true
            }
            if !live.isEmpty && doomed.count == live.count {
                exercises += 1
            }
        }
        return DiscardSummary(setCount: sets, exerciseCount: exercises, hasEnteredValues: entered)
    }

    /// Complete the workout: drop what was not performed, then stamp the
    /// totals.
    ///
    /// Order matters. `totalVolume` is computed AFTER the discard so it is a
    /// total of what remains; computing first would leave a number describing
    /// a workout that no longer exists.
    static func finish(
        _ workout: Workout,
        elapsedSeconds: Int,
        in context: ModelContext,
        at date: Date = .now
    ) {
        for exercise in workout.liveExercises {
            let live = exercise.liveSets
            for set in live where !set.isCompleted {
                context.delete(set)
            }
            // Only when EVERY set went. An exercise that kept one is kept.
            if !live.isEmpty && live.allSatisfy({ !$0.isCompleted }) {
                context.delete(exercise)
            }
        }

        // FLUSH BEFORE READING BACK. `context.delete` does not remove the
        // object from an already-loaded relationship array until pending
        // changes are processed, so `workout.liveExercises` would still hand
        // back the rows just deleted — and the volume below would be totalled
        // over a workout that no longer exists. Four tests failed on exactly
        // this before the save was here.
        try? context.save()

        workout.completedAt = date
        workout.durationSeconds = elapsedSeconds
        workout.totalVolume = WorkoutStats.totalVolume(for: workout)
        workout.markEdited(at: date)
    }
}
