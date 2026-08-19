//
//  SyncEngineTests.swift
//  MCPStrengthTests
//
//  The engine against a fake transport. No live project, no account, no
//  network. A suite that only runs against production is a suite nobody
//  runs, and this is the layer whose failure mode is silent data loss.
//

import Testing
import Foundation
import SwiftData
@testable import MCPStrength

@MainActor
struct SyncEngineTests {

    private let user = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let otherUser = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Harness

    private func makeDefaults() -> UserDefaults {
        let suite = "SyncEngineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Exercise.self, ExercisePreference.self, TemplateFolder.self, Template.self,
            TemplateExercise.self, TemplateSet.self, ProgramDay.self,
            Workout.self, WorkoutExercise.self, WorkoutSet.self,
            MeasurementType.self, MeasurementEntry.self,
            AppSettings.self,
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private func makeEngine(
        context: ModelContext,
        transport: FakeSyncTransport,
        defaults: UserDefaults? = nil
    ) -> (SyncEngine, SyncStatus) {
        let isolated = defaults ?? makeDefaults()
        let status = SyncStatus(defaults: isolated)
        let engine = SyncEngine(
            context: context,
            transport: transport,
            status: status,
            defaults: isolated
        )
        return (engine, status)
    }

    // MARK: - 1. PushFilter is the gate

    @Test func pushSendsOnlyWhatPushFilterAllows() async throws {
        // An unfinished workout (and everything under it) is a draft, not a
        // record of training. A seeded exercise is global library, not user
        // data. Sending either would be the filter failing at the only place
        // it can still fail: the engine walking past it.
        let context = try makeContext()
        let transport = FakeSyncTransport()

        let seeded = Exercise(
            name: "Bench Press (Barbell)", bodyPart: .chest,
            category: .barbell, isCustom: false
        )
        let custom = Exercise(
            name: "Reverse Nordic", bodyPart: .legs,
            category: .repsOnly, isCustom: true
        )
        let live = Workout(name: "In progress")
        let liveExercise = WorkoutExercise(order: 0, workout: live)
        let liveSet = WorkoutSet(order: 0, weight: 135, reps: 5, workoutExercise: liveExercise)
        let done = Workout(name: "Finished")
        done.completedAt = base
        let folder = TemplateFolder(name: "Q2 2026", order: 0)

        for row: any PersistentModel in [seeded, custom, live, liveExercise, liveSet, done, folder] {
            context.insert(row)
        }

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        let sentExercises = transport.upserted(SyncExerciseRow.self, from: "exercises")
        #expect(sentExercises.map(\.id) == [custom.id], "a seeded exercise left the device")

        let sentWorkouts = transport.upserted(SyncWorkoutRow.self, from: "workouts")
        #expect(sentWorkouts.map(\.id) == [done.id], "an unfinished workout left the device")

        #expect(transport.upserted(SyncWorkoutExerciseRow.self, from: "workout_exercises").isEmpty)
        #expect(transport.upserted(SyncWorkoutSetRow.self, from: "workout_sets").isEmpty)

        let sentFolders = transport.upserted(SyncTemplateFolderRow.self, from: "template_folders")
        #expect(sentFolders.map(\.id) == [folder.id])
    }

    // MARK: - 2. Confirmed push clears the flag

    @Test func aConfirmedPushClearsNeedsSyncOnExactlyTheRowsThatWereSent() async throws {
        let context = try makeContext()
        let transport = FakeSyncTransport()

        let sent = TemplateFolder(name: "Sent", order: 0)
        let held = Workout(name: "Still a draft")
        context.insert(sent)
        context.insert(held)
        #expect(sent.needsSync)
        #expect(held.needsSync)

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        #expect(sent.needsSync == false, "a confirmed row stayed dirty")
        #expect(held.needsSync == true, "an unsent draft was marked clean")
        #expect(transport.upserted(SyncTemplateFolderRow.self, from: "template_folders").count == 1)
        #expect(transport.upserted(SyncWorkoutRow.self, from: "workouts").isEmpty)
    }

    // MARK: - 3. Failed push leaves the flag — the whole design

    @Test func aFailedPushLeavesNeedsSyncSet() async throws {
        // If only one test in this file survives, it is this one. The
        // explicit flag exists so a push that throws does not pretend the
        // row arrived. Clearing it here is silent data loss: the next run
        // thinks the row is backed up, the UI agrees, and the only copy
        // is on a phone that may never push it again.
        let context = try makeContext()
        let transport = FakeSyncTransport()
        transport.upsertError = URLError(.notConnectedToInternet)

        let folder = TemplateFolder(name: "Q2 2026", order: 0)
        context.insert(folder)
        #expect(folder.needsSync)

        let (engine, status) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        #expect(folder.needsSync == true, "a failed push cleared needsSync")
        #expect(status.state == .failed(count: 1, reason: "No connection."))
    }

    @Test func aFailedPushDoesNotClearLaterRowsInTheSameBatchEither() async throws {
        // markSynced runs only AFTER the batch returns. A throw mid-upsert
        // must leave every row in that batch dirty, not just the one that
        // happened to be last in the array.
        let context = try makeContext()
        let transport = FakeSyncTransport()
        transport.upsertError = URLError(.timedOut)

        let a = TemplateFolder(name: "A", order: 0)
        let b = TemplateFolder(name: "B", order: 1)
        context.insert(a)
        context.insert(b)

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        #expect(a.needsSync)
        #expect(b.needsSync)
    }

    // MARK: - 4. Cursor

    @Test func theCursorAdvancesToTheNewestServerUpdatedAtSeen() async throws {
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let older = base
        let newer = base.addingTimeInterval(60)
        transport.seed([
            folderRow(id: UUID(), name: "Older", serverUpdatedAt: older),
            folderRow(id: UUID(), name: "Newer", serverUpdatedAt: newer),
        ], into: "template_folders")

        let (engine, status) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        #expect(status.cursor == newer, "the cursor did not take the newest server time")
    }

    @Test func anEmptyPullLeavesTheCursorUnchanged() async throws {
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let defaults = makeDefaults()
        let (engine, status) = makeEngine(context: context, transport: transport, defaults: defaults)

        // First run plants the cursor from a real page.
        transport.seed([
            folderRow(id: UUID(), name: "Planted", serverUpdatedAt: base),
        ], into: "template_folders")
        await engine.run(as: user)
        #expect(status.cursor == base)

        // Second run sees nothing. Mixing in the device clock here is how
        // a cursor drifts past rows it never received.
        transport.canned.removeAll()
        await engine.run(as: user)
        #expect(status.cursor == base)
    }

    @Test func aFirstPullAsksForEverything() async throws {
        // A first sync that started from "now" would leave every row
        // already on the account permanently unpulled.
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        #expect(!transport.fetchCalls.isEmpty)
        for call in transport.fetchCalls {
            #expect(call.since == nil, "\(call.table) was filtered from a date on a first pull")
        }
    }

    @Test func aLaterPullSendsTheOverlapWindow() async throws {
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let defaults = makeDefaults()
        let (engine, status) = makeEngine(context: context, transport: transport, defaults: defaults)
        status.adopt(userID: user)
        status.cursor = base

        await engine.run(as: user)

        let expected = SyncCursor.pullSince(base)
        #expect(expected == base.addingTimeInterval(-SyncCursor.overlap))
        for call in transport.fetchCalls {
            #expect(call.since == expected, "\(call.table) skipped the overlap window")
        }
    }

    // MARK: - 5. Conflicts
    //
    // Dirtiness for a pull is `needsSync || pushedThisRun`. Push runs first
    // and a confirmed upsert calls markSynced(), so the flag alone would
    // tell ConflictResolver every row this run sent is clean — and both
    // `.keepLocal` and `.takeRemoteDiscardingLocalEdit` would collapse to
    // `.takeRemote`. The set carries what was true before the push.

    @Test func aNewerDirtyLocalRowSurvivesAPull() async throws {
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let id = UUID()

        let local = TemplateFolder(id: id, name: "Local edit", order: 0)
        local.updatedAt = base.addingTimeInterval(60)
        local.needsSync = true
        context.insert(local)

        transport.seed([
            folderRow(id: id, name: "Remote older", updatedAt: base, serverUpdatedAt: base.addingTimeInterval(120)),
        ], into: "template_folders")

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        #expect(local.name == "Local edit")
        // The content assertion is the point. needsSync is false because
        // this run already confirmed the push — leaving the row dirty
        // would resend it on every subsequent run, forever.
        #expect(local.needsSync == false)
        #expect(engine.discardedEdits.isEmpty)
    }

    @Test func anOlderDirtyLocalRowLosesAndIsLogged() async throws {
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let id = UUID()

        let local = TemplateFolder(id: id, name: "Local older", order: 0)
        local.updatedAt = base
        local.needsSync = true
        context.insert(local)

        let remoteAt = base.addingTimeInterval(60)
        transport.seed([
            folderRow(id: id, name: "Remote newer", updatedAt: remoteAt, serverUpdatedAt: remoteAt),
        ], into: "template_folders")

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        #expect(local.name == "Remote newer")
        #expect(local.needsSync == false)
        // `#expect` RECORDS and continues, so a bare `discardedEdits[0]` after a
        // failed count assertion traps on an empty array and takes the whole
        // test PROCESS down — every other test in the suite included. Unwrap
        // first: one red test is a result, a crashed runner is no result at all.
        #expect(engine.discardedEdits.count == 1)
        let discarded = try #require(engine.discardedEdits.first)
        #expect(discarded.id == id)
        #expect(discarded.localUpdatedAt == base)
        #expect(discarded.remoteUpdatedAt == remoteAt)
    }

    @Test func aCleanLocalRowTakesTheRemoteEvenWhenTheRemoteIsOlder() async throws {
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let id = UUID()

        let local = TemplateFolder(id: id, name: "Clean copy", order: 0)
        local.updatedAt = base.addingTimeInterval(60)
        local.markSynced()
        context.insert(local)

        transport.seed([
            folderRow(id: id, name: "Older remote", updatedAt: base, serverUpdatedAt: base),
        ], into: "template_folders")

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        #expect(local.name == "Older remote")
        #expect(local.needsSync == false)
        #expect(engine.discardedEdits.isEmpty, "a clean overwrite is not a discarded edit")
    }

    @Test func aRowPushedThisRunThenSupersededByANewerRemoteIsLogged() async throws {
        // The discard path after a push: the flag is already clear, so
        // without pushedThisRun this would be an ordinary takeRemote and
        // the log would stay silent. Both timestamps have to be on the
        // entry — "my template reverted" is unanswerable with only one.
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let id = UUID()
        let localAt = base
        let remoteAt = base.addingTimeInterval(60)

        let local = TemplateFolder(id: id, name: "Sent then overwritten", order: 0)
        local.updatedAt = localAt
        local.needsSync = true
        context.insert(local)

        transport.seed([
            folderRow(id: id, name: "Newer elsewhere", updatedAt: remoteAt, serverUpdatedAt: remoteAt),
        ], into: "template_folders")

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        #expect(transport.upserted(SyncTemplateFolderRow.self, from: "template_folders").map(\.id) == [id])
        #expect(local.name == "Newer elsewhere")
        #expect(engine.discardedEdits.count == 1)
        let discarded = try #require(engine.discardedEdits.first)
        #expect(discarded.id == id)
        #expect(discarded.entity == .templateFolders)
        #expect(discarded.localUpdatedAt == localAt)
        #expect(discarded.remoteUpdatedAt == remoteAt)
    }

    @Test func aSuccessfulPushWhoseRowComesBackUnchangedLogsNothing() async throws {
        // The false-positive guard worth having: a confirmed push whose
        // echo lands in the same pull (same id, same updatedAt) is not a
        // discarded edit. Ties go to local, and nothing is logged.
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let id = UUID()

        let local = TemplateFolder(id: id, name: "Mine", order: 0)
        local.updatedAt = base
        local.needsSync = true
        context.insert(local)

        transport.seed([
            folderRow(id: id, name: "Mine", updatedAt: base, serverUpdatedAt: base),
        ], into: "template_folders")

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        #expect(transport.upserted(SyncTemplateFolderRow.self, from: "template_folders").map(\.id) == [id])
        #expect(local.name == "Mine")
        #expect(local.needsSync == false)
        #expect(engine.discardedEdits.isEmpty, "an unchanged echo is not a discarded edit")
    }

    @Test func anAcceptedPushThenANewerRemoteStillLogsADiscard() async throws {
        // Tension (a): we do not ask the server what it actually accepted.
        // FakeSyncTransport (and the live client) treat a non-throwing
        // upsert as success, so this run cannot tell "the guard kept a
        // newer row" from "our write landed and another device then won".
        // The second case is a false log entry. We accept that: the log
        // is local, the case is rare, and returning every upsert body to
        // suppress it is more machinery than a diagnostic line is worth.
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let id = UUID()
        let localAt = base
        let remoteAt = base.addingTimeInterval(90)

        let local = TemplateFolder(id: id, name: "Accepted locally", order: 0)
        local.updatedAt = localAt
        local.needsSync = true
        context.insert(local)

        transport.seed([
            folderRow(id: id, name: "Later winner", updatedAt: remoteAt, serverUpdatedAt: remoteAt),
        ], into: "template_folders")

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        #expect(!transport.upserted(SyncTemplateFolderRow.self, from: "template_folders").isEmpty)
        #expect(engine.discardedEdits.count == 1)
        let discarded = try #require(engine.discardedEdits.first)
        #expect(discarded.localUpdatedAt == localAt)
        #expect(discarded.remoteUpdatedAt == remoteAt)
    }

    // MARK: - 6. Echo trap

    @Test func aPullDoesNotDirtyTheRowsItTouched() async throws {
        // Asserted directly, not inferred from "the next push sent nothing".
        // That weaker form would also pass if the push filter were broken.
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let id = UUID()
        transport.seed([
            folderRow(id: id, name: "From server", serverUpdatedAt: base),
        ], into: "template_folders")

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        let pulled = try #require(context.fetch(FetchDescriptor<TemplateFolder>()).first { $0.id == id })
        #expect(pulled.needsSync == false)
        #expect(pulled.name == "From server")
        #expect(pulled.updatedAt == base)
    }

    @Test func aSecondRunDoesNotEchoAPulledRowBack() async throws {
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let id = UUID()
        transport.seed([
            folderRow(id: id, name: "From server", serverUpdatedAt: base),
        ], into: "template_folders")

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)
        transport.upsertCalls.removeAll()
        transport.canned.removeAll()

        await engine.run(as: user)
        #expect(transport.upserted(SyncTemplateFolderRow.self, from: "template_folders").isEmpty)
    }

