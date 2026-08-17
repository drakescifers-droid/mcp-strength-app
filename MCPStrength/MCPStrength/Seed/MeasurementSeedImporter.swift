//
//  MeasurementSeedImporter.swift
//  MCPStrength
//
//  Loads the seeded measurement-type library (`Resources/measurement-seed.json`) into a
//  SwiftData ModelContext. Mirrors `ExerciseSeedImporter`: a JSON resource with literal UUIDs,
//  a pure importer core taking decoded rows plus a ModelContext, a thin bundle-loading
//  convenience layer, and an idempotent upsert matching on `id`.
//
//  See docs/01-data-model.md § Measurements for the type set (CORE vs BODY PART).
//

import Foundation
import SwiftData

/// One row of the seed file. Mirrors the JSON shape: `id`, `name`, `group`, `unit`,
/// and `sortOrder`. `id` is a literal UUID baked into the file — it is never generated
/// at import time (see the seeded-IDs contract below).
struct MeasurementSeedRow: Codable, Sendable, Equatable {
    let id: UUID
    let name: String
    let group: MeasurementGroup
    let unit: String
    let sortOrder: Int
}

/// Imports seed rows into a SwiftData `ModelContext`.
///
/// The design splits a PURE, TESTABLE core from a thin bundle-loading convenience layer —
/// identical in shape to `ExerciseSeedImporter`:
///
/// - `importRows(_:into:)` — the entire upsert algorithm. Takes decoded `[MeasurementSeedRow]`
///   plus a `ModelContext` and nothing else. Tests drive this directly with fixture rows and an
///   in-memory container; they never touch bundle plumbing.
/// - `loadBundledSeed(into:)` / `decodeBundledRows()` — a thin convenience that finds the JSON in
///   the app bundle, decodes it, and hands the rows to the core.
///
/// ## The seeded-IDs contract
///
/// Seeded UUIDs are a permanent contract. Every `MeasurementEntry` points at its type by id, so
/// a re-seed that hands a type a new UUID orphans that measurement's entire history. So:
///
///   * IDs are literal values baked into the seed file.
///   * The importer never calls `UUID()` for a seeded row — it reads the id straight from the row.
///   * Re-import matches on `id`, never on `name`.
///
/// ## Import behavior
///
///   * IDEMPOTENT — importing the same set twice creates no duplicates. Existing rows are matched
///     by `id` and updated in place; nothing new is inserted.
///   * STABLE IDS — a type imported twice keeps the id from the seed file, both times.
///   * ADDITIVE UPGRADE — a seed set that has gained a new row adds only that new row and leaves
///     existing ones untouched.
///   * NON-DESTRUCTIVE — the importer never deletes anything; a type the user recorded against
///     keeps its entries regardless of re-import.
///   * Library-defined fields refreshed on a match: `name`, `group`, `sortOrder`. `sortOrder`
///     is included so a re-seed can correct the list order of types that already exist.
///
/// ## Default unit
///
/// `MeasurementType` carries no `unit` field (the unit lives on each `MeasurementEntry`). The
/// seed file is therefore the single source of truth for a type's DEFAULT unit — the unit a new
/// manual entry is recorded with. `defaultUnit(for:)` resolves it from the bundled rows so the
/// record sheet can show the type's unit without a model change.
enum MeasurementSeedImporter {

    // MARK: - Core (pure / testable)

    /// Idempotently upserts `rows` into `context`, matching on `id`.
    ///
    /// - Returns: The ids of the rows handled, in input order.
    @discardableResult
    static func importRows(_ rows: [MeasurementSeedRow], into context: ModelContext) throws -> [UUID] {
        // Fetch existing types once and index by id for O(1) lookup. Matching on id (not name)
        // is the whole point of the seeded-IDs contract.
        let existing = try context.fetch(FetchDescriptor<MeasurementType>())
        var byID: [UUID: MeasurementType] = [:]
        byID.reserveCapacity(existing.count)
        for type in existing {
            byID[type.id] = type
        }

        var handled: [UUID] = []
        handled.reserveCapacity(rows.count)

        for row in rows {
            if let type = byID[row.id] {
                // Existing row: update library-defined fields in place. The id is untouched
                // (stability). sortOrder is refreshed so a re-seed can correct the list
                // order of types that already exist — the reason the field is on the model
                // rather than derived from name. The unit is not stored on the model (see
                // "Default unit" above).
                type.name = row.name
                type.group = row.group
                type.sortOrder = row.sortOrder
            } else {
                // New row: insert with the literal id from the seed file. Never UUID().
                let type = MeasurementType(
                    id: row.id,
                    name: row.name,
                    group: row.group,
                    sortOrder: row.sortOrder
                )
                context.insert(type)
                byID[row.id] = type
            }
            handled.append(row.id)
        }

        try context.save()
        return handled
    }

