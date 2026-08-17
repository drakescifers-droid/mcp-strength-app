//
//  SyncEngine.swift
//  MCPStrength
//
//  The run loop. Four phases, in this order, on purpose:
//
//      1. Claim  — refuse to re-own another account's rows
//      2. Push   — every row PushFilter allows, parents before children
//      3. Pull   — everything changed since the cursor, same order
//      4. Report — move SyncStatus
//
//  Push before pull is a decision, not an accident. A local edit that has
//  not left the device is the ONLY copy in existence; a remote edit is
//  already durable somewhere. If a run is interrupted halfway, the half
//  that ran must be the one protecting what could still be lost.
//
//  ## The echo trap
//
//  A row written by a PULL must never be marked dirty. Applying goes
//  through SyncRowApply, which settles the row clean. This file never
//  calls `markEdited()`. If it did, the next push would send everything
//  a pull just touched straight back, the server would accept it, the
//  next pull would return it, and the two ends would never settle — a
//  sync that looks extremely busy and never finishes. docs/06-sync.md.
//
//  ## What this file does not do
//
//  It does not invent an order, a filter, a conflict rule, or a cursor
//  formula. Those are `SyncPlanning`. It does not encode or decode a
//  row; that is `SyncRowMapper` / `SyncRowApply`. It does not classify
//  an error by `String(describing:)` — a URLError stringifies to a
//  domain-and-code dump that contains none of the words you would scan
//  for, and the branch silently never fires.
//

import Foundation
import Observation
import SwiftData
import os

/// A local edit last-write-wins threw away. Recorded so "my template
/// reverted" is answerable rather than spooky. The log is local; nothing
/// about a discarded edit needs to leave the device.
struct DiscardedLocalEdit: Equatable, Sendable {
    let entity: SyncEntity
    let id: UUID
    let localUpdatedAt: Date
    let remoteUpdatedAt: Date
}

/// Device-wide claim: which account this phone has already stamped local
/// rows for. Not per-user — the whole point is to compare ACROSS users.
enum SyncDeviceClaim {
    static let defaultsKey = "sync.deviceClaim.userID"
}

@MainActor
@Observable
final class SyncEngine {

    /// How many rows ride in one upsert. Small enough that a failure
    /// leaves a bounded number still dirty, large enough that a first
    /// push of a real history is not a thousand round-trips.
    static let pushBatchSize = 100

    /// How many rows one pull page asks for. A first sync on an account
    /// with years of history can match far more than this; the transport
    /// walks pages until a short one comes back.
    static let pullPageSize = 500

    private let context: ModelContext
    private let transport: any SyncTransport
    private let status: SyncStatus
    private let defaults: UserDefaults

    private var inFlight = false

    /// Discards recorded by the most recent run. Survives only in memory
    /// so a test can assert the branch fired; the durable copy is the
    /// line written to the local log (and to `Logger`) at the same time.
    private(set) var discardedEdits: [DiscardedLocalEdit] = []

    /// Ids this run actually sent. Push confirms a row with `markSynced()`
    /// BEFORE pull examines it — on purpose, so a crash between phases
    /// does not re-send a row the server already has. That leaves
    /// `needsSync` false on every dirty row this run handled, and
    /// ConflictResolver told only the flag would see a clean row and
    /// collapse every outcome to `.takeRemote`. This set is what was
    /// true before the push, carried into the pull. It is not a second
    /// dirty flag: the model column stays the source of truth for the
    /// NEXT run; this memory dies with the run.
    private var pushedThisRun: Set<UUID> = []

    private let discardLogger = Logger(
        subsystem: "us.aiagent4.MCPStrength",
        category: "sync.conflicts"
    )

    /// The underlying error behind a failed run, which `SyncState` cannot
    /// carry. Its `reason` is a sentence for a human — deliberately calm and
    /// deliberately vague — so the detail has to go somewhere else or it goes
    /// nowhere. The first real round trip failed on a PostgREST 42501 and the
    /// only way to see that was to add a temporary log; this is that log,
    /// kept.
    private let failureLogger = Logger(
        subsystem: "us.aiagent4.MCPStrength",
        category: "sync.failures"
    )

