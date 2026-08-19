//
//  SyncPlanning.swift
//  MCPStrength
//
//  The decisions a sync run makes, as pure functions — what order to send
//  things in, where to resume from, and who wins a conflict.
//
//  Separated from the transport on purpose, and it is the same split as
//  RepRangeParser and ListOrdering: the network call is boilerplate, while
//  these three rules are where data is silently lost. They are testable here
//  with no server, no session and no clock of their own.
//

import Foundation

// MARK: - Order

/// The synced tables, in the order a run must touch them.
///
/// **Parents before children, and the order is load-bearing in both
/// directions.** Pushing a `template_set` before its `template_exercise`
/// exists is a foreign-key violation, and pulling in the wrong order is the
/// same failure with the rows arriving from the other side.
///
/// Because every operation is an upsert — including deletes, which are updates
/// that set `deleted_at` — there is no reverse pass. Nothing is ever removed by
/// sync, so no child is ever orphaned by it.
enum SyncEntity: String, CaseIterable, Sendable {
    /// First: its only foreign key is to `auth.users`, so nothing else
    /// has to exist before it can land. `allCases` is the push and pull
    /// order, and a test asserts that order satisfies `dependsOn`.
    case appSettings
    case exercises
    case exercisePreferences
    case templateFolders
    case templates
    case templateExercises
    case templateSets
    case programDays
    case workouts
    case workoutExercises
    case workoutSets
    case measurementTypes
    case measurementEntries

    /// The tables a row of this type points at. Declared separately from the
    /// order above so a test can check the order actually satisfies them —
    /// otherwise `allCases` is just a list somebody can reorder without
    /// noticing that they have.
    var dependsOn: [SyncEntity] {
        switch self {
        case .appSettings:          []
        case .exercises:            []
        case .exercisePreferences:  [.exercises]
        case .templateFolders:      []
        case .templates:            [.templateFolders]
        case .templateExercises:    [.templates, .exercises]
        case .templateSets:         [.templateExercises]
        case .programDays:          [.templateFolders, .templates]
        case .workouts:             [.templates]
        case .workoutExercises:     [.workouts, .exercises]
        case .workoutSets:          [.workoutExercises]
        case .measurementTypes:     []
        case .measurementEntries:   [.measurementTypes]
        }
    }
}

// MARK: - Cursor

/// Where to resume a pull from.
enum SyncCursor {

    /// How far back to re-read on every pull.
    ///
    /// `now()` in Postgres is TRANSACTION-START time, so two overlapping
    /// transactions can commit out of order: a row whose transaction began
    /// before the cursor can land in the table after it. Re-reading a few
    /// seconds of already-seen rows costs nothing — every apply is an idempotent
    /// upsert — and it is far cheaper than the alternative, which is a row that
    /// silently never arrives and cannot be identified afterwards.
    ///
    /// Five seconds is comfortably longer than any transaction this app runs
    /// and short enough to stay cheap. docs/05-database.md § "Two timestamps".
    static let overlap: TimeInterval = 5

    /// The value to send as `server_updated_at > ?`.
    ///
    /// `nil` means "everything" — the first sync on a device, which must not
    /// silently start from now and leave the account's existing history
    /// unpulled forever.
    static func pullSince(_ cursor: Date?) -> Date? {
        guard let cursor else { return nil }
        return cursor.addingTimeInterval(-overlap)
    }

    /// Advance the cursor after a successful pull.
    ///
    /// Takes the newest `server_updated_at` actually SEEN, never the local
    /// clock: the cursor lives in server time, and mixing in a device's clock
    /// is how it drifts past rows it never received. A pull that returned
    /// nothing leaves the cursor exactly where it was.
    static func advanced(from cursor: Date?, seeing newest: Date?) -> Date? {
        switch (cursor, newest) {
        case (let c, nil):       return c
        case (nil, let n):       return n
        case (let c?, let n?):   return max(c, n)
        }
    }
}

// MARK: - Conflicts

