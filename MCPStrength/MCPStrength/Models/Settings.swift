//
//  Settings.swift
//  MCPStrength
//
//  The user's global preferences — one row, and the thing that makes canonical
//  storage legible. See docs/01-data-model.md § Settings.
//
//  ## Why this exists at all
//
//  Weights are stored canonically in KILOGRAMS (docs/01-data-model.md § Units
//  decision, chosen 2026-08-18). A stored number therefore no longer means
//  anything on its own: 61.23 is 135 lb to a pounds lifter and 61.2 kg to a
//  metric one. Something has to hold the answer to "which unit do I show", it
//  has to survive relaunches, and nothing did before this file.
//
//  ## Why every field is here, including the ones nothing reads
//
//  This carries the WHOLE list from `01-data-model.md` rather than only the
//  units this task needs, and that is the Program schema precedent in
//  docs/04-status.md: `ProgramDay` and friends shipped in Phase 1 with no UI
//  on purpose, because *"additive-by-construction only helps if the columns
//  exist before there are users."* Drake is about to start training on this,
//  so "before there are users" is nearly over.
//
//  It is NOT the Archive precedent, which is the case for waiting. Archive is a
//  menu item a user can TAP that would do nothing — a visible half-feature. A
//  field with no screen is invisible, and `06-sync.md` makes the same argument
//  for the four fields leaving `Exercise`: they are safe to reshape *"for a
//  reason that will not stay true: nothing writes them today."* An unused field
//  is free to change. It stops being free the moment something writes it.
//
//  Which is exactly why **`theme` and `previousSetBehavior` are `String?` and
//  not enums.** Their case lists are the part nobody has decided — there is no
//  light palette designed, and only ONE Previous behaviour has been built (see
//  `SetNumbering.positionsWithinKind`). A `String?` says "shape undecided" out
//  loud, where an enum would quietly commit to cases and then need an enum
//  migration on two sides to change, the way `BarType` now does. They become
//  enums when they get a screen, and they must not get a screen before then.
//
//  ## The rule that makes this file dangerous
//
//  **Every property needs a DECLARATION-level default** — `var x: T = v`, never
//  a default supplied only in `init`. AGENTS.md rule 2, and it is the single
//  most expensive mistake in this codebase: SwiftData's lightweight migration
//  cannot see initialiser defaults, so `ModelContainer(for:)` throws when
//  opening a store written before the property existed and the app dies on
//  LAUNCH. Unit tests cannot catch it by construction — they build in-memory
//  containers from the current schema, so there is never an old store to
//  migrate. Adding nine properties at once is nine chances to get it wrong,
//  which is the real cost of doing the whole list in one go.
//

import Foundation
import SwiftData

/// Distance for cardio work. `WeightUnit` already exists on `Exercise`.
enum DistanceUnit: String, Codable, CaseIterable, Sendable {
    case miles, kilometers
}

/// Body measurements — circumferences, not loads.
enum SizeUnit: String, Codable, CaseIterable, Sendable {
    case inches, centimeters
}

@Model
final class AppSettings {
    var id: UUID = UUID()

    /// When this row was made, so "which row is the real one" has a
    /// deterministic answer rather than depending on fetch order. See
    /// `current(in:)`.
    var createdAt: Date = Date.distantPast

    // MARK: Sync metadata
    //
    // Present but NOT YET WIRED. `AppSettings` deliberately does not conform to
    // `Syncable` and has no `SyncEntity` case — there is no settings table in
    // Postgres yet (docs/05-database.md § What is not here yet). The columns are
    // here now anyway, because adding a stored property later is precisely the
    // crash-on-launch rule above, and the conformance is a one-line decision
    // once the table exists.
    //
    // `Syncable`'s conformance list is described there as "the answer to what
    // leaves the device", so flipping it is deliberately a separate, visible
    // change rather than something that arrives with a column.

    /// Wall-clock time of the last local edit. The last-write-wins key.
    var updatedAt: Date = Date.distantPast
    /// Tombstone. Non-nil means deleted.
    var deletedAt: Date?
    /// Has local changes the server has not confirmed.
    var needsSync: Bool = true

