//
//  SyncClient.swift
//  MCPStrength
//
//  The network half of a sync run: a protocol the engine talks to, and the
//  one live conformance that hits Supabase.
//
//  ## Why a protocol at all
//
//  A transport reached only as a concrete `SupabaseClient` means the engine
//  is untestable without a live project and a real account — which is how a
//  sync engine ships that nobody has ever run. The two operations below are
//  the entire surface the engine needs; everything else (order, conflicts,
//  the dirty flag) is a pure function that already has tests.
//
//  ## Dates
//
//  Do not add a custom JSON encoder. supabase-swift's default encoder already
//  uses ISO8601 with fractional seconds, the decoder accepts either form, and
//  `Date` is a `PostgrestFilterValue` formatted the same way. Passing a `Date`
//  to `.gt(value:)` and letting the row structs carry `Date` properties both
//  work as-is. A homemade encoder is how those two would silently disagree.
//

import Foundation
import Supabase

// MARK: - Wire row

/// The three fields every pull needs, regardless of table.
///
/// `id` is how a pulled row is matched to a local model. `updatedAt` is the
/// last-write-wins key (the CLIENT's clock). `serverUpdatedAt` is the pull
/// cursor and nothing else — see docs/05-database.md § "Two timestamps".
///
/// Declared here rather than on the structs themselves so `SyncRows.swift`
/// stays a mapping file. The thirteen conformances below are the list of
/// tables the engine can actually apply.
/// NOT refined by `Sendable`, and that is forced rather than chosen. This
/// target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so the
/// row structs' SYNTHESISED `Codable` conformances are main-actor isolated
/// even though the structs themselves declare `Sendable` — and a main-actor
/// isolated conformance cannot satisfy a `Sendable` requirement on `Self`.
/// Nothing is lost: `SyncTransport` below is `@MainActor`, so a row never
/// crosses an isolation boundary on this path anyway.
protocol SyncWireRow: Codable {
    var id: UUID { get }
    var updatedAt: Date { get }
    var serverUpdatedAt: Date? { get }
}

extension SyncAppSettingsRow: SyncWireRow {}
extension SyncExerciseRow: SyncWireRow {}
extension SyncExercisePreferenceRow: SyncWireRow {}
extension SyncTemplateFolderRow: SyncWireRow {}
extension SyncTemplateRow: SyncWireRow {}
extension SyncTemplateExerciseRow: SyncWireRow {}
extension SyncTemplateSetRow: SyncWireRow {}
extension SyncProgramDayRow: SyncWireRow {}
extension SyncWorkoutRow: SyncWireRow {}
extension SyncWorkoutExerciseRow: SyncWireRow {}
extension SyncWorkoutSetRow: SyncWireRow {}
extension SyncMeasurementTypeRow: SyncWireRow {}
extension SyncMeasurementEntryRow: SyncWireRow {}

// MARK: - Transport

/// The two network operations a sync run needs.
///
/// Generic over the row structs so a fake can record and return them without
/// going through JSON, and so the live client can let supabase-swift encode
/// and decode with its own coder — the one that already knows about dates.
@MainActor
protocol SyncTransport: AnyObject {
    /// Upsert a batch into a named table. Throws if the server rejects the
    /// batch; the engine then leaves those rows dirty so they are retried.
    ///
    /// `onConflict` is the PostgREST conflict-target column list, passed
    /// in by the engine from `SyncEntity.conflictTarget`. The client must
    /// not re-derive it from the table name — a table's key is a fact the
    /// entity already knows, and looking it up here is how `"id"` got
    /// hard-coded in the first place.
    func upsert<Row: Encodable>(
        _ rows: [Row],
        into table: String,
        onConflict: String
    ) async throws

    /// One page of rows changed since `since` (`nil` means everything),
    /// oldest `server_updated_at` first.
    ///
    /// `offset` is the paging cursor. A first sync can match a large number
    /// of rows; the caller keeps requesting pages until one comes back
    /// shorter than `limit`. Offset rather than "advance since to the last
    /// timestamp" so a page break that lands inside a cluster of identical
    /// `server_updated_at` values cannot skip the rest of the cluster.
    func fetchPage<Row: Decodable>(
        _ type: Row.Type,
        from table: String,
        since: Date?,
        limit: Int,
        offset: Int
    ) async throws -> [Row]
}