    // MARK: - Foreign keys

    @Test func aPulledChildResolvesItsParentFromTheBatchedIndex() async throws {
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let folderID = UUID()
        let templateID = UUID()
        transport.seed([
            folderRow(id: folderID, name: "Push Pull", serverUpdatedAt: base),
        ], into: "template_folders")
        transport.seed([
            SyncTemplateRow(
                id: templateID,
                userID: user,
                name: "Push A",
                folderID: folderID,
                note: nil,
                sortOrder: 0,
                lastPerformedAt: nil,
                updatedAt: base,
                deletedAt: nil,
                serverUpdatedAt: base
            ),
        ], into: "templates")

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        let template = try #require(context.fetch(FetchDescriptor<Template>()).first { $0.id == templateID })
        #expect(template.folder?.id == folderID)
        #expect(template.needsSync == false)
    }

    // MARK: - Claim

    @Test func aFreshDeviceClaimsTheSignedInUserAndPushes() async throws {
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let folder = TemplateFolder(name: "Q2 2026", order: 0)
        context.insert(folder)

        let defaults = makeDefaults()
        let (engine, _) = makeEngine(context: context, transport: transport, defaults: defaults)
        await engine.run(as: user)

        #expect(defaults.string(forKey: SyncDeviceClaim.defaultsKey) == user.uuidString)
        #expect(!transport.upserted(SyncTemplateFolderRow.self, from: "template_folders").isEmpty)
    }