    // MARK: - Default unit lookup

    /// Returns the default unit for the seeded type with `typeID`, read from the bundled seed
    /// file. Returns nil for a type id that is not in the seed (e.g. a user-created type) or if
    /// the bundled seed cannot be read. The result is not cached: the seed is small, and the
    /// record sheet is not a hot path.
    static func defaultUnit(for typeID: UUID) -> String? {
        guard let rows = try? decodeBundledRows() else { return nil }
        return rows.first { $0.id == typeID }?.unit
    }

    /// The ids of every SEEDED measurement type, for `PushFilter`.
    ///
    /// ## Why this exists, and what it cost to find out
    ///
    /// Seeded measurement types live in TWO places by design: local SwiftData
    /// rows, and global Postgres rows with `user_id IS NULL`, sharing these
    /// baked UUIDs (docs/06-sync.md § "The seeded library exists twice").
    /// `needsSync` defaults to `true` on every `@Model`, so without a filter
    /// the engine pushes all of them as USER data. PostgREST turns an upsert
    /// on an existing id into an UPDATE, and `measurement_types_update`'s
    /// `USING (user_id = auth.uid())` refuses it because the row it would
    /// replace is owned by nobody:
    ///
    ///     42501 — new row violates row-level security policy
    ///             (USING expression) for table "measurement_types"
    ///
    /// That is the policy doing its job, and it aborts THE ENTIRE RUN — push
    /// stops, pull never happens, and every subsequent sync fails the same
    /// way. It was the first thing a real round trip hit, and no test caught
    /// it because a fake transport accepts anything.
    ///
    /// `06-sync.md` predicted exactly this and named measurement types
    /// alongside exercises — *"filter rather than discover"* — but only the
    /// exercise half was built. `Exercise` carries `isCustom`; `MeasurementType`
    /// has no equivalent field, so the seed file is the discriminator instead.
    ///
    /// Deriving it from the seed rather than adding a model property is
    /// deliberate: a new `@Model` property means a SwiftData migration on a
    /// store that already has rows, which is the most expensive mistake in
    /// this codebase (docs/04-status.md). It is also self-maintaining — a type
    /// added to the seed becomes non-pushable automatically, and a
    /// user-created type, whose UUID is not in the file, pushes without anyone
    /// having to remember to flag it.
    ///
    /// Cached: `PushFilter` consults this once per model per run, and re-reading
    /// and re-decoding a bundled file that many times is pointless work.
    static let seededIDs: Set<UUID> = {
        guard let rows = try? decodeBundledRows() else {
            // An unreadable seed makes every type look user-created, which
            // would push the seeded ones and break sync exactly as above. The
            // app already treats a failed seed import as non-fatal, so match
            // that: an empty set is wrong in the SAFE direction only if the
            // seed is also absent locally, which is the same failure.
            assertionFailure("measurement seed unreadable; seeded ids unavailable")
            return []
        }
        return Set(rows.map(\.id))
    }()

    // MARK: - Convenience (bundle plumbing)

    /// Loads the bundled `measurement-seed.json` and imports it into `context`. Thin wrapper
    /// around the pure core — all logic lives in `importRows(_:into:)`.
    static func loadBundledSeed(into context: ModelContext) throws {
        let rows = try decodeBundledRows()
        try importRows(rows, into: context)
    }

    /// Finds and decodes the bundled seed file. Looks in the app bundle for a resource named
    /// `measurement-seed` with extension `json`.
    static func decodeBundledRows() throws -> [MeasurementSeedRow] {
        guard let url = Bundle.main.url(forResource: "measurement-seed", withExtension: "json") else {
            throw SeedError.bundledSeedMissing
        }
        let data = try Data(contentsOf: url)
        return try decodeRows(data)
    }

    /// Decodes seed rows from raw JSON data. Supports both a top-level array form and an object
    /// form with a `measurements` array, per the seed-file spec.
    static func decodeRows(_ data: Data) throws -> [MeasurementSeedRow] {
        let decoder = JSONDecoder()
        // Peek at the first non-whitespace byte to pick the shape without swallowing decode
        // errors from the wrong branch. JSON whitespace is just space/tab/LF/CR (RFC 8259).
        let jsonWhitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
        if let first = data.first(where: { !jsonWhitespace.contains($0) }) {
            if first == 0x5B { // '[' — top-level array form
                return try decoder.decode([MeasurementSeedRow].self, from: data)
            }
        }
        // Otherwise the object form: { "measurements": [ ... ] }
        return try decoder.decode(SeedFile.self, from: data).measurements
    }

    enum SeedError: Error, Equatable {
        case bundledSeedMissing
    }

    /// Wrapper for the `{"measurements": [...]}` object form of the seed file.
    private struct SeedFile: Codable {
        let measurements: [MeasurementSeedRow]
    }
}