/// What to do with a pulled row that also exists locally.
enum ConflictOutcome: Equatable, Sendable {
    /// Overwrite the local row.
    case takeRemote
    /// Leave the local row alone; it is newer and will be pushed.
    case keepLocal
    /// Overwrite the local row AND record that a local edit was discarded.
    ///
    /// Distinct from `takeRemote` because last-write-wins throws away a real
    /// user edit here, silently and by design. `02-architecture.md` asks for
    /// that to be diagnosable rather than spooky — *"my template reverted"*
    /// should be answerable — so the caller logs both timestamps locally.
    case takeRemoteDiscardingLocalEdit
}

enum ConflictResolver {

    /// Record-level last-write-wins on `updatedAt`.
    ///
    /// TIES GO TO LOCAL when the local row is dirty. An unpushed local edit is
    /// the only copy of that change in existence, while the remote version is
    /// already durable somewhere — so when the two timestamps cannot separate
    /// them, the tie-break protects the copy that could still be lost. It also
    /// terminates: local pushes, the server takes it, and the next pull agrees.
    static func resolve(
        localUpdatedAt: Date,
        localIsDirty: Bool,
        remoteUpdatedAt: Date
    ) -> ConflictOutcome {
        guard localIsDirty else {
            // Nothing local to protect. Take the server's version even when it
            // is older — a clean local row is only ever a copy of something the
            // server already had.
            return .takeRemote
        }
        if localUpdatedAt >= remoteUpdatedAt {
            return .keepLocal
        }
        return .takeRemoteDiscardingLocalEdit
    }
}

// MARK: - What to push

enum PushFilter {

    /// Whether a row should be sent.
    ///
    /// The rule is `needsSync`, with one exception that would otherwise fail
    /// every sync on the account: SEEDED EXERCISES ARE NOT USER DATA. They live
    /// on the server once, globally, with `user_id IS NULL` and the same baked
    /// UUIDs the app ships. Pushing one as owned data violates
    /// `exercises_custom_iff_owned` — the constraint doing exactly its job —
    /// and the run fails on a row the user has never heard of. Filter rather
    /// than discover. docs/05-database.md § Ownership.
    static func shouldPush(_ exercise: Exercise) -> Bool {
        exercise.needsSync && exercise.isCustom
    }

    /// An UNFINISHED workout never leaves the device, and neither does anything
    /// under it.
    ///
    /// A workout in progress is not a record of training, it is a draft — sets
    /// appear, get retyped, get discarded at Finish. Uploading that would put
    /// half a session on the server and, worse, would make the discard at
    /// Finish unsafe: WorkoutFinishing HARD-deletes unticked sets, which is
    /// only correct while those rows have never left the device.
    ///
    /// This is enforced here rather than by scheduling sync carefully. "Never
    /// sync during a workout" is a rule someone has to remember and a
    /// foreground event can violate by accident; "an unfinished workout is not
    /// eligible" cannot be violated at all.
    ///
    /// Live session mirroring — a Watch showing the current set, heart rate
    /// coming back — is a different transport (Bluetooth, on-device) and a
    /// different problem. It does not belong on the path that talks to Postgres.
    static func shouldPush(_ workout: Workout) -> Bool {
        workout.needsSync && workout.completedAt != nil
    }

    static func shouldPush(_ exercise: WorkoutExercise) -> Bool {
        exercise.needsSync && exercise.workout?.completedAt != nil
    }

    static func shouldPush(_ set: WorkoutSet) -> Bool {
        set.needsSync && set.workoutExercise?.workout?.completedAt != nil
    }