extension SyncTransport {
    /// Walk pages until a short one comes back. The engine calls this; tests
    /// of the engine do not have to know about paging.
    func fetchChanged<Row: Decodable>(
        _ type: Row.Type,
        from table: String,
        since: Date?,
        pageSize: Int
    ) async throws -> [Row] {
        var all: [Row] = []
        var offset = 0
        while true {
            let page = try await fetchPage(
                type, from: table, since: since, limit: pageSize, offset: offset
            )
            all.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += page.count
        }
        return all
    }
}

// MARK: - Table names

extension SyncEntity {
    /// The Postgres table a case writes to. Snake_case, character for
    /// character as in the schema migration — not the Swift raw value,
    /// which is camelCase (`exercisePreferences` ≠ `exercise_preferences`).
    var tableName: String {
        switch self {
        case .appSettings:          "app_settings"
        case .exercises:            "exercises"
        case .exercisePreferences:  "exercise_preferences"
        case .templateFolders:      "template_folders"
        case .templates:            "templates"
        case .templateExercises:    "template_exercises"
        case .templateSets:         "template_sets"
        case .programDays:          "program_days"
        case .workouts:             "workouts"
        case .workoutExercises:     "workout_exercises"
        case .workoutSets:          "workout_sets"
        case .measurementTypes:     "measurement_types"
        case .measurementEntries:   "measurement_entries"
        }
    }

    /// The PostgREST `onConflict` target. A table's key is a fact about
    /// the table, not something a caller should have to remember, so it
    /// lives next to `tableName`.
    ///
    /// Every other synced table is keyed on `id`. These two are not:
    /// `app_settings` is one row per person (`user_id`), and
    /// `exercise_preferences` is one row per person per exercise
    /// (`user_id,exercise_id` — no spaces, that is the PostgREST spelling
    /// of a composite target). Hard-coding `"id"` in the client was what
    /// blocked both from joining the run: PostgREST rejects a conflict
    /// target that is not a unique constraint, a rejected batch aborts
    /// the WHOLE RUN, and the pull never happens either.
    var conflictTarget: String {
        switch self {
        case .appSettings:          "user_id"
        case .exercisePreferences:  "user_id,exercise_id"
        default:                    "id"
        }
    }
}

// MARK: - Live client

/// The one `SyncTransport` that talks to the hosted project.
///
/// Uses `SupabaseClientProvider.shared` so it shares the auth session with
/// `AuthController`. A second client would run a second refresh timer
/// against the same stored session.
@MainActor
final class SupabaseSyncClient: SyncTransport {

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
    }

    func upsert<Row: Encodable>(
        _ rows: [Row],
        into table: String,
        onConflict: String
    ) async throws {
        // An empty upsert is a no-op we must not send: PostgREST still
        // treats it as a write, and a Prefer: return=minimal on zero rows
        // is a request we have no reason to make.
        guard !rows.isEmpty else { return }
        try await client.from(table)
            .upsert(rows, onConflict: onConflict, returning: .minimal)
            .execute()
    }

    func fetchPage<Row: Decodable>(
        _ type: Row.Type,
        from table: String,
        since: Date?,
        limit: Int,
        offset: Int
    ) async throws -> [Row] {
        let lastIndex = offset + limit - 1
        // When `since` is nil the `.gt` filter is OMITTED, not sent as
        // "greater than now". A first sync that started from now would
        // leave every row already on the account permanently unpulled.
        if let since {
            return try await client.from(table)
                .select()
                .gt("server_updated_at", value: since)
                .order("server_updated_at", ascending: true)
                .range(from: offset, to: lastIndex)
                .execute()
                .value
        } else {
            return try await client.from(table)
                .select()
                .order("server_updated_at", ascending: true)
                .range(from: offset, to: lastIndex)
                .execute()
                .value
        }
    }
}