    @Test func aDifferentAccountIsRefusedAndNothingIsPushed() async throws {
        // Handing one person's training history to another is the worst
        // bug this design can permit. The store has no user_id field, so
        // the only defence is this device-wide claim.
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let folder = TemplateFolder(name: "Someone else's", order: 0)
        context.insert(folder)

        let defaults = makeDefaults()
        defaults.set(otherUser.uuidString, forKey: SyncDeviceClaim.defaultsKey)

        let (engine, status) = makeEngine(context: context, transport: transport, defaults: defaults)
        await engine.run(as: user)

        #expect(transport.upsertCalls.isEmpty, "a foreign claim still pushed")
        #expect(transport.fetchCalls.isEmpty, "a foreign claim still pulled")
        #expect(folder.needsSync == true)
        #expect(status.state == .failed(
            count: 1,
            reason: "This phone is already backing up a different account."
        ))
        #expect(defaults.string(forKey: SyncDeviceClaim.defaultsKey) == otherUser.uuidString)
    }

    // MARK: - Error classification

    @Test func aURLErrorIsNotClassifiedByItsDescription() {
        // The string contains none of "network", "offline", or "connection".
        // Matching on the type is the whole lesson of the shipped bug.
        let error = URLError(.notConnectedToInternet)
        #expect(!String(describing: error).localizedCaseInsensitiveContains("network"))
        #expect(SyncEngine.failureReason(for: error) == "No connection.")
    }

    @Test func aNonOfflineURLErrorIsNotCalledAConnectionFailure() {
        let error = URLError(.badServerResponse)
        #expect(SyncEngine.failureReason(for: error) == "Backup could not finish.")
    }

    // A server that explained its own refusal must have that sentence REACH
    // the user.
    //
    // This is the 2026-08-19 outage as a test. PostgREST answered `permission
    // denied for table app_settings` — naming the table and the cause — and
    // the account card said "Backup could not finish." The real message had to
    // be dug out of the project's server logs, and the app had it in hand the
    // whole time.
    //
    // Conforming a stub here rather than importing the SDK's error is the point
    // of `ServerRefusal` existing: the engine matches its OWN protocol, so this
    // is testable with no network, no account and no Supabase types.
    @Test func aServerRefusalCarriesTheServersOwnSentence() {
        struct Refusal: ServerRefusal {
            let serverMessage: String
        }
        let error = Refusal(serverMessage: "permission denied for table app_settings")
        #expect(
            SyncEngine.failureReason(for: error)
                == "The server refused it: permission denied for table app_settings"
        )
    }

    // Offline still wins over the server-refusal branch, because a URLError is
    // not a refusal and "No connection." is both truer and more actionable.
    @Test func offlineStillOutranksEverythingElse() {
        #expect(SyncEngine.failureReason(for: URLError(.timedOut)) == "No connection.")
    }

    // MARK: - Orphaned children

    @Test func aChildThatCannotBeEncodedIsLeftDirty() async throws {
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let orphan = TemplateSet(order: 0)
        context.insert(orphan)
        #expect(SyncRowMapper.row(for: orphan, userID: user) == nil)

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        #expect(orphan.needsSync == true)
        #expect(transport.upserted(SyncTemplateSetRow.self, from: "template_sets").isEmpty)
    }


    // MARK: - Seeded rows are not "edits"

    @Test func pullingTheSeededLibraryLogsNoDiscardedEdits() async throws {
        // THE FIRST SYNC OF A FRESH INSTALL LOGGED 43 DISCARDED EDITS, all of
        // them fabricated. Seeded rows keep needsSync == true forever — they
        // are excluded from every push, so markSynced never runs on them — and
        // their updatedAt is .distantPast, the "never stamped" default. Read as
        // "dirty with a very old edit", every one loses last-write-wins and
        // gets recorded as a discard. Nothing was discarded. The log exists so
        // "my template reverted" is answerable; 43 false entries on day one is
        // how a log becomes noise.
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let id = UUID()

        let seeded = Exercise(
            id: id, name: "Bench Press (Barbell)", bodyPart: .chest,
            category: .barbell, isCustom: false
        )
        #expect(seeded.needsSync, "a seeded row starts dirty and nothing ever clears it")
        #expect(seeded.updatedAt == .distantPast, "and it has never been stamped")
        context.insert(seeded)

        transport.seed([
            exerciseRow(id: id, name: "Bench Press (Barbell)",
                        updatedAt: base, serverUpdatedAt: base),
        ], into: "exercises")

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        #expect(engine.discardedEdits.isEmpty,
                "a row PushFilter will never send cannot be holding an edit worth discarding")
        #expect(seeded.name == "Bench Press (Barbell)")
        #expect(seeded.needsSync == false, "the pull settles it clean")
    }

    @Test func aCustomExerciseSupersededByANewerRemoteIsStillLogged() async throws {
        // The counterpart, and the reason the seeded fix has to be narrow: a
        // CUSTOM exercise IS pushable, so when a newer remote overtakes it the
        // discard is real and must still be recorded. Same shape as the test
        // above, one field different — isCustom.
        //
        // The push must SUCCEED here. A failing push aborts the run before the
        // pull (docs/06-sync.md § The shape), so there is no pull to resolve a
        // conflict against and nothing could be logged either way.
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let id = UUID()

        let mine = Exercise(
            id: id, name: "Reverse Nordic", bodyPart: .legs,
            category: .repsOnly, isCustom: true
        )
        mine.updatedAt = base
        context.insert(mine)

        let newer = base.addingTimeInterval(60)
        transport.seed([
            exerciseRow(id: id, name: "Renamed elsewhere",
                        updatedAt: newer, serverUpdatedAt: newer),
        ], into: "exercises")

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        #expect(engine.discardedEdits.count == 1,
                "a pushable row overtaken by a newer remote IS a real discard")
        #expect(mine.name == "Renamed elsewhere", "last-write-wins should have taken the remote")
    }

    // MARK: - Never-stamped rows

    @Test func aRowCreatedButNeverEditedIsStampedBeforeItIsPushed() async throws {
        // FOUND IN THE FIRST REAL ROUND TRIP. `updatedAt` defaults to
        // .distantPast ("never stamped") and only markEdited moves it, so a row
        // that is created and pushed without ever being mutated reached the
        // server as 0001-01-01. The WorkoutExercise did exactly that, sitting
        // between a workout and a set that both carried real timestamps.
        //
        // updated_at is the last-write-wins key, so such a row loses every
        // conflict it will ever have, to anything, forever.
        let context = try makeContext()
        let transport = FakeSyncTransport()

        let folder = TemplateFolder(name: "Untouched", order: 0)
        context.insert(folder)
        #expect(folder.updatedAt == .distantPast, "created, never edited")

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        let sent = transport.upserted(SyncTemplateFolderRow.self, from: "template_folders")
        #expect(sent.count == 1)
        #expect(sent.first?.updatedAt != .distantPast,
                "a never-stamped row went up claiming it was last edited in year 1")
        #expect(folder.updatedAt != .distantPast, "and the local row keeps the backfilled stamp")
    }

    @Test func backfillDoesNotOverwriteARealEditTimestamp() async throws {
        let context = try makeContext()
        let transport = FakeSyncTransport()

        let folder = TemplateFolder(name: "Edited", order: 0)
        folder.markEdited(at: base)
        context.insert(folder)

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        let sent = transport.upserted(SyncTemplateFolderRow.self, from: "template_folders")
        #expect(sent.first?.updatedAt == base, "backfill clobbered a genuine edit time")
    }

    // MARK: - Settings: the two hazards

    @Test func anUntouchedSettingsRowIsNotPushedAndIsNotBackfilled() async throws {
        // HAZARD TWO. A fresh install's settings row is dirty, full of
        // defaults, and stamped distantPast. Pushing it would overwrite a
        // real choice made on another device: pushModels backfills
        // distantPast to now, that now wins last-write-wins, and both
        // devices revert. The filter has to hold it, AND the backfill
        // must not run on a row the filter held back.
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let settings = AppSettings()
        context.insert(settings)
        #expect(settings.updatedAt == .distantPast)
        #expect(settings.needsSync)

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        #expect(transport.upserted(SyncAppSettingsRow.self, from: "app_settings").isEmpty)
        #expect(settings.needsSync == true, "an unsent defaults row was marked clean")
        #expect(settings.updatedAt == .distantPast, "backfill stamped a row the filter held back")
    }

    @Test func anEditedSettingsRowIsPushed() async throws {
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let settings = AppSettings()
        settings.setWeightUnit(.kg)
        context.insert(settings)
        #expect(settings.updatedAt != .distantPast)

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        let sent = transport.upserted(SyncAppSettingsRow.self, from: "app_settings")
        #expect(sent.count == 1)
        #expect(sent.first?.weightUnit == .kg)
        #expect(sent.first?.userID == user)
        #expect(settings.needsSync == false)
    }

    @Test func pullingSettingsDoesNotCreateASecondRow() async throws {
        // HAZARD ONE. Drake's phone already holds an AppSettings row
        // with a random UUID. The server identifies settings by user_id.
        // Matching on id would treat the remote as new and insert a
        // second row; current() then reads whichever happened to be
        // older, and the unit choice appears to revert at random.
        let context = try makeContext()
        let transport = FakeSyncTransport()

        let local = AppSettings(weightUnit: .lbs)
        #expect(local.id != user, "the local id must not coincidentally be the user id")
        context.insert(local)
        #expect(try context.fetch(FetchDescriptor<AppSettings>()).count == 1)

        transport.seed([
            SyncAppSettingsRow(
                userID: user,
                weightUnit: .kg,
                measurementWeightUnit: .kg,
                distanceUnit: .kilometers,
                sizeUnit: .centimeters,
                defaultRestSeconds: 120,
                weekStartDay: 2,
                workoutCalorieRate: .high,
                writeWorkoutsToHealth: true,
                writeMeasurementsToHealth: true,
                readMeasurementsFromHealth: true,
                theme: "dark",
                language: "en",
                previousSetBehavior: "lastTime",
                updatedAt: base,
                deletedAt: nil,
                serverUpdatedAt: base
            ),
        ], into: "app_settings")

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        let all = try context.fetch(FetchDescriptor<AppSettings>())
        #expect(all.count == 1, "settings pull inserted a second row")
        let current = AppSettings.current(in: context)
        #expect(current.id == local.id, "values did not land on the existing current() row")
        #expect(current.weightUnit == .kg)
        #expect(current.measurementWeightUnit == .kg)
        #expect(current.distanceUnit == .kilometers)
        #expect(current.sizeUnit == .centimeters)
        #expect(current.defaultRestSeconds == 120)
        #expect(current.weekStartDay == 2)
        #expect(current.theme == "dark")
        #expect(current.language == "en")
        #expect(current.previousSetBehavior == "lastTime")
        #expect(current.needsSync == false)
        #expect(current.updatedAt == base)
    }

    @Test func pullingAPreferenceMatchesTheLocalRowByExerciseID() async throws {
        // The counterpart of the settings hazard: preference local id
        // IS the exercise's id, so the generic index must hit and must
        // not insert a second row.
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let exercise = Exercise(
            name: "Bench Press", bodyPart: .chest, category: .barbell, isCustom: false
        )
        context.insert(exercise)
        let preference = ExercisePreference(
            id: exercise.id, barType: .olympicBar, exercise: exercise
        )
        preference.markEdited(at: base.addingTimeInterval(-60))
        preference.markSynced()
        context.insert(preference)

        transport.seed([
            SyncExercisePreferenceRow(
                userID: user,
                exerciseID: exercise.id,
                weightUnitOverride: .kg,
                barType: .trapBar,
                focusMetric: .totalReps,
                notes: "paused",
                updatedAt: base,
                deletedAt: nil,
                serverUpdatedAt: base
            ),
        ], into: "exercise_preferences")

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        let all = try context.fetch(FetchDescriptor<ExercisePreference>())
        #expect(all.count == 1)
        let pulled = try #require(all.first)
        #expect(pulled.id == exercise.id)
        #expect(pulled.barType == .trapBar)
        #expect(pulled.weightUnitOverride == .kg)
        #expect(pulled.focusMetric == .totalReps)
        #expect(pulled.notes == "paused")
        #expect(pulled.needsSync == false)
        #expect(pulled.exercise?.id == exercise.id)
    }

    @Test func aNewerDirtySettingsRowSurvivesAPull() async throws {
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let local = AppSettings(weightUnit: .kg)
        local.markEdited(at: base.addingTimeInterval(60))
        context.insert(local)

        transport.seed([
            SyncAppSettingsRow(
                userID: user,
                weightUnit: .lbs,
                measurementWeightUnit: .lbs,
                distanceUnit: .miles,
                sizeUnit: .inches,
                defaultRestSeconds: 90,
                weekStartDay: 1,
                workoutCalorieRate: .medium,
                writeWorkoutsToHealth: true,
                writeMeasurementsToHealth: true,
                readMeasurementsFromHealth: true,
                theme: nil,
                language: nil,
                previousSetBehavior: nil,
                updatedAt: base,
                deletedAt: nil,
                serverUpdatedAt: base.addingTimeInterval(120)
            ),
        ], into: "app_settings")

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        #expect(try context.fetch(FetchDescriptor<AppSettings>()).count == 1)
        #expect(AppSettings.current(in: context).weightUnit == .kg)
        #expect(engine.discardedEdits.isEmpty)
    }

    @Test func anOlderDirtySettingsRowLosesAndIsLogged() async throws {
        let context = try makeContext()
        let transport = FakeSyncTransport()
        let local = AppSettings(weightUnit: .lbs)
        local.markEdited(at: base)
        context.insert(local)

        let remoteAt = base.addingTimeInterval(60)
        transport.seed([
            SyncAppSettingsRow(
                userID: user,
                weightUnit: .kg,
                measurementWeightUnit: .lbs,
                distanceUnit: .miles,
                sizeUnit: .inches,
                defaultRestSeconds: 90,
                weekStartDay: 1,
                workoutCalorieRate: .medium,
                writeWorkoutsToHealth: true,
                writeMeasurementsToHealth: true,
                readMeasurementsFromHealth: true,
                theme: nil,
                language: nil,
                previousSetBehavior: nil,
                updatedAt: remoteAt,
                deletedAt: nil,
                serverUpdatedAt: remoteAt
            ),
        ], into: "app_settings")

        let (engine, _) = makeEngine(context: context, transport: transport)
        await engine.run(as: user)

        #expect(try context.fetch(FetchDescriptor<AppSettings>()).count == 1)
        #expect(AppSettings.current(in: context).weightUnit == .kg)
        #expect(engine.discardedEdits.count == 1)
        let discarded = try #require(engine.discardedEdits.first)
        #expect(discarded.entity == .appSettings)
        #expect(discarded.id == local.id)
        #expect(discarded.localUpdatedAt == base)
        #expect(discarded.remoteUpdatedAt == remoteAt)
    }

    // MARK: - Row fixtures

    private func folderRow(
        id: UUID,
        name: String,
        updatedAt: Date? = nil,
        serverUpdatedAt: Date?
    ) -> SyncTemplateFolderRow {
        SyncTemplateFolderRow(
            id: id,
            userID: user,
            name: name,
            sortOrder: 0,
            isCollapsed: false,
            kind: .folder,
            programCursor: 0,
            totalCycles: nil,
            updatedAt: updatedAt ?? serverUpdatedAt ?? base,
            deletedAt: nil,
            serverUpdatedAt: serverUpdatedAt
        )
    }

    private func exerciseRow(
        id: UUID,
        name: String,
        isCustom: Bool = false,
        updatedAt: Date? = nil,
        serverUpdatedAt: Date?
    ) -> SyncExerciseRow {
        SyncExerciseRow(
            id: id,
            userID: isCustom ? user : nil,
            name: name,
            aliases: [],
            bodyPart: .chest,
            secondaryBodyParts: [],
            category: .barbell,
            isCustom: isCustom,
            updatedAt: updatedAt ?? serverUpdatedAt ?? base,
            deletedAt: nil,
            serverUpdatedAt: serverUpdatedAt
        )
    }
}

