//
//  HealthMeasurementRuleTests.swift
//  MCPStrengthTests
//
//  Mapping, write-plan eligibility, unit conversion, the import skip,
//  the inbound payload, which local entries Health does not yet have,
//  and both banner sentences — the whole of what can be tested without
//  a device, an entitlement and somebody's thumb on a permission sheet.
//  That is exactly why the rule is a pure function and `HealthStore` is
//  behind a protocol.
//
//  What these CANNOT cover, and what therefore has to be checked on the
//  phone once the HealthKit half is wired: the permission prompt, the write
//  itself, the observer, and whether a weigh-in actually appears in Health
//  without echoing back as a duplicate. No test here talks to HealthKit.
//

import Testing
import Foundation
import SwiftData
@testable import MCPStrength

@MainActor
struct HealthMeasurementRuleTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Exercise.self, ExercisePreference.self, TemplateFolder.self, Template.self,
            TemplateExercise.self, TemplateSet.self, ProgramDay.self,
            Workout.self, WorkoutExercise.self, WorkoutSet.self,
            MeasurementType.self, MeasurementEntry.self, AppSettings.self,
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private let recordedAt = Date(timeIntervalSince1970: 1_800_000_000)

    // Seed contract, copied from measurement-seed.json. Tests pin these
    // literals rather than `HealthMeasurementRule.bodyMassTypeID` so a
    // constant that drifts from the seed fails here.
    private static let weightID = UUID(uuidString: "d4982888-f08b-4e32-892c-4a7c36658311")!
    private static let bodyFatID = UUID(uuidString: "5725b6bb-91e7-4ce9-a68f-5f9584f43649")!
    private static let caloriesID = UUID(uuidString: "e701352b-95d1-4623-b293-e001dc0d70dc")!
    private static let waistID = UUID(uuidString: "6cc45dde-f100-48a4-852b-7d85e9d722a4")!
    private static let neckID = UUID(uuidString: "fc17fc4a-6e88-4176-9c90-c7d9c3d847fe")!

    private func insertType(
        _ id: UUID,
        name: String,
        group: MeasurementGroup = .core,
        in context: ModelContext
    ) -> MeasurementType {
        let type = MeasurementType(id: id, name: name, group: group)
        context.insert(type)
        return type
    }

    private func insertEntry(
        id: UUID = UUID(),
        value: Double,
        unit: String,
        source: MeasurementSource = .manual,
        type: MeasurementType?,
        recordedAt: Date? = nil,
        in context: ModelContext
    ) -> MeasurementEntry {
        let entry = MeasurementEntry(
            id: id,
            value: value,
            unit: unit,
            recordedAt: recordedAt ?? self.recordedAt,
            source: source,
            type: type
        )
        context.insert(entry)
        return entry
    }

    // MARK: - 1. Can this type travel?

    @Test func theFourSeedIdsMap() {
        #expect(HealthMeasurementRule.quantity(forTypeID: Self.weightID) == .bodyMass)
        #expect(HealthMeasurementRule.quantity(forTypeID: Self.bodyFatID) == .bodyFatPercentage)
        #expect(HealthMeasurementRule.quantity(forTypeID: Self.caloriesID) == .dietaryEnergyConsumed)
        #expect(HealthMeasurementRule.quantity(forTypeID: Self.waistID) == .waistCircumference)
    }

    // THE LOAD-BEARING ABSENCE for mapping. Neck is a seeded circumference
    // and HealthKit has no type for it. A "nearest" quantity (waist, say)
    // would put a neck measurement in a field whose name promises something
    // it is not.
    @Test func aNeckIdDoesNotMap() {
        #expect(HealthMeasurementRule.quantity(forTypeID: Self.neckID) == nil)
    }

    @Test func aRandomUUIDDoesNotMap() {
        #expect(HealthMeasurementRule.quantity(forTypeID: UUID()) == nil)
    }

    // Mapping is by id, never by name. A user-created type named "Weight"
    // must not travel — otherwise every custom type that happens to share a
    // seeded name would write into Health as body mass.
    @Test func mappingIsByIdNotName() throws {
        let context = try makeContext()
        let impostor = insertType(UUID(), name: "Weight", in: context)

        #expect(HealthMeasurementRule.quantity(forTypeID: impostor.id) == nil)
        #expect(impostor.name == "Weight")
    }

    // MARK: - Inverse mapping: quantity → seed type id

    // THE LOAD-BEARING SEED LITERAL. If this returned a random UUID, the
    // HealthKit layer would attach a newly created Weight type and the
    // chart would split into two Weight series.
    @Test func typeIDForBodyMassIsTheWeightSeedId() {
        #expect(HealthMeasurementRule.typeID(for: .bodyMass) == Self.weightID)
        #expect(HealthMeasurementRule.typeID(for: .bodyMass) != UUID())
    }

    @Test func everyQuantityRoundTripsThroughTypeID() {
        for quantity in HealthMeasurementQuantity.allCases {
            let id = HealthMeasurementRule.typeID(for: quantity)
            #expect(HealthMeasurementRule.quantity(forTypeID: id) == quantity)
        }
        #expect(HealthMeasurementRule.typeID(for: .bodyFatPercentage) == Self.bodyFatID)
        #expect(HealthMeasurementRule.typeID(for: .dietaryEnergyConsumed) == Self.caloriesID)
        #expect(HealthMeasurementRule.typeID(for: .waistCircumference) == Self.waistID)
    }

    // MARK: - 2. What writing looks like

    // 135 lb is the number this project keeps pinning because a wrong pounds
    // factor is silent, not a crash. Equal to `WeightUnits.kilograms`, not
    // to a hand-typed 61.23 — a second factor here would be a second
    // body-weight number in Health.
    @Test func aManualWeightOf135LbProducesCanonicalKilograms() throws {
        let context = try makeContext()
        let type = insertType(Self.weightID, name: "Weight", in: context)
        let entry = insertEntry(value: 135, unit: "lb", type: type, in: context)

        let plan = try #require(try? HealthMeasurementRule.plan(for: entry).get())

        #expect(plan.canonicalValue == WeightUnits.kilograms(from: 135, in: .lbs))
        #expect(plan.externalID == entry.id)
        #expect(plan.quantity == .bodyMass)
        #expect(plan.recordedAt == recordedAt)
    }

    // THE LOAD-BEARING CONVERSION. HealthKit's percent is a FRACTION.
    // Writing 20 would claim 2000% body fat. Pin both `== 0.2` and `!= 20`
    // so a pass-through cannot hide behind "it produced a number".
    @Test func aManualBodyFatOf20PercentProducesAFraction() throws {
        let context = try makeContext()
        let type = insertType(Self.bodyFatID, name: "Body Fat %", in: context)
        let entry = insertEntry(value: 20, unit: "%", type: type, in: context)

        let plan = try #require(try? HealthMeasurementRule.plan(for: entry).get())

        #expect(plan.canonicalValue == 0.2)
        #expect(plan.canonicalValue != 20)
        #expect(plan.quantity == .bodyFatPercentage)
        #expect(plan.externalID == entry.id)
    }

    @Test func aManualWaistOf34InProducesMeters() throws {
        let context = try makeContext()
        let type = insertType(Self.waistID, name: "Waist", group: .bodyPart, in: context)
        let entry = insertEntry(value: 34, unit: "in", type: type, in: context)

        let plan = try #require(try? HealthMeasurementRule.plan(for: entry).get())

        #expect(plan.canonicalValue == 34 * 0.0254)
        #expect(plan.quantity == .waistCircumference)
        #expect(plan.externalID == entry.id)
    }

    @Test func aManualCaloricIntakePassesThroughAsKilocalories() throws {
        let context = try makeContext()
        let type = insertType(Self.caloriesID, name: "Caloric Intake", in: context)
        let entry = insertEntry(value: 2200, unit: "kcal", type: type, in: context)

        let plan = try #require(try? HealthMeasurementRule.plan(for: entry).get())

        #expect(plan.canonicalValue == 2200)
        #expect(plan.quantity == .dietaryEnergyConsumed)
    }

    // kg is as-is, still through WeightUnits so lbs and kg cannot drift.
    @Test func aKilogramWeightIsNotConvertedAsPounds() throws {
        let context = try makeContext()
        let type = insertType(Self.weightID, name: "Weight", in: context)
        let entry = insertEntry(value: 80, unit: "kg", type: type, in: context)

        let plan = try #require(try? HealthMeasurementRule.plan(for: entry).get())

        #expect(plan.canonicalValue == WeightUnits.kilograms(from: 80, in: .kg))
        #expect(plan.canonicalValue == 80)
        #expect(plan.canonicalValue != WeightUnits.kilograms(from: 80, in: .lbs))
    }

    // MARK: - What does not go out, and WHY it does not

    // THE LOAD-BEARING ECHO SKIP on the way out. An imported sample is
    // already in Health. Writing it back is import→write→import. If this
    // were wrong, the time series would silently double.
    @Test func aHealthKitSourcedWeightIsIneligibleEvenThoughTheTypeMaps() throws {
        let context = try makeContext()
        let type = insertType(Self.weightID, name: "Weight", in: context)
        let entry = insertEntry(
            value: 135,
            unit: "lb",
            source: .healthKit,
            type: type,
            in: context
        )

        #expect(HealthMeasurementRule.quantity(forTypeID: type.id) == .bodyMass)
        #expect(HealthMeasurementRule.plan(for: entry) == .failure(.importedFromHealth))
        #expect(HealthMeasurementRule.plan(for: entry) != .failure(.cannotTravel))
    }

    @Test func aTombstonedEntryIsIneligible() throws {
        let context = try makeContext()
        let type = insertType(Self.weightID, name: "Weight", in: context)
        let entry = insertEntry(value: 135, unit: "lb", type: type, in: context)
        entry.markDeleted()

        #expect(HealthMeasurementRule.plan(for: entry) == .failure(.deleted))
    }

    // A seeded circumference with no HealthKit type. Manual source does
    // not make it travel — source is the echo skip, not a bypass of mapping.
    @Test func aNeckEntryCannotTravelEvenWhenManual() throws {
        let context = try makeContext()
        let type = insertType(Self.neckID, name: "Neck", group: .bodyPart, in: context)
        let entry = insertEntry(value: 15, unit: "in", source: .manual, type: type, in: context)

        #expect(HealthMeasurementRule.plan(for: entry) == .failure(.cannotTravel))
    }

    // AGENTS.md rule 4: a 0 kg body mass in Health is a fabricated
    // measurement in somebody else's UI. Not a sample, and not `unknownUnit`.
    @Test func aZeroValueWeightIsIneligible() throws {
        let context = try makeContext()
        let type = insertType(Self.weightID, name: "Weight", in: context)
        let entry = insertEntry(value: 0, unit: "lb", type: type, in: context)

        #expect(HealthMeasurementRule.plan(for: entry) == .failure(.nonPositiveValue))
        #expect(HealthMeasurementRule.plan(for: entry) != .failure(.unknownUnit))
    }

    @Test func anUnknownUnitIsIneligibleNotAGuessedConversion() throws {
        let context = try makeContext()
        let type = insertType(Self.weightID, name: "Weight", in: context)
        let entry = insertEntry(value: 135, unit: "stone", type: type, in: context)

        #expect(HealthMeasurementRule.plan(for: entry) == .failure(.unknownUnit))
    }

    @Test func aMissingTypeCannotTravel() throws {
        let context = try makeContext()
        let entry = insertEntry(value: 135, unit: "lb", type: nil, in: context)

        #expect(HealthMeasurementRule.plan(for: entry) == .failure(.cannotTravel))
    }

    // "Nothing to do" and "something is wrong" are different answers, and a
    // bare nil collapses them into one. A caller that cannot tell a bicep
    // from an imported weigh-in cannot report either honestly.
    @Test func theReasonsAreDistinguishableFromEachOther() throws {
        let context = try makeContext()
        let weight = insertType(Self.weightID, name: "Weight", in: context)
        let neck = insertType(Self.neckID, name: "Neck", group: .bodyPart, in: context)

        let imported = insertEntry(value: 135, unit: "lb", source: .healthKit, type: weight, in: context)
        let circumference = insertEntry(value: 15, unit: "in", type: neck, in: context)
        let zero = insertEntry(value: 0, unit: "lb", type: weight, in: context)
        let deleted = insertEntry(value: 135, unit: "lb", type: weight, in: context)
        deleted.markDeleted()

        let a = HealthMeasurementRule.plan(for: imported)
        let b = HealthMeasurementRule.plan(for: circumference)
        let c = HealthMeasurementRule.plan(for: zero)
        let d = HealthMeasurementRule.plan(for: deleted)
        #expect(a != b)
        #expect(a != c)
        #expect(a != d)
        #expect(b != c)
        #expect(b != d)
        #expect(c != d)
    }

    // MARK: - 3. Should this Health sample be imported?

    // THE LOAD-BEARING ECHO SKIP on the way in. Our writes are tagged with
    // this app as the HealthKit source. Importing them would duplicate every
    // manual weigh-in, even on the first notification before `alreadyHave`
    // has the id.
    @Test func importIsSkippedWhenTheSampleIsFromThisApp() {
        let foreign = UUID()
        let decision = HealthMeasurementRule.importDecision(
            isFromThisApp: true,
            externalID: foreign,
            alreadyHave: []
        )

        #expect(decision == .skipFromThisApp)
        #expect(decision != .allow)
        #expect(decision != .skipAlreadyHave)
    }

    @Test func importIsSkippedWhenTheExternalIdIsAlreadyHeld() {
        let id = UUID()
        let decision = HealthMeasurementRule.importDecision(
            isFromThisApp: false,
            externalID: id,
            alreadyHave: [id]
        )

        #expect(decision == .skipAlreadyHave)
        #expect(decision != .allow)
        #expect(decision != .skipFromThisApp)
    }

    @Test func importIsAllowedForAnotherSourceWhoseIdWeDoNotHave() {
        let decision = HealthMeasurementRule.importDecision(
            isFromThisApp: false,
            externalID: UUID(),
            alreadyHave: [UUID()]
        )

        #expect(decision == .allow)
    }

    // MARK: - Inverse conversion (Health canonical → seed default unit)

    // Body fat the other way: a Health fraction 0.20 becomes a stored 20,
    // not 0.20. If this were wrong the chart would show 0.2% after an import.
    @Test func localBodyFatTurnsAFractionBackIntoAPercent() {
        let local = HealthMeasurementRule.localValue(
            canonical: 0.2,
            quantity: .bodyFatPercentage
        )
        #expect(local.value == 20)
        #expect(local.value != 0.2)
        #expect(local.unit == "%")
    }

    @Test func localWeightUsesWeightUnitsPoundsFactor() {
        let kilograms = WeightUnits.kilograms(from: 135, in: .lbs)
        let local = HealthMeasurementRule.localValue(canonical: kilograms, quantity: .bodyMass)
        #expect(local.value == 135)
        #expect(local.unit == "lb")
    }

    // MARK: - What an incoming sample becomes locally

    // A scale sample: another source, no metadata UUID, sampleID not in
    // alreadyHave. Identity is Health's sample uuid. Local value is 185 lb
    // through WeightUnits, not a second pounds factor, and the type is the
    // Weight seed — not a newly created one.
    @Test func aForeignBodyMassWithNoMetadataImportsAsPoundsUsingTheSampleID() throws {
        let sampleID = UUID()
        let canonical = WeightUnits.kilograms(from: 185, in: .lbs)
        let plan = try #require(try? HealthMeasurementRule.importPlan(
            isFromThisApp: false,
            sampleID: sampleID,
            externalID: nil,
            alreadyHave: [],
            quantity: .bodyMass,
            canonicalValue: canonical,
            recordedAt: recordedAt
        ).get())

        #expect(plan.id == sampleID)
        #expect(plan.typeID == Self.weightID)
        // 185 × lb-to-kg × kg-to-lb is not bit-identical to 185 in Double.
        // The identity that matters is sampleID and the seed type; the
        // pounds round-trip is pinned exactly at 135 in
        // `localWeightUsesWeightUnitsPoundsFactor`.
        #expect((plan.local.value - 185).magnitude < 0.000_000_1)
        #expect(plan.local.unit == "lb")
        #expect(plan.quantity == .bodyMass)
        #expect(plan.recordedAt == recordedAt)
    }

    // THE LOAD-BEARING ECHO SKIP on the inbound payload. Same sample as
    // above, but tagged as this app. Skipped even when alreadyHave is
    // empty — the first notification after a write, before we have
    // recorded that we hold the id.
    @Test func aSampleFromThisAppIsNotImportedEvenWhenAlreadyHaveIsEmpty() {
        let sampleID = UUID()
        let result = HealthMeasurementRule.importPlan(
            isFromThisApp: true,
            sampleID: sampleID,
            externalID: nil,
            alreadyHave: [],
            quantity: .bodyMass,
            canonicalValue: WeightUnits.kilograms(from: 185, in: .lbs),
            recordedAt: recordedAt
        )
        #expect(result == .failure(.skipFromThisApp))
        #expect(result != .failure(.skipAlreadyHave))
        #expect(result != .failure(.nonPositiveValue))
    }

    // A scale sample we already ingested: no metadata, identity is
    // sampleID, alreadyHave contains it. Must skip — otherwise Settings
    // re-imports the same scale reading every time it appears.
    @Test func aSampleIDWeAlreadyHoldIsSkippedWhenExternalIDIsNil() {
        let sampleID = UUID()
        let result = HealthMeasurementRule.importPlan(
            isFromThisApp: false,
            sampleID: sampleID,
            externalID: nil,
            alreadyHave: [sampleID],
            quantity: .bodyMass,
            canonicalValue: WeightUnits.kilograms(from: 185, in: .lbs),
            recordedAt: recordedAt
        )
        #expect(result == .failure(.skipAlreadyHave))
        #expect(result != .failure(.skipFromThisApp))
    }

    // Metadata we already hold: identity would have been that externalID,
    // not a new one. Pin via the skip — if identity were sampleID, this
    // would have been allowed (sampleID is not in alreadyHave).
    @Test func aMetadataExternalIDWeAlreadyHoldIsSkipped() {
        let sampleID = UUID()
        let metadataID = UUID()
        let result = HealthMeasurementRule.importPlan(
            isFromThisApp: false,
            sampleID: sampleID,
            externalID: metadataID,
            alreadyHave: [metadataID],
            quantity: .bodyMass,
            canonicalValue: WeightUnits.kilograms(from: 185, in: .lbs),
            recordedAt: recordedAt
        )
        #expect(sampleID != metadataID)
        #expect(result == .failure(.skipAlreadyHave))
        #expect(result != .failure(.skipFromThisApp))
    }

    @Test func anAllowedSampleWithMetadataUsesTheMetadataUUIDAsID() throws {
        let sampleID = UUID()
        let metadataID = UUID()
        let plan = try #require(try? HealthMeasurementRule.importPlan(
            isFromThisApp: false,
            sampleID: sampleID,
            externalID: metadataID,
            alreadyHave: [],
            quantity: .bodyMass,
            canonicalValue: WeightUnits.kilograms(from: 185, in: .lbs),
            recordedAt: recordedAt
        ).get())

        #expect(plan.id == metadataID)
        #expect(plan.id != sampleID)
    }

    // A 0 kg sample is not a weigh-in. Distinct from the echo skips: a
    // Bool would collapse "our own write" with "Health sent a zero".
    @Test func aZeroCanonicalValueIsSkippedDistinguishably() {
        let result = HealthMeasurementRule.importPlan(
            isFromThisApp: false,
            sampleID: UUID(),
            externalID: nil,
            alreadyHave: [],
            quantity: .bodyMass,
            canonicalValue: 0,
            recordedAt: recordedAt
        )
        #expect(result == .failure(.nonPositiveValue))
        #expect(result != .failure(.skipFromThisApp))
        #expect(result != .failure(.skipAlreadyHave))
    }

    @Test func aNegativeCanonicalValueIsSkippedDistinguishably() {
        let result = HealthMeasurementRule.importPlan(
            isFromThisApp: false,
            sampleID: UUID(),
            externalID: nil,
            alreadyHave: [],
            quantity: .bodyMass,
            canonicalValue: -1,
            recordedAt: recordedAt
        )
        #expect(result == .failure(.nonPositiveValue))
        #expect(result != .failure(.skipFromThisApp))
        #expect(result != .failure(.skipAlreadyHave))
    }

    // Body fat the inbound way through importPlan, not just localValue:
    // Health's 0.20 becomes stored 20 %, not 0.20. If this were wrong
    // the chart would show 0.2% after tapping Add.
    @Test func bodyFatCanonicalFractionImportsAsAPercent() throws {
        let plan = try #require(try? HealthMeasurementRule.importPlan(
            isFromThisApp: false,
            sampleID: UUID(),
            externalID: nil,
            alreadyHave: [],
            quantity: .bodyFatPercentage,
            canonicalValue: 0.20,
            recordedAt: recordedAt
        ).get())

        #expect(plan.local.value == 20)
        #expect(plan.local.value != 0.20)
        #expect(plan.local.unit == "%")
        #expect(plan.typeID == Self.bodyFatID)
    }

    // A sample that fails importPlan must not appear in the batch, and
    // the survivors come back in recordedAt order even if the input is
    // reversed. Unsorted is a silent shuffle every time Settings appears.
    @Test func importPlansDropsFailuresAndOrdersByRecordedAt() {
        let earlierID = UUID()
        let laterID = UUID()
        let earlier = recordedAt
        let later = recordedAt.addingTimeInterval(3600)
        let samples = [
            HealthMeasurementSampleFacts(
                isFromThisApp: false,
                sampleID: laterID,
                externalID: nil,
                quantity: .bodyMass,
                canonicalValue: WeightUnits.kilograms(from: 185, in: .lbs),
                recordedAt: later
            ),
            HealthMeasurementSampleFacts(
                isFromThisApp: true,
                sampleID: UUID(),
                externalID: nil,
                quantity: .bodyMass,
                canonicalValue: WeightUnits.kilograms(from: 185, in: .lbs),
                recordedAt: earlier.addingTimeInterval(1)
            ),
            HealthMeasurementSampleFacts(
                isFromThisApp: false,
                sampleID: earlierID,
                externalID: nil,
                quantity: .bodyMass,
                canonicalValue: WeightUnits.kilograms(from: 185, in: .lbs),
                recordedAt: earlier
            ),
            HealthMeasurementSampleFacts(
                isFromThisApp: false,
                sampleID: UUID(),
                externalID: nil,
                quantity: .bodyMass,
                canonicalValue: 0,
                recordedAt: earlier.addingTimeInterval(2)
            ),
        ]
        let plans = HealthMeasurementRule.importPlans(from: samples, alreadyHave: [])
        #expect(plans.map(\.id) == [earlierID, laterID])
    }

    // MARK: - Which local entries Health does not yet have

    // Eligibility is plan(for:), not a second reasons list. A row plan
    // refuses cannot be "missing from Health" — the banner would offer
    // Add for a write that will refuse.
    @Test func ineligibleEntriesAreNotMissingFromHealth() throws {
        let context = try makeContext()
        let weight = insertType(Self.weightID, name: "Weight", in: context)
        let neck = insertType(Self.neckID, name: "Neck", group: .bodyPart, in: context)

        let imported = insertEntry(
            value: 135,
            unit: "lb",
            source: .healthKit,
            type: weight,
            in: context
        )
        let neckEntry = insertEntry(
            value: 15,
            unit: "in",
            source: .manual,
            type: neck,
            in: context
        )
        let tombstoned = insertEntry(value: 135, unit: "lb", type: weight, in: context)
        tombstoned.markDeleted()
        let zero = insertEntry(value: 0, unit: "lb", type: weight, in: context)

        let missing = HealthMeasurementRule.missingFromHealth(
            from: [imported, neckEntry, tombstoned, zero],
            alreadyWritten: []
        )
        #expect(missing.isEmpty)
        #expect(HealthMeasurementRule.plan(for: imported) == .failure(.importedFromHealth))
        #expect(HealthMeasurementRule.plan(for: neckEntry) == .failure(.cannotTravel))
        #expect(HealthMeasurementRule.plan(for: tombstoned) == .failure(.deleted))
        #expect(HealthMeasurementRule.plan(for: zero) == .failure(.nonPositiveValue))
    }

    @Test func aManualWeightNotInAlreadyWrittenIsMissing() throws {
        let context = try makeContext()
        let type = insertType(Self.weightID, name: "Weight", in: context)
        let entry = insertEntry(value: 135, unit: "lb", type: type, in: context)

        let missing = HealthMeasurementRule.missingFromHealth(
            from: [entry],
            alreadyWritten: []
        )
        #expect(missing.map(\.id) == [entry.id])
    }

    @Test func aManualWeightAlreadyWrittenIsNotMissing() throws {
        let context = try makeContext()
        let type = insertType(Self.weightID, name: "Weight", in: context)
        let entry = insertEntry(value: 135, unit: "lb", type: type, in: context)

        let missing = HealthMeasurementRule.missingFromHealth(
            from: [entry],
            alreadyWritten: [entry.id]
        )
        #expect(missing.isEmpty)
    }

    @Test func aWrittenIdDoesNotHideADifferentEligibleEntry() throws {
        let context = try makeContext()
        let type = insertType(Self.weightID, name: "Weight", in: context)
        let written = insertEntry(value: 135, unit: "lb", type: type, in: context)
        let other = insertEntry(value: 140, unit: "lb", type: type, in: context)

        let missing = HealthMeasurementRule.missingFromHealth(
            from: [written, other],
            alreadyWritten: [written.id]
        )
        #expect(missing.map(\.id) == [other.id])
    }

    @Test func missingEntriesComeBackInRecordedAtOrder() throws {
        let context = try makeContext()
        let type = insertType(Self.weightID, name: "Weight", in: context)
        let later = insertEntry(
            value: 140,
            unit: "lb",
            type: type,
            recordedAt: recordedAt.addingTimeInterval(3600),
            in: context
        )
        let earlier = insertEntry(
            value: 135,
            unit: "lb",
            type: type,
            recordedAt: recordedAt,
            in: context
        )

        let missing = HealthMeasurementRule.missingFromHealth(
            from: [later, earlier],
            alreadyWritten: []
        )
        #expect(missing.map(\.id) == [earlier.id, later.id])
    }

    // MARK: - Banner sentences

    @Test func zeroWritePromptIsNil() {
        #expect(HealthMeasurementRule.writePrompt(count: 0) == nil)
        #expect(HealthMeasurementRule.writePrompt(count: -1) == nil)
        #expect(HealthMeasurementRule.writePrompt(count: 0)?.contains("0") != true)
    }

    @Test func oneWritePromptIsTheSingularSentence() {
        let text = HealthMeasurementRule.writePrompt(count: 1)
        #expect(text == "1 MCP Strength measurement without a corresponding Apple Health entry. Add measurement to Apple Health?")
        #expect(text?.contains("measurements") != true)
    }

    @Test func eightWritePromptMatchesTheReferenceSentence() {
        let text = HealthMeasurementRule.writePrompt(count: 8)
        #expect(text == "8 MCP Strength measurements without corresponding Apple Health entries. Add measurements to Apple Health?")
    }

    @Test func zeroImportPromptIsNil() {
        #expect(HealthMeasurementRule.importPrompt(count: 0) == nil)
        #expect(HealthMeasurementRule.importPrompt(count: -1) == nil)
        #expect(HealthMeasurementRule.importPrompt(count: 0)?.contains("0") != true)
    }

    @Test func oneImportPromptIsTheSingularSentence() {
        let text = HealthMeasurementRule.importPrompt(count: 1)
        #expect(text == "1 additional measurement available from Apple Health. Add measurement to MCP Strength?")
        #expect(text?.contains("measurements") != true)
    }

    @Test func fourteenImportPromptMatchesTheReferenceSentence() {
        let text = HealthMeasurementRule.importPrompt(count: 14)
        #expect(text == "14 additional measurements available from Apple Health. Add measurements to MCP Strength?")
    }
}