    init(
        context: ModelContext,
        transport: any SyncTransport,
        status: SyncStatus,
        defaults: UserDefaults = .standard
    ) {
        self.context = context
        self.transport = transport
        self.status = status
        self.defaults = defaults
    }

    // MARK: - Run

    /// Drive one claim → push → pull → report cycle for `userID`.
    ///
    /// A second call while one is in flight is ignored. Overlapping runs
    /// would interleave markSynced with a pull of the same rows and the
    /// echo-trap reasoning stops being locally obvious.
    func run(as userID: UUID) async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        discardedEdits = []
        pushedThisRun = []
        // Point the cursor at this account BEFORE beginRun. `adopt` reloads
        // persisted state and would otherwise overwrite `.syncing` with
        // `.never` / `.upToDate`.
        status.adopt(userID: userID)
        status.beginRun()

        do {
            try claim(for: userID)
            try await pushAll(userID: userID)
            try await pullAll()
            try reportSuccess()
        } catch let error as ClaimMismatch {
            status.failRun(reason: error.reason, pending: (try? pendingCount()) ?? 0)
        } catch {
            // The UNDERLYING error, not the sentence shown to the user.
            // `failureReason` deliberately flattens everything into something
            // reassuring ("Backup could not finish."), which is right on the
            // Profile tab and useless when a sync is failing and nobody knows
            // why. The first real round trip failed on
            // `PostgrestError(code: 42501, …)` and the app's own UI could not
            // have told anyone that; it took a temporary NSLog to find it.
            //
            // Logged, not surfaced: docs/02-architecture.md § Observability
            // asks for diagnosability, and the sentence a user reads and the
            // detail a developer needs are different artefacts.
            failureLogger.error("sync run failed: \(String(describing: error), privacy: .public)")
            status.failRun(reason: Self.failureReason(for: error), pending: (try? pendingCount()) ?? 0)
        }
    }

    // MARK: - 1. Claim
    //
    // The local models have no `user_id` field. Ownership is applied at
    // push time by SyncRowMapper's `userID:` parameter. What we CAN
    // record is which account this device has already claimed for, so a
    // later sign-in as someone else cannot silently re-stamp the first
    // person's training history as the second person's.
    //
    // docs/06-sync.md has an OPEN QUESTION about signing out with
    // unpushed changes. That decision has not been made. The only thing
    // this step is allowed to do is refuse: a device that will not sync
    // is a vastly better failure than one that hands one person's rows
    // to another.

    private struct ClaimMismatch: Error {
        let reason: String
    }

    private func claim(for userID: UUID) throws {
        if let existing = claimedUserID, existing != userID {
            throw ClaimMismatch(
                reason: "This phone is already backing up a different account."
            )
        }
        if claimedUserID == nil {
            defaults.set(userID.uuidString, forKey: SyncDeviceClaim.defaultsKey)
        }
    }

    private var claimedUserID: UUID? {
        guard let raw = defaults.string(forKey: SyncDeviceClaim.defaultsKey) else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    // MARK: - 2. Push

    private func pushAll(userID: UUID) async throws {
        // SyncEntity.allCases is the topological order. Walking it here
        // rather than a handwritten list means a new case cannot be
        // appended to the enum and then forgotten on the push path.
        for entity in SyncEntity.allCases {
            try await push(entity, userID: userID)
        }
    }

    private func push(_ entity: SyncEntity, userID: UUID) async throws {
        let table = entity.tableName
        switch entity {
        case .exercises:
            try await pushModels(
                Exercise.self, userID: userID, into: table
            ) { SyncRowMapper.row(for: $0, userID: $1) }

        case .exercisePreferences:
            // No SwiftData model and no wire struct. The table exists so
            // a later settings screen has somewhere to land; pushing it
            // now would be inventing a mapping nobody has designed.
            break

        case .templateFolders:
            try await pushModels(
                TemplateFolder.self, userID: userID, into: table
            ) { SyncRowMapper.row(for: $0, userID: $1) }

        case .templates:
            try await pushModels(
                Template.self, userID: userID, into: table
            ) { SyncRowMapper.row(for: $0, userID: $1) }

        case .templateExercises:
            try await pushModels(
                TemplateExercise.self, userID: userID, into: table
            ) { SyncRowMapper.row(for: $0, userID: $1) }

        case .templateSets:
            try await pushModels(
                TemplateSet.self, userID: userID, into: table
            ) { SyncRowMapper.row(for: $0, userID: $1) }

        case .programDays:
            try await pushModels(
                ProgramDay.self, userID: userID, into: table
            ) { SyncRowMapper.row(for: $0, userID: $1) }

        case .workouts:
            try await pushModels(
                Workout.self, userID: userID, into: table
            ) { SyncRowMapper.row(for: $0, userID: $1) }

        case .workoutExercises:
            try await pushModels(
                WorkoutExercise.self, userID: userID, into: table
            ) { SyncRowMapper.row(for: $0, userID: $1) }

        case .workoutSets:
            try await pushModels(
                WorkoutSet.self, userID: userID, into: table
            ) { SyncRowMapper.row(for: $0, userID: $1) }

        case .measurementTypes:
            try await pushModels(
                MeasurementType.self, userID: userID, into: table
            ) { SyncRowMapper.row(for: $0, userID: $1) }

        case .measurementEntries:
            try await pushModels(
                MeasurementEntry.self, userID: userID, into: table
            ) { SyncRowMapper.row(for: $0, userID: $1) }
        }
    }

    /// Fetch, filter, map, upsert, THEN markSynced — and only the rows
    /// the server confirmed. A mapper that returns nil is a child that
    /// has lost its required parent: skip it, leave it dirty, retry
    /// later. Do not invent a parent uuid.
    private func pushModels<Model: SyncIdentified, Row: Encodable>(
        _: Model.Type,
        userID: UUID,
        into table: String,
        map: (Model, UUID) -> Row?
    ) async throws {
        let models = try context.fetch(FetchDescriptor<Model>())
        var pairs: [(Model, Row)] = []
        pairs.reserveCapacity(models.count)
        for model in models {
            guard PushFilter.shouldPush(model) else { continue }
            // BACKFILL A ROW THAT WAS CREATED BUT NEVER EDITED.
            //
            // `updatedAt` defaults to `.distantPast` — "never stamped" — and
            // only `markEdited` moves it. A row that is created and then
            // pushed without ever being mutated therefore arrives at the
            // server claiming it was last modified in year 1. The first real
            // sync did exactly that: the workout carried a true timestamp
            // (Finish stamps it) and so did its set (entering a weight stamps
            // it), but the WorkoutExercise between them went up as
            // `0001-01-01 00:00:00+00`.
            //
            // That is not cosmetic. `updated_at` is the last-write-wins key,
            // so such a row LOSES every conflict it will ever have — any stale
            // edit from any device outranks it, permanently. The server's
            // far-future clamp guards the opposite direction only.
            //
            // docs/06-sync.md § "Rows that predate sign-in" already says the
            // first sync backfills these; this is that backfill. Done here
            // rather than in the model initialisers because the DECLARATION
            // default must stay `.distantPast` — a migrating store has to land
            // there honestly rather than claim it was edited at upgrade time.
            if model.updatedAt == .distantPast {
                model.updatedAt = Date()
            }
            guard let row = map(model, userID) else { continue }
            pairs.append((model, row))
        }

        var start = 0
        while start < pairs.count {
            let end = min(start + Self.pushBatchSize, pairs.count)
            let batch = Array(pairs[start..<end])
            try await transport.upsert(batch.map(\.1), into: table)
            for (model, _) in batch {
                // Record BEFORE clearing the flag. The pull reads this
                // set, not the flag, to decide whether the local row
                // still has an edit worth protecting. See `pushedThisRun`.
                pushedThisRun.insert(model.id)
                model.markSynced()
            }
            try context.save()
            start = end
        }
    }

    // MARK: - 3. Pull

    private func pullAll() async throws {
        // `pullSince` subtracts the five-second overlap. Postgres `now()`
        // is transaction-START time, so a row whose transaction began
        // before the cursor can land in the table after it. Skipping the
        // window is how a row silently never arrives.
        let since = SyncCursor.pullSince(status.cursor)

        // One dictionary per parent type, built once per run and updated
        // as new rows land. Looking each FK up with a fresh fetch is an
        // N+1; this is the alternative.
        var exercises: [UUID: Exercise] = try index()
        var folders: [UUID: TemplateFolder] = try index()
        var templates: [UUID: Template] = try index()
        var templateExercises: [UUID: TemplateExercise] = try index()
        var templateSets: [UUID: TemplateSet] = try index()
        var programDays: [UUID: ProgramDay] = try index()
        var workouts: [UUID: Workout] = try index()
        var workoutExercises: [UUID: WorkoutExercise] = try index()
        var workoutSets: [UUID: WorkoutSet] = try index()
        var measurementTypes: [UUID: MeasurementType] = try index()
        var measurementEntries: [UUID: MeasurementEntry] = try index()

        var newest: Date?

        newest = SyncCursor.advanced(
            from: newest,
            seeing: try await pull(
                Exercise.self, entity: .exercises, since: since, index: &exercises,
                make: { row in
                    Exercise(
                        id: row.id,
                        name: row.name,
                        aliases: row.aliases,
                        bodyPart: row.bodyPart,
                        category: row.category,
                        isCustom: row.isCustom,
                        focusMetric: .totalVolume
                    )
                },
                apply: { row, model in
                    SyncRowApply.apply(row, to: model)
                }
            )
        )

        // exercise_preferences: no model, no apply. See push, same reason.

        newest = SyncCursor.advanced(
            from: newest,
            seeing: try await pull(
                TemplateFolder.self, entity: .templateFolders, since: since, index: &folders,
                make: { row in
                    TemplateFolder(
                        id: row.id,
                        name: row.name,
                        order: row.sortOrder,
                        isCollapsed: row.isCollapsed,
                        kind: row.kind,
                        cursor: row.programCursor,
                        totalCycles: row.totalCycles
                    )
                },
                apply: { row, model in
                    SyncRowApply.apply(row, to: model)
                }
            )
        )

        newest = SyncCursor.advanced(
            from: newest,
            seeing: try await pull(
                Template.self, entity: .templates, since: since, index: &templates,
                make: { row in
                    Template(
                        id: row.id,
                        name: row.name,
                        note: row.note,
                        order: row.sortOrder,
                        lastPerformedAt: row.lastPerformedAt
                    )
                },
                apply: { row, model in
                    SyncRowApply.apply(
                        row, to: model,
                        folder: row.folderID.flatMap { folders[$0] }
                    )
                }
            )
        )

        newest = SyncCursor.advanced(
            from: newest,
            seeing: try await pull(
                TemplateExercise.self, entity: .templateExercises, since: since,
                index: &templateExercises,
                make: { row in
                    TemplateExercise(
                        id: row.id,
                        order: row.sortOrder,
                        supersetGroupID: row.supersetGroupID,
                        note: row.note,
                        stickyNote: row.stickyNote,
                        defaultRestSeconds: row.defaultRestSeconds
                    )
                },
                apply: { row, model in
                    SyncRowApply.apply(
                        row, to: model,
                        template: templates[row.templateID],
                        exercise: row.exerciseID.flatMap { exercises[$0] }
                    )
                }
            )
        )

        newest = SyncCursor.advanced(
            from: newest,
            seeing: try await pull(
                TemplateSet.self, entity: .templateSets, since: since,
                index: &templateSets,
                make: { row in
                    TemplateSet(
                        id: row.id,
                        order: row.sortOrder,
                        setType: row.setType,
                        weight: row.weight,
                        reps: row.reps,
                        repRangeStart: row.repRangeStart,
                        repRangeEnd: row.repRangeEnd,
                        rpe: row.rpe,
                        distance: row.distance,
                        duration: row.durationSeconds,
                        restSeconds: row.restSeconds
                    )
                },
                apply: { row, model in
                    SyncRowApply.apply(
                        row, to: model,
                        templateExercise: templateExercises[row.templateExerciseID]
                    )
                }
            )
        )

        newest = SyncCursor.advanced(
            from: newest,
            seeing: try await pull(
                ProgramDay.self, entity: .programDays, since: since,
                index: &programDays,
                make: { row in
                    ProgramDay(id: row.id, order: row.sortOrder, label: row.label)
                },
                apply: { row, model in
                    SyncRowApply.apply(
                        row, to: model,
                        folder: folders[row.folderID],
                        template: row.templateID.flatMap { templates[$0] }
                    )
                }
            )
        )

        newest = SyncCursor.advanced(
            from: newest,
            seeing: try await pull(
                Workout.self, entity: .workouts, since: since, index: &workouts,
                make: { row in
                    Workout(
                        id: row.id,
                        name: row.name,
                        startedAt: row.startedAt,
                        completedAt: row.completedAt,
                        durationSeconds: row.durationSeconds,
                        note: row.note,
                        summary: row.summary,
                        totalVolume: row.totalVolume,
                        prCount: row.prCount
                    )
                },
                apply: { row, model in
                    SyncRowApply.apply(
                        row, to: model,
                        template: row.templateID.flatMap { templates[$0] }
                    )
                }
            )
        )

        newest = SyncCursor.advanced(
            from: newest,
            seeing: try await pull(
                WorkoutExercise.self, entity: .workoutExercises, since: since,
                index: &workoutExercises,
                make: { row in
                    WorkoutExercise(
                        id: row.id,
                        order: row.sortOrder,
                        supersetGroupID: row.supersetGroupID,
                        note: row.note,
                        stickyNote: row.stickyNote,
                        defaultRestSeconds: row.defaultRestSeconds
                    )
                },
                apply: { row, model in
                    SyncRowApply.apply(
                        row, to: model,
                        workout: workouts[row.workoutID],
                        exercise: row.exerciseID.flatMap { exercises[$0] }
                    )
                }
            )
        )

        newest = SyncCursor.advanced(
            from: newest,
            seeing: try await pull(
                WorkoutSet.self, entity: .workoutSets, since: since,
                index: &workoutSets,
                make: { row in
                    WorkoutSet(
                        id: row.id,
                        order: row.sortOrder,
                        setType: row.setType,
                        weight: row.weight,
                        reps: row.reps,
                        rpe: row.rpe,
                        distance: row.distance,
                        duration: row.durationSeconds,
                        restSeconds: row.restSeconds,
                        isCompleted: row.isCompleted,
                        completedAt: row.completedAt
                    )
                },
                apply: { row, model in
                    SyncRowApply.apply(
                        row, to: model,
                        workoutExercise: workoutExercises[row.workoutExerciseID]
                    )
                }
            )
        )

        newest = SyncCursor.advanced(
            from: newest,
            seeing: try await pull(
                MeasurementType.self, entity: .measurementTypes, since: since,
                index: &measurementTypes,
                make: { row in
                    MeasurementType(
                        id: row.id,
                        name: row.name,
                        group: row.groupKind,
                        sortOrder: row.sortOrder
                    )
                },
                apply: { row, model in
                    SyncRowApply.apply(row, to: model)
                }
            )
        )

        newest = SyncCursor.advanced(
            from: newest,
            seeing: try await pull(
                MeasurementEntry.self, entity: .measurementEntries, since: since,
                index: &measurementEntries,
                make: { row in
                    MeasurementEntry(
                        id: row.id,
                        value: row.value,
                        unit: row.unit,
                        recordedAt: row.recordedAt,
                        source: row.source
                    )
                },
                apply: { row, model in
                    SyncRowApply.apply(
                        row, to: model,
                        type: row.typeID.flatMap { measurementTypes[$0] }
                    )
                }
            )
        )

        // Advance ONCE, at the end, from the newest server_updated_at
        // actually seen — never the local clock, and never mid-pull. A
        // crash halfway through must re-read everything, not skip the
        // tables that had not run yet. An empty pull leaves the cursor
        // where it was (`advanced` with a nil `seeing`).
        status.cursor = SyncCursor.advanced(from: status.cursor, seeing: newest)
    }

    /// Apply every pulled row of one type. Returns the newest
    /// `serverUpdatedAt` in the page so the caller can advance the
    /// global cursor; returns nil when the page was empty.
    private func pull<Model: SyncIdentified, Row: SyncWireRow>(
        _: Model.Type,
        entity: SyncEntity,
        since: Date?,
        index: inout [UUID: Model],
        make: (Row) -> Model,
        apply: (Row, Model) -> Void
    ) async throws -> Date? {
        let rows = try await transport.fetchChanged(
            Row.self, from: entity.tableName, since: since, pageSize: Self.pullPageSize
        )
        var newest: Date?
        for row in rows {
            newest = SyncCursor.advanced(from: newest, seeing: row.serverUpdatedAt)
            if let existing = index[row.id] {
                // The flag alone is a lie by this point: every row this
                // run confirmed has already been markSynced. Dirtiness
                // for THIS pull is the flag OR membership in the set
                // push filled — what was true before the push. The
                // resolver stays the decision; we just stop lying to it.
                // `updatedAt` is untouched by markSynced, so that
                // argument is still the local edit's real time.
                // `PushFilter.shouldPush`, not the raw `needsSync` flag. A row
                // the filter will NEVER send cannot be holding a local edit
                // worth protecting, whatever its flag says — and the seeded
                // library says `true` forever, because it is excluded from
                // every push so nothing ever calls markSynced on it.
                //
                // Read naively, the first sync of a fresh install logged 43
                // discarded edits: 25 seeded exercises and 18 seeded
                // measurement types, every one with
                // `updatedAt == .distantPast`, which is the "never stamped"
                // default and the opposite of an edit. Nothing was discarded.
                // The discard log exists so "my template reverted" is
                // answerable, and 43 fabricated entries on day one is exactly
                // the kind of noise that makes a log worth ignoring.
                //
                // "Would we push it, or did we?" is the honest question.
                let localIsDirty = PushFilter.shouldPush(existing)
                    || pushedThisRun.contains(existing.id)
                switch ConflictResolver.resolve(
                    localUpdatedAt: existing.updatedAt,
                    localIsDirty: localIsDirty,
                    remoteUpdatedAt: row.updatedAt
                ) {
                case .keepLocal:
                    // Newer (or tied) local edit. Leave the row as-is.
                    // If this run already confirmed it, it is clean and
                    // must stay clean — flipping the flag back on would
                    // resend the same row on every subsequent run. If it
                    // never left the device (PushFilter, a failed encode)
                    // the flag is still set and the next run will retry.
                    continue
                case .takeRemoteDiscardingLocalEdit:
                    // Last-write-wins is throwing away a real user edit.
                    // Distinct from ordinary overwrite so this is
                    // diagnosable. docs/06-sync.md § Conflicts.
                    recordDiscard(
                        entity: entity,
                        id: row.id,
                        localUpdatedAt: existing.updatedAt,
                        remoteUpdatedAt: row.updatedAt
                    )
                    apply(row, existing)
                case .takeRemote:
                    apply(row, existing)
                }
            } else {
                let created = make(row)
                context.insert(created)
                apply(row, created)
                index[row.id] = created
            }
        }
        if !rows.isEmpty {
            try context.save()
        }
        return newest
    }

    // MARK: - 4. Report

    private func reportSuccess() throws {
        let pending = try pendingCount()
        if pending > 0 {
            // Still waiting — usually a child whose parent has not
            // encoded, or an unfinished workout PushFilter is holding
            // back. Not a failure.
            status.finishRun(pending: pending)
        } else {
            status.finishRun(at: .now)
        }
    }

    // MARK: - Lookups

    private func index<Model: SyncIdentified>() throws -> [UUID: Model] {
        let rows = try context.fetch(FetchDescriptor<Model>())
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    private func pendingCount() throws -> Int {
        var rows: [any Syncable] = []
        rows.append(contentsOf: try context.fetch(FetchDescriptor<Exercise>()))
        rows.append(contentsOf: try context.fetch(FetchDescriptor<TemplateFolder>()))
        rows.append(contentsOf: try context.fetch(FetchDescriptor<Template>()))
        rows.append(contentsOf: try context.fetch(FetchDescriptor<TemplateExercise>()))
        rows.append(contentsOf: try context.fetch(FetchDescriptor<TemplateSet>()))
        rows.append(contentsOf: try context.fetch(FetchDescriptor<ProgramDay>()))
        rows.append(contentsOf: try context.fetch(FetchDescriptor<Workout>()))
        rows.append(contentsOf: try context.fetch(FetchDescriptor<WorkoutExercise>()))
        rows.append(contentsOf: try context.fetch(FetchDescriptor<WorkoutSet>()))
        rows.append(contentsOf: try context.fetch(FetchDescriptor<MeasurementType>()))
        rows.append(contentsOf: try context.fetch(FetchDescriptor<MeasurementEntry>()))
        return PushFilter.pendingCount(rows)
    }

    // MARK: - Discard log

    private func recordDiscard(
        entity: SyncEntity,
        id: UUID,
        localUpdatedAt: Date,
        remoteUpdatedAt: Date
    ) {
        let entry = DiscardedLocalEdit(
            entity: entity,
            id: id,
            localUpdatedAt: localUpdatedAt,
            remoteUpdatedAt: remoteUpdatedAt
        )
        discardedEdits.append(entry)

        // Durable enough to answer "my template reverted" after a
        // relaunch, local enough that nothing about the discarded edit
        // leaves the phone.
        let line = "discarded \(entity.rawValue) \(id.uuidString) local=\(localUpdatedAt.timeIntervalSince1970) remote=\(remoteUpdatedAt.timeIntervalSince1970)"
        var lines = defaults.stringArray(forKey: Self.discardLogKey) ?? []
        lines.append(line)
        defaults.set(lines, forKey: Self.discardLogKey)

        discardLogger.warning("\(line, privacy: .public)")
    }

    private static let discardLogKey = "sync.discardedEdits"

    // MARK: - Errors
    //
    // Match on the TYPE. A URLError stringifies to
    // `URLError(_nsError: Error Domain=NSURLErrorDomain Code=-1009 "(null)")`
    // and contains none of the words a string scan would look for, so that
    // branch can never fire and every offline user gets a message that is
    // both useless and false.

    /// Offline-class URLError codes: retrying later genuinely works.
    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .networkConnectionLost,
        .timedOut,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed,
        .internationalRoamingOff,
        .dataNotAllowed,
        .secureConnectionFailed,
    ]

    /// A sentence for a human, never an error dump. The safety line
    /// ("workouts are still on this phone") is appended by
    /// `SyncState.detail` — putting it in the reason as well would
    /// print it twice on the Profile card.
    static func failureReason(for error: any Error) -> String {
        if let urlError = error as? URLError, offlineCodes.contains(urlError.code) {
            return "No connection."
        }
        // supabase-swift sometimes boxes the transport error rather than
        // rethrowing the URLError. Still a typed check — the domain
        // constant, not a word in the description.
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let code = URLError.Code(rawValue: nsError.code)
            if offlineCodes.contains(code) {
                return "No connection."
            }
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? URLError,
           offlineCodes.contains(underlying.code) {
            return "No connection."
        }
        return "Backup could not finish."
    }
}

// MARK: - Identity

/// The models the engine can look up by the client UUID they were
/// created with. Declared here so `Models/*.swift` does not have to
/// know they participate in a dictionary.
private protocol SyncIdentified: PersistentModel, Syncable {
    var id: UUID { get }
}

extension Exercise: SyncIdentified {}
extension TemplateFolder: SyncIdentified {}
extension Template: SyncIdentified {}
extension TemplateExercise: SyncIdentified {}
extension TemplateSet: SyncIdentified {}
extension ProgramDay: SyncIdentified {}
extension Workout: SyncIdentified {}
extension WorkoutExercise: SyncIdentified {}
extension WorkoutSet: SyncIdentified {}
extension MeasurementType: SyncIdentified {}
extension MeasurementEntry: SyncIdentified {}