// MARK: - Fake transport

@MainActor
final class FakeSyncTransport: SyncTransport {

    var upsertCalls: [(table: String, rows: [any Encodable])] = []
    var fetchCalls: [(table: String, since: Date?, limit: Int, offset: Int)] = []
    var canned: [String: Any] = [:]
    var upsertError: (any Error)?

    func seed<Row>(_ rows: [Row], into table: String) {
        canned[table] = rows
    }

    func upserted<Row>(_ type: Row.Type, from table: String) -> [Row] {
        upsertCalls
            .filter { $0.table == table }
            .flatMap { $0.rows.compactMap { $0 as? Row } }
    }

    func upsert<Row: Encodable>(
        _ rows: [Row],
        into table: String,
        onConflict: String
    ) async throws {
        if let upsertError { throw upsertError }
        upsertCalls.append((table, rows))
        _ = onConflict
    }

    func fetchPage<Row: Decodable>(
        _ type: Row.Type,
        from table: String,
        since: Date?,
        limit: Int,
        offset: Int
    ) async throws -> [Row] {
        fetchCalls.append((table, since, limit, offset))
        // All canned rows on the first page, nothing after — tests seed
        // far fewer than the engine's page size, so this is the same
        // shape a short last page has in production.
        if offset > 0 { return [] }
        return (canned[table] as? [Row]) ?? []
    }
}
