//
//  ExerciseSeedImporter.swift
//  MCPStrength
//
//  Loads the seeded exercise library (`Resources/exercise-seed.json`) into a SwiftData
//  ModelContext. The seeded library is the integrity constraint for the whole app: it is
//  what stops every AI-generated plan from inventing its own names and history fragments
//  across "Lateral Raise (Machine)" / "Machine Lateral Raise" / "Lat Raise".
//
//  See docs/01-data-model.md § "The seeded library" for the contract.
//

import Foundation
import SwiftData

/// One row of the seed file. Mirrors the JSON shape: `id`, `name`, `bodyPart`, `category`,
/// and an optional `aliases` array. `id` is a literal UUID baked into the file — it is never
/// generated at import time (see the seeded-IDs contract below).
struct ExerciseSeedRow: Codable, Sendable, Equatable {
    let id: UUID
    let name: String
    let bodyPart: BodyPart
    let category: ExerciseCategory
    let aliases: [String]?
    /// Body parts trained beyond `bodyPart` — Deadlift is `bodyPart: .back,
    /// secondaryBodyParts: [.legs]`. Optional in the JSON, like `aliases`,
    /// so the many rows that only train one body part need no key at all;
    /// absent decodes to empty, same as `aliases ?? []` below.
    let secondaryBodyParts: [BodyPart]?
}

/// Imports seed rows into a SwiftData `ModelContext`.
///
/// The design splits a PURE, TESTABLE core from a thin bundle-loading convenience layer:
///
/// - `import(rows:into:)` — the entire upsert algorithm. Takes decoded `[ExerciseSeedRow]` plus
///   a `ModelContext` and nothing else. Tests drive this directly with fixture rows and an
///   in-memory container; they never touch bundle plumbing.
/// - `loadBundledSeed(into:)` / `decodeBundledRows()` — a thin convenience that finds the JSON
///   in the app bundle, decodes it, and hands the rows to the core. App code uses this; tests do
///   not have to.
///
/// ## The seeded-IDs contract (the one property that cannot be got wrong)
///
/// Seeded UUIDs are a permanent contract. Every workout ever logged points at an exercise by
/// `id`. If the library is re-seeded later — new exercises in v1.2, a typo fixed, a better list
/// imported — and an existing exercise comes back with a NEW UUID, every user's history for that
/// movement silently detaches from it. So:
///
///   * IDs are literal values baked into the seed file.
///   * The importer never calls `UUID()` for a seeded row — it reads the id straight from the row.
///   * Re-import matches on `id`, never on `name`.
///
/// There is no good fix after the fact. Cheap on day one; impossible later.
///
/// ## Import behavior
///
///   * IDEMPOTENT — importing the same set twice creates no duplicates. Existing rows are
///     matched by `id` and updated in place; nothing new is inserted.
///   * STABLE IDS — an exercise imported twice keeps the id from the seed file, both times.
///   * ADDITIVE UPGRADE — a seed set that has gained a new row adds only that new row and leaves
///     existing ones untouched.
///   * NON-DESTRUCTIVE — exercises the user created (`isCustom == true`) have their own
///     runtime-generated ids that never collide with the baked seed ids, so they are never
///     matched and survive a re-import untouched. The importer never deletes anything.
///   * Seeded rows are written with `isCustom == false`.
///
/// ## When a seeded row's NAME changes but its id stays the same
///
/// THE ID WINS, and the name is updated in place. This is exactly why ids are the contract: a
/// corrected name must not orphan the history attached to that id. The same in-place update
/// applies to `bodyPart`, `secondaryBodyParts`, `category`, and `aliases` — the library-defined fields.
///
/// For an existing matched (seeded) row, only the library-defined fields are refreshed
/// (`name`, `bodyPart`, `secondaryBodyParts`, `category`, `aliases`). Per-user preferences live on a
/// different model (`ExercisePreference`) and a re-seed cannot touch them: they
/// are a different row entirely, so the preservation logic is not lost, it is
/// structurally unnecessary.
enum ExerciseSeedImporter {

