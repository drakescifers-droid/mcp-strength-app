//
//  Syncable.swift
//  MCPStrength
//
//  The three columns every synced model carries, and the two operations that
//  are allowed to change them.
//
//  See docs/06-sync.md. Nothing here talks to the network; this is the local
//  bookkeeping the engine will read.
//
//  ## The defaults are load-bearing — read before changing one
//
//  `var needsSync: Bool = true`, not `false`. Two reasons, and both are about
//  which way this fails:
//
//    * A newly created object genuinely IS unsynced. Defaulting to false means
//      every `Workout(...)` starts life claiming to be pushed already, and the
//      only thing standing between a user's workout and oblivion is whether
//      every creation site remembered to say otherwise.
//    * EXISTING ROWS MIGRATE IN WITH THE DEFAULT. The store on this machine
//      predates these columns. With `false`, every workout already logged would
//      migrate in marked clean and never be pushed — the data silently left
//      behind, with a UI cheerfully reporting it is up to date.
//
//  So `true` is the safe direction: the failure mode is pushing something
//  twice, which is idempotent, instead of never pushing it, which is loss.
//  `false` is written ONLY by the sync engine, per row, after the server has
//  confirmed that row.
//
//  `var updatedAt: Date = Date.distantPast` means "never stamped". Migrated
//  rows land here honestly rather than pretending to have been edited at
//  migration time, and the first sync backfills them (docs/06-sync.md § "Rows
//  that predate sign-in"). Using `Date()` as the default would date every row
//  in the store to whenever the app happened to be upgraded, which is a
//  fabricated timestamp that then WINS last-write-wins comparisons against
//  genuinely newer remote edits.
//
//  Every property added here needs a DECLARATION-level default — `var x = y` on
//  the property, never a default in `init`. SwiftData's lightweight migration
//  cannot see initialiser defaults, and `ModelContainer(for:)` throws on launch
//  against a store written before the property existed. See docs/04-status.md
//  § "Lessons worth not relearning"; this change is exactly the situation that
//  lesson was written for.
//

import Foundation

/// A model that participates in sync.
///
/// Conformance is deliberately not automatic. A type joining this protocol is a
/// type whose rows start travelling to a server, which is a decision, not a
/// detail.
protocol Syncable: AnyObject {
    /// Wall-clock time of the last local edit. The last-write-wins comparison
    /// key, and the CLIENT's clock on purpose: an edit made offline has no
    /// server time. It is never the pull cursor — see docs/05-database.md.
    var updatedAt: Date { get set }

    /// Tombstone. Non-nil means deleted; the row stays so the delete can
    /// propagate to devices that were offline when it happened.
    var deletedAt: Date? { get set }

    /// This row has local changes the server has not confirmed.
    var needsSync: Bool { get set }
}

extension Syncable {

    /// Whether this row is a tombstone.
    ///
    /// Named `isTombstoned`, not `isDeleted`: `PersistentModel` already has an
    /// `isDeleted` meaning "removed from the context in this session", and two
    /// properties one letter apart with different meanings is a bug waiting for
    /// a tired reader.
    var isTombstoned: Bool { deletedAt != nil }

    /// Record a local edit. Call from every mutation site.
    ///
    /// MUST NOT be called when applying a row pulled FROM the server. Doing so
    /// dirties everything a pull touches, the next push sends it all straight
    /// back, and the two ends never settle — a sync that looks extremely busy
    /// and never finishes. docs/06-sync.md § "The echo trap".
    func markEdited(at date: Date = .now) {
        updatedAt = date
        needsSync = true
    }

    /// Tombstone this row. The soft-delete replacement for `context.delete`.
    ///
    /// Does NOT cascade. SwiftData's `.cascade` rules fire on real deletes and
    /// will not fire here, so a parent's children must be walked explicitly by
    /// the caller. That is deliberate rather than hidden inside this method:
    /// the cascade shape differs per type, and a silent partial cascade is
    /// worse than an obvious call site.
    func markDeleted(at date: Date = .now) {
        // Idempotent. Re-deleting must not move the timestamp, or a repeated
        // tap keeps resetting the 90-day retention clock on a row nobody is
        // coming back for.
        guard deletedAt == nil else { return }
        deletedAt = date
        updatedAt = date
        needsSync = true
    }

    /// Mark this row as matching the server. Called ONLY by the sync engine,
    /// per row, after the server confirms that row.
    func markSynced() {
        needsSync = false
    }
}

// MARK: - Conformances
//
// Every synced type, in one place on purpose. This list IS the answer to "what
// leaves the device", and keeping it here rather than scattered across the
// model files means adding a type to it is a visible, deliberate line in a
// diff rather than a word appended to a class declaration.
//
// The order matches the push/pull order in docs/06-sync.md: parents before
// children, so foreign keys resolve in both directions.

extension AppSettings: Syncable {}
extension Exercise: Syncable {}
extension ExercisePreference: Syncable {}
extension TemplateFolder: Syncable {}
extension Template: Syncable {}
extension TemplateExercise: Syncable {}
extension TemplateSet: Syncable {}
extension ProgramDay: Syncable {}
extension Workout: Syncable {}
extension WorkoutExercise: Syncable {}
extension WorkoutSet: Syncable {}
extension MeasurementType: Syncable {}
extension MeasurementEntry: Syncable {}