    /// SEEDED MEASUREMENT TYPES ARE NOT USER DATA, for exactly the reason
    /// seeded exercises are not.
    ///
    /// They exist twice — local rows, and global Postgres rows with
    /// `user_id IS NULL` sharing the same baked UUIDs. `needsSync` defaults to
    /// `true`, so unfiltered the engine pushes all 18 as owned data; PostgREST
    /// turns the upsert into an UPDATE on the global row and
    /// `measurement_types_update`'s `USING (user_id = auth.uid())` refuses it:
    ///
    ///     42501 — new row violates row-level security policy
    ///
    /// That aborts the WHOLE RUN, so the pull never happens either, and every
    /// later sync fails identically. This was the first failure a real round
    /// trip produced — the fake transport had accepted it for the entire life
    /// of the test suite. docs/06-sync.md § "The seeded library exists twice"
    /// called for this filter and only the exercise half was ever written.
    ///
    /// `MeasurementType` has no `isCustom` (unlike `Exercise`), so the seed
    /// file is the discriminator. A user-created type's UUID is not in it and
    /// pushes normally, with nothing to remember.
    ///
    /// `seededIDs` is injectable so the RULE can be tested without a bundle;
    /// the default is the real seed.
    ///
    /// > **Consequence worth knowing:** an edit to a SEEDED type — were the UI
    /// > ever to allow renaming or reordering one — cannot travel. That mirrors
    /// > seeded exercises, whose per-user fields live in `exercise_preferences`;
    /// > measurement types have no such table yet. Today nothing can create or
    /// > rename one, so nothing is lost.
    static func shouldPush(
        _ type: MeasurementType,
        seededIDs: Set<UUID> = MeasurementSeedImporter.seededIDs
    ) -> Bool {
        type.needsSync && !seededIDs.contains(type.id)
    }

    /// A settings row that has never been edited must not leave the device.
    ///
    /// `needsSync` defaults to `true` and the app creates this row at first
    /// launch, so a freshly installed device has a dirty row of pure defaults
    /// nobody chose. A run is claim → push → pull, so that device would push
    /// BEFORE it pulls — and `pushModels` backfills `.distantPast` to `Date()`
    /// on the way out. Phone B then uploads pounds stamped *now* over the
    /// kilograms Drake picked on phone A, wins last-write-wins, and both
    /// devices revert. Nothing reports a conflict: as far as the engine is
    /// concerned B made the newer edit.
    ///
    /// `.distantPast` is how this codebase already spells "never stamped".
    /// `setWeightUnit` calls `markEdited`, so a genuine choice is eligible
    /// immediately. The backfill is safely downstream of this check, so a
    /// defaults row is never stamped on the way out. docs/06-sync.md §
    /// "A never-touched settings row MUST NOT PUSH".
    static func shouldPush(_ settings: AppSettings) -> Bool {
        settings.needsSync && settings.updatedAt != .distantPast
    }

    /// Everything else is simply "has unconfirmed local changes".
    static func shouldPush(_ row: any Syncable) -> Bool {
        switch row {
        case let exercise as Exercise:          shouldPush(exercise)
        case let workout as Workout:            shouldPush(workout)
        case let workoutExercise as WorkoutExercise: shouldPush(workoutExercise)
        case let set as WorkoutSet:             shouldPush(set)
        // `seededIDs:` is passed EXPLICITLY, and that is load-bearing. Written
        // as `shouldPush(type)` the compiler resolves it back to THIS function
        // — `MeasurementType` conforms to `Syncable`, and an overload needing a
        // defaulted argument loses to one that takes exactly one parameter — so
        // it calls itself until the stack dies. It compiles, and it crashed the
        // app on launch (EXC_BAD_ACCESS, "excessive recursion") the first time
        // a sync ran. The other cases are safe only because their overloads
        // take a single argument and win outright. `AppSettings` is in that
        // safe group: its overload takes exactly one parameter.
        case let type as MeasurementType:
            shouldPush(type, seededIDs: MeasurementSeedImporter.seededIDs)
        case let settings as AppSettings:       shouldPush(settings)
        default:                                row.needsSync
        }
    }

    /// How many local changes are waiting — the number the UI reports.
    static func pendingCount(_ rows: [any Syncable]) -> Int {
        rows.count { shouldPush($0) }
    }
}