    // MARK: - Core (pure / testable)

    /// Idempotently upserts `rows` into `context`, matching on `id`.
    ///
    /// - Returns: The ids of the rows handled, in input order.
    @discardableResult
    static func importRows(_ rows: [ExerciseSeedRow], into context: ModelContext) throws -> [UUID] {
        // Fetch existing exercises once and index by id for O(1) lookup. Matching on id (not
        // name) is the whole point of the seeded-IDs contract.
        let existing = try context.fetch(FetchDescriptor<Exercise>())
        var byID: [UUID: Exercise] = [:]
        byID.reserveCapacity(existing.count)
        for exercise in existing {
            byID[exercise.id] = exercise
        }

        var handled: [UUID] = []
        handled.reserveCapacity(rows.count)

        for row in rows {
            let aliases = row.aliases ?? []
            let secondaryBodyParts = row.secondaryBodyParts ?? []
            if let exercise = byID[row.id] {
                // Existing row: update library-defined fields in place. The id is untouched
                // (stability). A preference is a different row and is not in scope
                // here, so a re-seed cannot rewrite one. A name change with the same
                // id is applied here: the id wins.
                exercise.name = row.name
                exercise.aliases = aliases
                exercise.bodyPart = row.bodyPart
                exercise.secondaryBodyParts = secondaryBodyParts
                exercise.category = row.category
                exercise.isCustom = false
            } else {
                // New row: insert with the literal id from the seed file. Never UUID().
                let exercise = Exercise(
                    id: row.id,
                    name: row.name,
                    aliases: aliases,
                    bodyPart: row.bodyPart,
                    secondaryBodyParts: secondaryBodyParts,
                    category: row.category,
                    isCustom: false
                )
                context.insert(exercise)
                byID[row.id] = exercise
            }
            handled.append(row.id)
        }

        try context.save()
        return handled
    }

    // MARK: - Convenience (bundle plumbing)

    /// Loads the bundled `exercise-seed.json` and imports it into `context`. Thin wrapper around
    /// the pure core — all logic lives in `importRows(_:into:)`.
    static func loadBundledSeed(into context: ModelContext) throws {
        let rows = try decodeBundledRows()
        try importRows(rows, into: context)
    }

    /// Finds and decodes the bundled seed file. Looks in the app bundle for a resource named
    /// `exercise-seed` with extension `json`.
    static func decodeBundledRows() throws -> [ExerciseSeedRow] {
        guard let url = Bundle.main.url(forResource: "exercise-seed", withExtension: "json") else {
            throw SeedError.bundledSeedMissing
        }
        let data = try Data(contentsOf: url)
        return try decodeRows(data)
    }

    /// Decodes seed rows from raw JSON data. Supports both a top-level array form and an object
    /// form with an `exercises` array, per the seed-file spec.
    static func decodeRows(_ data: Data) throws -> [ExerciseSeedRow] {
        let decoder = JSONDecoder()
        // Peek at the first non-whitespace byte to pick the shape without swallowing decode
        // errors from the wrong branch. JSON whitespace is just space/tab/LF/CR (RFC 8259).
        let jsonWhitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
        if let first = data.first(where: { !jsonWhitespace.contains($0) }) {
            if first == 0x5B { // '[' — top-level array form
                return try decoder.decode([ExerciseSeedRow].self, from: data)
            }
        }
        // Otherwise the object form: { "exercises": [ ... ] }
        return try decoder.decode(SeedFile.self, from: data).exercises
    }

    enum SeedError: Error, Equatable {
        case bundledSeedMissing
    }

    /// Wrapper for the `{"exercises": [...]}` object form of the seed file.
    private struct SeedFile: Codable {
        let exercises: [ExerciseSeedRow]
    }
}
