//
//  ExercisePreference.swift
//  MCPStrength
//
//  Per-user settings that happen to be attached to an exercise. The four
//  fields used to live on `Exercise`; they moved here so `Exercise` is
//  purely what the shared library defines — the same split the server
//  already made (`exercise_preferences`, docs/05-database.md § "The one
//  real divergence", docs/06-sync.md § "Per-exercise preferences get
//  their own local model").
//
//  ## Why this is a different model at all
//
//  Hanging the four fields off `Exercise` and syncing them from there
//  makes four problems worse at once, argued in `06-sync.md`. The short
//  version: a preference on Bench Press is the user's own data even
//  when Bench Press is a seeded library row, and it needs its own
//  `needsSync` so the exercises push cannot clear the flag the
//  preferences pass is about to read. A separate model dissolves both.
//
//  ## Why the conflict target is not `id`
//
//  The server table has no `id` column. Its primary key is
//  `(user_id, exercise_id)`. `SyncEntity.conflictTarget` carries that
//  pair; the upsert used to hard-code `"id"` and would have rejected
//  every batch, aborting the whole run. The local `id` is still the
//  exercise's, so the pull index matches without a special path —
//  unlike `AppSettings`, whose local id is a random UUID.
//
//  ## `id` is the exercise's id. Do not mint a fresh UUID.
//
//  The server table has no `id` column. Its primary key is
//  `(user_id, exercise_id)`, and there is at most one preference row
//  per user per exercise. Taking the exercise's id makes two devices
//  that independently set a bar type for Bench Press arrive at the
//  same row identity, which is the only thing that lets last-write-
//  wins settle. `ExercisePreference(id: UUID())` would mint two
//  different local ids for what the server stores as ONE row, and the
//  pull would then create a duplicate on every device with no way to
//  tell the two apart.
//
//  `docs/06-sync.md` says "the local model gets an ordinary `id`".
//  That did not reckon with there being no id column on the server to
//  match against. The ordinary `id` is still here — `SyncWireRow` and
//  the pull index assume one — but its VALUE is the exercise's.
//
//  ## The table stays sparse by construction
//
//  A row exists only where the user actually set one. Reading goes
//  through `exercise.preference?.<field>` and must NEVER create a
//  row: merely rendering a screen would then write a row of pure
//  defaults for every exercise on it. That is the same shape as the
//  43 fabricated discard entries in `00faec1` — a value meaning
//  "never touched" being read as "the user did something".
//
//  Writing goes through `current(for:in:)`, which creates the row on
//  first ask. The resolver has no caller in the app yet: the
//  Preferences sheet is a different task, and inventing a caller so
//  this felt used would be the thing the sparse rule exists to
//  prevent.
//
//  ## The rule that makes this file dangerous
//
//  **Every property needs a DECLARATION-level default** — `var x: T = v`,
//  never a default supplied only in `init`. AGENTS.md rule 2.
//  SwiftData's lightweight migration cannot see initialiser defaults,
//  so `ModelContainer(for:)` throws when opening a store written
//  before the property existed and the app dies on LAUNCH. Unit tests
//  cannot catch it by construction — they build in-memory containers
//  from the current schema, so there is never an old store to
//  migrate.
//
//  `focusMetric` on `Exercise` was `var focusMetric: FocusMetric` with
//  no declaration default, a latent instance of exactly this bug that
//  survived only because the property has always been there. It is
//  not carried across. The default is `.totalVolume`, matching the
//  Postgres column.
//

import Foundation
import SwiftData

@Model
final class ExercisePreference {
    /// The exercise's id, not a freshly minted UUID. See the file comment.
    var id: UUID = UUID()

    // MARK: Sync metadata
    //
    // Wired. The conformance lives in Syncable.swift — that list is the
    // answer to what leaves the device. The local `id` is the exercise's
    // id, so the generic pull index matches. The wire row's `id` is
    // computed from `exercise_id` because the server table has no `id`
    // column to decode.

    /// Wall-clock time of the last local edit. The last-write-wins key.
    var updatedAt: Date = Date.distantPast
    /// Tombstone. Non-nil means deleted.
    var deletedAt: Date?
    /// Has local changes the server has not confirmed.
    var needsSync: Bool = true

    // MARK: The four per-user fields

    /// Per-exercise unit, or `nil` to follow the global setting. That
    /// `nil` IS the *Default* option in the reference app's three-way
    /// Weight Unit row, not a missing value to paper over.
    var weightUnitOverride: WeightUnit?

    var barType: BarType?

    /// **Fully qualified default** — the `@Model` macro rejects `.totalVolume`
    /// with "A default value requires a fully qualified domain named
    /// value". Same wrinkle as `AppSettings.weightUnit`.
    var focusMetric: FocusMetric = FocusMetric.totalVolume

    var notes: String?

    /// Back-reference. Optional on both sides so adding the relationship
    /// to a store that already has `Exercise` rows is a lightweight
    /// migration. A non-optional relationship would kill the app on
    /// launch against the store on the phone.
    var exercise: Exercise?

    init(
        id: UUID,
        weightUnitOverride: WeightUnit? = nil,
        barType: BarType? = nil,
        focusMetric: FocusMetric = .totalVolume,
        notes: String? = nil,
        exercise: Exercise? = nil
    ) {
        self.id = id
        self.weightUnitOverride = weightUnitOverride
        self.barType = barType
        self.focusMetric = focusMetric
        self.notes = notes
        self.exercise = exercise
    }
}

extension ExercisePreference {

    /// The preference row for this exercise, created on first ask.
    ///
    /// This is the WRITE path. Reading is `exercise.preference?.<field>`
    /// and must not come through here — see the file comment on
    /// sparsity. Modelled on `AppSettings.current(in:)`: return the
    /// existing row if there is one, otherwise create it with
    /// `id: exercise.id`, wire the relationship, insert, and return.
    ///
    /// Call `markEdited()` when a field is actually changed. Creating
    /// the row is not itself an edit — a freshly inserted row already
    /// lands dirty (`needsSync = true`) with `updatedAt == .distantPast`,
    /// which is honest, and stamping `.now` here would date a row of
    /// pure defaults to "just now" before the user has set anything.
    static func current(for exercise: Exercise, in context: ModelContext) -> ExercisePreference {
        if let existing = exercise.preference {
            return existing
        }

        let exerciseID = exercise.id
        var descriptor = FetchDescriptor<ExercisePreference>(
            predicate: #Predicate { $0.id == exerciseID }
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.exercise = exercise
            return existing
        }

        let created = ExercisePreference(id: exercise.id, exercise: exercise)
        context.insert(created)
        return created
    }
}
