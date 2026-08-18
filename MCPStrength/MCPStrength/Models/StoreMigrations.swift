//
//  StoreMigrations.swift
//  MCPStrength
//
//  What one-shot data migrations have already run against THIS store.
//
//  ## Why this is a model of its own and not a field on AppSettings
//
//  Two reasons, and the second is the load-bearing one.
//
//  **It is not a setting.** Nobody chooses it, no screen shows it, and it says
//  nothing about the user. It describes the FILE.
//
//  **It must never sync, and here that is structural rather than a comment.**
//  `AppSettings` is on its way to becoming a synced table keyed by `user_id`
//  (docs/04-status.md, item 4). A "have I converted my weights yet" flag on a
//  row shared between devices is actively dangerous: the second device pulls
//  `true` from the first, skips its own conversion, and reads a store of pounds
//  as kilograms — every lift wrong by 2.2, with no error anywhere. This model
//  does not conform to `Syncable` and has no `SyncEntity` case, so there is no
//  code path that could send it. A future author would have to add the
//  conformance on purpose.
//
//  ## Why in the store rather than in UserDefaults
//
//  UserDefaults is the usual home for a migration marker and is device-local,
//  which is most of what is wanted. It is rejected because the marker has to
//  travel WITH the store or it is lying: this project deliberately swaps store
//  files around to test SwiftData migrations (docs/04-status.md § the canary),
//  and restoring an older store under a defaults dictionary that says
//  "converted" is exactly the silent halving this file exists to prevent. A
//  marker inside the store cannot get out of step with the rows it describes.
//
//  ## The rule that makes this file dangerous
//
//  Every property needs a DECLARATION-level default (AGENTS.md rule 2). Adding
//  a model is also adding it to the `Schema` in `MCPStrengthApp`.
//

import Foundation
import SwiftData

@Model
final class StoreMigrations {

    var id: UUID = UUID()

    /// When this row was made, so `current(in:)` has a deterministic answer to
    /// "which row is the real one" rather than depending on fetch order. Same
    /// resolution rule as `AppSettings`.
    var createdAt: Date = Date.distantPast

    /// Whether every stored weight in this store has been converted from
    /// pounds to kilograms.
    ///
    /// **`false` is the safe default and that is not an accident.** A store
    /// written before this model existed comes back from lightweight migration
    /// with `false`, which is correct — its weights ARE pounds. A brand-new
    /// store also starts `false`, which is harmless: the conversion runs over
    /// zero rows and flips the flag.
    ///
    /// Getting this backwards is the one mistake with no symptom. `true` on an
    /// unconverted store skips the conversion and every weight in the app is
    /// then read as 2.2× what it was.
    var didConvertWeightsToKilograms: Bool = false

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        didConvertWeightsToKilograms: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.didConvertWeightsToKilograms = didConvertWeightsToKilograms
    }
}

extension StoreMigrations {

    /// The migration record for this store, created on first ask.
    ///
    /// The oldest row wins, same as `AppSettings.current(in:)`, so two callers
    /// racing on first launch cannot disagree about which record is
    /// authoritative. Extra rows are left alone rather than deleted.
    ///
    /// Does NOT save. The caller saves, because the whole point of the
    /// conversion is that the rows and the flag land in one write.
    static func current(in context: ModelContext) -> StoreMigrations {
        var descriptor = FetchDescriptor<StoreMigrations>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let created = StoreMigrations()
        context.insert(created)
        return created
    }
}