    // MARK: Units — the reason this model exists
    //
    // **Enum defaults are spelled `WeightUnit.lbs`, not `.lbs`.** The `@Model`
    // macro rejects the inferred form with "A default value requires a fully
    // qualified domain named value" — it reads the initial value before the
    // property's type is known to it, so there is nothing for `.lbs` to be
    // shorthand FOR. A wrinkle in AGENTS.md rule 2 rather than an exception to
    // it: the default still has to be on the declaration, it just has to spell
    // the type out.

    /// Unit for training loads. Storage is always kg; this is display only.
    var weightUnit: WeightUnit = WeightUnit.lbs

    /// Unit for BODY weight and other measured masses, separate from training
    /// loads on purpose: lifting in kg while weighing yourself in pounds is an
    /// ordinary combination, and the reference app separates them too.
    var measurementWeightUnit: WeightUnit = WeightUnit.lbs

    /// Unit for cardio distance.
    var distanceUnit: DistanceUnit = DistanceUnit.miles

    /// Unit for body-part circumferences.
    var sizeUnit: SizeUnit = SizeUnit.inches

    // MARK: Settled behaviour, currently hardcoded

    /// Rest to seed a new set with, in seconds.
    ///
    /// `90` matches the value hardcoded at every creation site today
    /// (`Workout.swift`, `Template.swift`), so introducing this row changes no
    /// behaviour until something reads it.
    var defaultRestSeconds: Int = 90

    /// First day of the week, in `Calendar.firstWeekday` numbering where Sunday
    /// is 1. An Int rather than an enum because Calendar already owns the
    /// vocabulary and there is nothing to invent — the profile chart's weekly
    /// buckets are the only reader.
    var weekStartDay: Int = 1

    // MARK: Shape not decided — no screen until it is

    /// Light / dark / follow-the-system, once a light palette exists. There is
    /// no light palette, so a picker for this today would either do nothing or
    /// produce an unstyled screen. `nil` means follow the system.
    ///
    /// `String?` rather than an enum ON PURPOSE — see the file comment.
    var theme: String?

    /// Device language override, once the app is localised. It is not localised
    /// at all today. `nil` means follow the device.
    var language: String?

    /// What the Previous column reports — last time, personal best, or the same
    /// slot in the same template. Exactly ONE behaviour exists today ("last
    /// time", matched within set kind), and the others are not designed.
    ///
    /// `String?` rather than an enum ON PURPOSE — see the file comment.
    var previousSetBehavior: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        weightUnit: WeightUnit = .lbs,
        measurementWeightUnit: WeightUnit = .lbs,
        distanceUnit: DistanceUnit = .miles,
        sizeUnit: SizeUnit = .inches,
        defaultRestSeconds: Int = 90,
        weekStartDay: Int = 1,
        theme: String? = nil,
        language: String? = nil,
        previousSetBehavior: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.weightUnit = weightUnit
        self.measurementWeightUnit = measurementWeightUnit
        self.distanceUnit = distanceUnit
        self.sizeUnit = sizeUnit
        self.defaultRestSeconds = defaultRestSeconds
        self.weekStartDay = weekStartDay
        self.theme = theme
        self.language = language
        self.previousSetBehavior = previousSetBehavior
    }
}

extension AppSettings {

    /// The settings row, created on first ask.
    ///
    /// There must be exactly one, and "exactly one" is enforced by resolution
    /// rather than by a constraint SwiftData does not offer: the OLDEST live row
    /// wins, deterministically, so two callers racing on first launch cannot
    /// disagree about which row is authoritative. Extra rows are left alone
    /// rather than deleted — a hard delete here is the thing AGENTS.md rule 1
    /// forbids, and once this syncs a duplicate arriving from another device is
    /// exactly the case that must not destroy data.
    ///
    /// > **Open, and it belongs to the sync task, not here.** One row per user
    /// > means the server key is `user_id`, not `id` — so a device that creates
    /// > its own row and then pulls the account's row has two, with different
    /// > ids and no way to tell they are the same thing. That is the same
    /// > per-entity conflict-target work `docs/06-sync.md` specifies for
    /// > `exercise_preferences`; do it once for both. Until then this is
    /// > local-only and cannot produce a duplicate.
    static func current(in context: ModelContext) -> AppSettings {
        var descriptor = FetchDescriptor<AppSettings>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let created = AppSettings()
        context.insert(created)
        return created
    }
}
