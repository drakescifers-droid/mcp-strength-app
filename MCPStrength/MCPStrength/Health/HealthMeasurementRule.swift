//
//  HealthMeasurementRule.swift
//  MCPStrength
//
//  Which body measurements can travel to Apple Health, what a manual entry
//  becomes in Health's units, which incoming Health samples must be
//  skipped so a write does not echo back as a duplicate, what an allowed
//  sample becomes locally, which local entries Health does not yet have,
//  and the two yellow-banner sentences that offer Add.
//
//  Same split as `HealthWorkoutRule` versus `HealthStore`, and for the same
//  reason: the decisions are where data is silently lost or duplicated, and
//  they are testable here with no HKHealthStore, no entitlement, and no
//  permission prompt. Quantity kinds are an enum this file owns. The HealthKit
//  layer switches on it to pick `HKQuantityTypeIdentifier`. Importing
//  HealthKit here to "complete" the mapping would put the untestable half
//  back into the testable one.
//
//  ## Decisions, kept separate
//
//  1. **Can this type travel?** A function of a type id. Only four of the
//     eighteen seeded types exist in HealthKit. Names are not the key — a
//     user-created type named "Weight" must not travel.
//  2. **What is the inverse?** A Health quantity → the seeded type UUID.
//     The HealthKit layer attaches that existing Weight type, not a newly
//     created one. Separate from (1) so the two can round-trip without
//     the write plan growing a type-id field it does not need.
//  3. **What would writing this entry look like?** Eligibility (tombstone,
//     imported-from-Health, unmapped type, non-positive value, unknown unit)
//     plus the conversion into Health's canonical unit.
//  4. **Should this Health sample be imported?** Skip vs allow, from
//     `isFromThisApp`, optional `externalID`, and `alreadyHave`. Skipping
//     is the load-bearing half of the echo loop.
//  5. **What does an allowed sample become locally?** Identity, seeded
//     type, local value — and refuse a fabricated zero. Sit beside (4),
//     do not grow it: skip-vs-allow is one question; "what to store,
//     including refuse a zero" is another. A Bool would collapse "our
//     own write" with "Health sent a zero".
//  6. **Which local entries does Health not yet have?** The write banner.
//     Eligibility is `plan(for:)`, not a second reasons list. A row
//     `plan` refuses cannot be "missing from Health".
//  7. **The two banner sentences**, each from a count. Separate from the
//     counting functions so a bug in one cannot write a matching lie in
//     the other. Count 0 is `nil`, not `"0 …"` (AGENTS.md rule 4).
//
//  Collapsing them into one function would make "this is a bicep" and "this
//  was imported from Health" the same sentence, and they are not. Workouts
//  already went out one-way and so could not echo. Measurements are
//  bidirectional, so the loop is possible: write a weight to Health → Health
//  notifies → the app imports its own write as a new entry → duplicates
//  forever. The failure mode is a silently doubling time series.
//
//  ## Closing the echo loop
//
//  Two skips, one on each side, and both are required:
//
//    * **On the way OUT:** a `.healthKit`-sourced entry is ineligible. Health
//      already has it; writing it back is the first half of the loop.
//    * **On the way IN:** a sample whose source is this app (`isFromThisApp`)
//      is not imported. Our writes are tagged; importing them would
//      duplicate every manual weigh-in.
//
//  Either skip alone is not enough. Out-only still imports our writes as
//  new `.healthKit` rows (a second time series next to the manual one).
//  In-only still writes those imported rows back, and Health notifies again.
//  Together they settle.
//
//  The entry's own id goes into `HKMetadataKeyExternalUUID`, the same trick
//  as workouts: the writer can ask Health whether it already has this id,
//  and the importer can skip a sample whose external UUID we already hold.
//  No `didWriteToHealth` column — that would be a stored property on a
//  synced model, it would need a Postgres column to travel, and it would
//  still be WRONG across devices because Health syncs through iCloud.
//
//  ## Samples with no metadata still close
//
//  A scale sample has no `HKMetadataKeyExternalUUID`. Identity is then
//  HealthKit's own `HKObject.uuid` (`sampleID`):
//
//      id = externalID ?? sampleID
//
//  That id becomes `MeasurementEntry.id`. The next scan, `alreadyHave`
//  contains it and we skip. Passing the *resolved* id into `importDecision`
//  is load-bearing: that function treats a nil `externalID` as "not
//  already held", so a scale sample would otherwise re-import every time
//  Settings appeared. Our own writes still have `isFromThisApp == true`
//  even when metadata is missing, so they skip on the first notification
//  before `alreadyHave` has the id. And a `.healthKit` row never goes
//  back out, so the inbound id cannot bounce.
//
//  ## Only four types, and the mapping is by id
//
//  Weight, Body Fat %, Caloric Intake, Waist. The other fourteen are limb
//  and torso circumferences and HealthKit has no type for any of them.
//  There is no "nearest" quantity: putting a bicep in `waistCircumference`
//  would put a number in a field whose name promises something it is not.
//
//  ## Percent is a fraction
//
//  HealthKit's percent unit is 0...1. This app stores 20 for 20%. Writing
//  20 into Health would claim 2000% body fat. That conversion is
//  load-bearing, and it is why the write plan carries the canonical value
//  rather than the stored one.
//
//  ## No fabricated zero
//
//  A 0 kg body mass in Health is a fabricated measurement in somebody
//  else's UI, where no caveat can be added and it cannot be taken back
//  (AGENTS.md rule 4). Value `<= 0` is therefore ineligible, not a sample.
//  The same rule applies inbound: a 0 kg sample from a scale is not a
//  weigh-in. And a banner that reads "0 additional measurements" is the
//  same lie in a different place — count `<= 0` produces no sentence.
//

import Foundation

/// The four HealthKit quantity kinds this app can travel as.
///
/// Owned here so the rule does not import HealthKit. The HealthKit layer
/// switches on this to pick `HKQuantityTypeIdentifier`. Fourteen of the
/// eighteen seeded types have no case, and that is the point: there is no
/// nearest-quantity fallback.
enum HealthMeasurementQuantity: Equatable, Sendable, CaseIterable {
    /// `bodyMass`. Canonical unit: kilograms.
    case bodyMass
    /// `bodyFatPercentage`. Canonical unit: a FRACTION in 0...1.
    /// HealthKit's percent is not "20 for 20%". Writing 20 would claim 2000%.
    case bodyFatPercentage
    /// `dietaryEnergyConsumed`. Canonical unit: kilocalories.
    case dietaryEnergyConsumed
    /// `waistCircumference`. Canonical unit: meters.
    case waistCircumference
}

/// Everything needed to write one measurement to Health, with no HealthKit types.
struct HealthMeasurementPlan: Equatable, Sendable {
    /// The entry's own id, written to `HKMetadataKeyExternalUUID` so the
    /// sample can be found again without storing anything locally, and so
    /// the importer can skip a sample we already hold.
    let externalID: UUID
    let quantity: HealthMeasurementQuantity
    /// Value in Health's canonical unit for `quantity`: kilograms, fraction
    /// 0...1, kilocalories, or meters. Not the stored `MeasurementEntry.value`.
    let canonicalValue: Double
    let recordedAt: Date
}

/// Everything needed to insert one incoming Health sample as a local entry,
/// with no HealthKit types and no `ModelContext`.
///
/// The HealthKit layer builds the `MeasurementEntry` — that needs a live
/// `MeasurementType` this file cannot fetch. This is the payload: identity,
/// which seeded type to attach, the stored value in that type's default
/// unit, and when it was recorded.
struct HealthMeasurementImportPlan: Equatable, Sendable {
    /// Identity of the sample, and of the local row if we import it:
    /// `externalID ?? sampleID`. Next scan, `alreadyHave` contains this
    /// and we skip. No `didImport` column — same reason workouts have no
    /// `didWriteToHealth`.
    let id: UUID
    /// Seeded type UUID from the inverse map. The HealthKit layer attaches
    /// this existing type, not a newly created one. Names are not the key.
    let typeID: UUID
    let local: HealthMeasurementLocalValue
    let recordedAt: Date
    let quantity: HealthMeasurementQuantity
}

/// Facts the HealthKit layer learned from a query this file cannot run,
/// one incoming sample. The batch helper takes a list of these.
///
/// Plain values, not HealthKit types — a scale's `HKQuantitySample` is
/// reduced to these before it crosses the rule boundary.
struct HealthMeasurementSampleFacts: Equatable, Sendable {
    let isFromThisApp: Bool
    /// HealthKit's `HKObject.uuid`. Always present.
    let sampleID: UUID
    /// `HKMetadataKeyExternalUUID` if the sample has one.
    let externalID: UUID?
    let quantity: HealthMeasurementQuantity
    /// Health's unit: kilograms, fraction 0...1, kilocalories, metres.
    let canonicalValue: Double
    /// The sample's start.
    let recordedAt: Date
}

/// What to store locally for an incoming Health sample, in the seeded type's
/// default unit. Inverse of the write conversion.
///
/// Welcome rather than required — skipping is the load-bearing import
/// decision. Kept beside the write conversion so Health canonical → local
/// cannot drift from local → Health canonical.
struct HealthMeasurementLocalValue: Equatable, Sendable {
    let value: Double
    let unit: String
}

/// Whether an incoming Health sample should become a local entry.
///
/// A Bool would collapse "this is our own write echoing back" with "we
/// already ingested this id", and those are different sentences. Skipping
/// is the decision; the cases name why.
enum HealthMeasurementImportDecision: Equatable, Sendable {
    /// The sample's source is this app's default HealthKit source. Importing
    /// it would duplicate every manual weigh-in we just wrote.
    case skipFromThisApp
    /// `HKMetadataKeyExternalUUID` is one of the local entry ids we already
    /// hold. A sample we already ingested, or a sample whose id is one of
    /// our entries.
    case skipAlreadyHave
    /// Another source, and an id we do not have. Import is allowed.
    case allow
}

/// Why `importPlan` produces no payload. Distinct from
/// `HealthMeasurementImportDecision` because refuse-a-zero is not a
/// skip-vs-allow question — growing `importDecision` with `canonicalValue`
/// would make "our own write" and "Health sent a 0 kg sample" the same
/// function, and they are not.
///
/// The two echo cases keep the `skip…` names so a test (or a caller) that
/// already matches `importDecision` can match the same words here.
enum HealthMeasurementImportSkip: Error, Equatable, Sendable {
    /// Same sentence as `HealthMeasurementImportDecision.skipFromThisApp`.
    case skipFromThisApp
    /// Same sentence as `HealthMeasurementImportDecision.skipAlreadyHave`.
    case skipAlreadyHave
    /// Canonical value `<= 0`. A 0 kg body mass imported into this app is
    /// a fabricated measurement (AGENTS.md rule 4).
    case nonPositiveValue
}

enum HealthMeasurementRule {

    // MARK: - Seed ids
    //
    // Copied from `measurement-seed.json`. Mapping is by these ids, never by
    // name. A user-created type named "Weight" has a different id and must
    // not travel. Changing a string here without changing the seed is a
    // silent empty mapping, so the tests pin the same literals independently.

    /// Seeded Weight. Health: body mass, kilograms.
    static let bodyMassTypeID = UUID(uuidString: "d4982888-f08b-4e32-892c-4a7c36658311")!
    /// Seeded Body Fat %. Health: body fat percentage, fraction 0...1.
    static let bodyFatTypeID = UUID(uuidString: "5725b6bb-91e7-4ce9-a68f-5f9584f43649")!
    /// Seeded Caloric Intake. Health: dietary energy consumed, kilocalories.
    static let dietaryEnergyTypeID = UUID(uuidString: "e701352b-95d1-4623-b293-e001dc0d70dc")!
    /// Seeded Waist. Health: waist circumference, meters.
    static let waistTypeID = UUID(uuidString: "6cc45dde-f100-48a4-852b-7d85e9d722a4")!

    /// The international inch in metres, exactly. Defined as 0.0254 m in 1959,
    /// the same year as the international pound `WeightUnits.kilogramsPerPound`
    /// uses. Waist is a circumference, not a load: do not call `WeightUnits`.
    static let metersPerInternationalInch: Double = 0.0254

    /// Why an entry is not going to Health. Returned rather than a bare `nil`
    /// so a caller — or a test — can tell "this is a bicep" from "this was
    /// imported from Health", which a single nil collapses into one
    /// indistinguishable case.
    enum Ineligible: Error, Equatable, Sendable {
        /// Tombstoned. It did not happen as far as this app is concerned.
        case deleted
        /// `source == .healthKit`. Health already has this sample; writing it
        /// back is the outbound half of the echo loop.
        case importedFromHealth
        /// Type missing, or the type id is not one of the four that exist in
        /// HealthKit. Neck, biceps, and a user-created "Weight" all land here.
        case cannotTravel
        /// Value `<= 0`. A 0 kg body mass in Health is a fabricated
        /// measurement in somebody else's UI (AGENTS.md rule 4).
        case nonPositiveValue
        /// The entry's `unit` string is not one we convert for this quantity.
        /// Unknown is ineligible, not a guessed conversion.
        case unknownUnit
    }

    // MARK: - 1. Can this type travel?

    /// Which of the four Health quantities this type id is, or `nil` if it
    /// cannot travel.
    ///
    /// A function of the id, not the name. The four UUIDs are the seed
    /// contract; everything else — including a type a user named "Weight" —
    /// has no HealthKit type and must not map.
    static func quantity(forTypeID id: UUID) -> HealthMeasurementQuantity? {
        switch id {
        case bodyMassTypeID:        return .bodyMass
        case bodyFatTypeID:         return .bodyFatPercentage
        case dietaryEnergyTypeID:   return .dietaryEnergyConsumed
        case waistTypeID:           return .waistCircumference
        default:                    return nil
        }
    }

    /// Inverse of `quantity(forTypeID:)`. Every quantity this app travels as
    /// is one of the four seeded types; there is no optional, because there
    /// is no fifth case that would have no seed.
    ///
    /// The HealthKit layer uses this when inserting a `MeasurementEntry`
    /// so it attaches the seeded Weight type, not a newly created one.
    /// Names are not the key: a user-created type named "Weight" has a
    /// different id and must not be chosen here.
    static func typeID(for quantity: HealthMeasurementQuantity) -> UUID {
        switch quantity {
        case .bodyMass:              return bodyMassTypeID
        case .bodyFatPercentage:     return bodyFatTypeID
        case .dietaryEnergyConsumed: return dietaryEnergyTypeID
        case .waistCircumference:    return waistTypeID
        }
    }

    // MARK: - 2. What would writing this entry look like?

    /// The plan for this entry, or why there isn't one.
    ///
    /// Order is the decision: deleted first (it did not happen), then the
    /// outbound echo skip (Health already has it), then type, then a
    /// fabricated zero, then unit. A `.healthKit`-sourced Weight is
    /// ineligible even though the type maps — if that were wrong,
    /// import→write→import would loop.
    static func plan(for entry: MeasurementEntry) -> Result<HealthMeasurementPlan, Ineligible> {
        if entry.deletedAt != nil { return .failure(.deleted) }
        if entry.source == .healthKit { return .failure(.importedFromHealth) }
        guard let typeID = entry.type?.id,
              let quantity = quantity(forTypeID: typeID) else {
            return .failure(.cannotTravel)
        }
        guard entry.value > 0 else { return .failure(.nonPositiveValue) }
        guard let canonical = canonicalValue(entry.value, unit: entry.unit, quantity: quantity) else {
            return .failure(.unknownUnit)
        }

        return .success(
            HealthMeasurementPlan(
                externalID: entry.id,
                quantity: quantity,
                canonicalValue: canonical,
                recordedAt: entry.recordedAt
            )
        )
    }

    // MARK: - Which local entries Health does not yet have

    /// Entries that `plan(for:)` would accept AND whose id is not in the
    /// set Health already holds for this app, in `recordedAt` order.
    ///
    /// `alreadyWritten` is the set of `HKMetadataKeyExternalUUID` values
    /// the HealthKit layer read from THIS APP's samples — which is the
    /// entry's own id, see `HealthMeasurementPlan.externalID`. Asking
    /// Health is the whole point of not storing a `didWriteToHealth`
    /// flag. This function cannot query; it subtracts the set it is given.
    /// Empty `alreadyWritten` means Health has none of ours yet: every
    /// eligible entry is missing.
    ///
    /// **Eligibility is `plan(for:)`, not a second list of reasons.** A
    /// tombstoned, `.healthKit`-sourced, Neck, or non-positive entry
    /// cannot be "missing from Health" because it will never be written.
    /// If this function and `plan` disagree, the banner offers Add for a
    /// row `writeMeasurement` will refuse.
    ///
    /// Add writes them in this order so Health's timeline matches when
    /// they were recorded. An unsorted return is a silent shuffle every
    /// time Settings appears.
    static func missingFromHealth(
        from entries: [MeasurementEntry],
        alreadyWritten: Set<UUID>
    ) -> [MeasurementEntry] {
        entries
            .filter { entry in
                guard case .success(let plan) = plan(for: entry) else {
                    return false
                }
                return !alreadyWritten.contains(plan.externalID)
            }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    // MARK: - 3. Should this Health sample be imported?

    /// Skip or allow, given facts the HealthKit layer learned from a query
    /// this rule cannot run.
    ///
    /// **`isFromThisApp` is decided first**, and that order is the echo.
    /// Our writes are tagged with this app as the HealthKit source; importing
    /// them would duplicate every manual weigh-in even when the external UUID
    /// is not yet in `alreadyHave` (the first pull after a write, before we
    /// have recorded that we hold it). The already-have check is the other
    /// skip: a sample we already ingested, or a sample whose id is one of
    /// our entries, from any source.
    ///
    /// Otherwise import is allowed. This function does not build a
    /// `MeasurementEntry` — skipping is the load-bearing decision.
    ///
    /// A nil `externalID` is "no metadata", not "not already held". A
    /// scale sample has no metadata; `importPlan` passes the resolved
    /// identity (`externalID ?? sampleID`) so that path still dedupes.
    static func importDecision(
        isFromThisApp: Bool,
        externalID: UUID?,
        alreadyHave: Set<UUID>
    ) -> HealthMeasurementImportDecision {
        if isFromThisApp { return .skipFromThisApp }
        if let externalID, alreadyHave.contains(externalID) { return .skipAlreadyHave }
        return .allow
    }

    // MARK: - What an incoming sample becomes locally

    /// The local payload for this sample, or why there isn't one.
    ///
    /// Identity of the sample, and therefore of the local row if we
    /// import it:
    ///
    ///     id = externalID ?? sampleID
    ///
    /// That id becomes `MeasurementEntry.id`. Next scan, `alreadyHave`
    /// contains it and we skip. The HealthKit layer will call this once
    /// per sample, with facts it learned from a query this file cannot run.
    ///
    /// Skip (do not produce a plan) when:
    ///
    ///   1. `importDecision` says skip. The resolved `id` is passed as
    ///      `externalID` — always non-nil — so a scale sample with no
    ///      metadata still dedupes on `sampleID`. A nil here would make
    ///      `importDecision` treat "no metadata" as "not already held"
    ///      and re-import the same scale sample forever.
    ///   2. `canonicalValue <= 0`. A 0 kg body mass imported into this
    ///      app is a fabricated measurement (rule 4). Distinguishable
    ///      from the echo skips — a Bool would collapse "our own write"
    ///      with "Health sent a zero".
    ///
    /// Does not build a `MeasurementEntry` — that needs a ModelContext
    /// and a live `MeasurementType`.
    static func importPlan(
        isFromThisApp: Bool,
        sampleID: UUID,
        externalID: UUID?,
        alreadyHave: Set<UUID>,
        quantity: HealthMeasurementQuantity,
        canonicalValue: Double,
        recordedAt: Date
    ) -> Result<HealthMeasurementImportPlan, HealthMeasurementImportSkip> {
        let id = externalID ?? sampleID
        switch importDecision(
            isFromThisApp: isFromThisApp,
            externalID: id,
            alreadyHave: alreadyHave
        ) {
        case .skipFromThisApp:
            return .failure(.skipFromThisApp)
        case .skipAlreadyHave:
            return .failure(.skipAlreadyHave)
        case .allow:
            break
        }
        guard canonicalValue > 0 else { return .failure(.nonPositiveValue) }
        return .success(
            HealthMeasurementImportPlan(
                id: id,
                typeID: typeID(for: quantity),
                local: localValue(canonical: canonicalValue, quantity: quantity),
                recordedAt: recordedAt,
                quantity: quantity
            )
        )
    }

    /// Successful import plans for a batch of samples, in `recordedAt`
    /// order. A sample that fails `importPlan` does not appear.
    ///
    /// Add writes them in this order so the local time series matches
    /// Health's. An unsorted return is a silent shuffle every time
    /// Settings appears.
    static func importPlans(
        from samples: [HealthMeasurementSampleFacts],
        alreadyHave: Set<UUID>
    ) -> [HealthMeasurementImportPlan] {
        samples
            .compactMap { sample in
                try? importPlan(
                    isFromThisApp: sample.isFromThisApp,
                    sampleID: sample.sampleID,
                    externalID: sample.externalID,
                    alreadyHave: alreadyHave,
                    quantity: sample.quantity,
                    canonicalValue: sample.canonicalValue,
                    recordedAt: sample.recordedAt
                ).get()
            }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    // MARK: - Banner sentences

    /// The write-banner sentence, or `nil` when there is nothing to add.
    ///
    /// Nil at `<= 0` is AGENTS.md rule 4: "0 MCP Strength measurements
    /// without corresponding Apple Health entries" would read as a count
    /// rather than absence, so the banner is simply not shown. Negative
    /// is also nil — a count cannot be negative, and inventing a sentence
    /// for one would be a second kind of fabricated measurement.
    ///
    /// The sentences are the reference app's (`IMG_2995.PNG`) with Strong
    /// renamed to MCP Strength. Singular vs plural is load-bearing
    /// English: "1 measurements" is a lie. The Add button is drawn by
    /// the view; the sentence still asks the question.
    ///
    /// Separate from `missingFromHealth` so a bug in the count cannot
    /// write a matching lie in the sentence, and the view asks with
    /// `missing.count`.
    static func writePrompt(count: Int) -> String? {
        switch count {
        case 1:
            return "1 MCP Strength measurement without a corresponding Apple Health entry. Add measurement to Apple Health?"
        case let n where n > 1:
            return "\(n) MCP Strength measurements without corresponding Apple Health entries. Add measurements to Apple Health?"
        default:
            return nil
        }
    }

    /// The import-banner sentence, or `nil` when there is nothing to add.
    ///
    /// Same nil-at-zero rule as `writePrompt`. The reference
    /// (`IMG_2995.PNG`) said "Add measurements to Strong?"; we say
    /// MCP Strength. Do not drop the app name — "Add measurements?"
    /// does not say where they go.
    ///
    /// Separate from the import-plan list so the sentence cannot become
    /// a second way of counting. The view asks with `plans.count`.
    static func importPrompt(count: Int) -> String? {
        switch count {
        case 1:
            return "1 additional measurement available from Apple Health. Add measurement to MCP Strength?"
        case let n where n > 1:
            return "\(n) additional measurements available from Apple Health. Add measurements to MCP Strength?"
        default:
            return nil
        }
    }

    // MARK: - Health canonical ↔ seed default unit

    /// Seed default unit for storing a Health sample locally: Weight `lb`,
    /// Body Fat `%`, Calories `kcal`, Waist `in`. Inverse of the write
    /// conversion, so a round trip cannot invent a second number.
    ///
    /// Body fat 0.20 becomes 20, not 0.20. Body mass uses
    /// `WeightUnits.kilogramsPerPound` rather than a second pounds factor.
    /// Waist uses `metersPerInternationalInch`, not `WeightUnits` — a
    /// circumference is not a load.
    static func localValue(
        canonical: Double,
        quantity: HealthMeasurementQuantity
    ) -> HealthMeasurementLocalValue {
        switch quantity {
        case .bodyMass:
            return HealthMeasurementLocalValue(
                value: canonical / WeightUnits.kilogramsPerPound,
                unit: "lb"
            )
        case .bodyFatPercentage:
            return HealthMeasurementLocalValue(value: canonical * 100, unit: "%")
        case .dietaryEnergyConsumed:
            return HealthMeasurementLocalValue(value: canonical, unit: "kcal")
        case .waistCircumference:
            return HealthMeasurementLocalValue(
                value: canonical / metersPerInternationalInch,
                unit: "in"
            )
        }
    }

    /// Local stored value → Health canonical, or `nil` when the unit string
    /// is not one we convert for this quantity.
    ///
    /// Unknown is ineligible, not a guessed conversion. A second pounds
    /// factor here would be a second body-weight number in Health, so body
    /// mass always goes through `WeightUnits.kilograms(from:in:)`. Do not
    /// round: a Health-bound number is not a plate increment.
    static func canonicalValue(
        _ value: Double,
        unit: String,
        quantity: HealthMeasurementQuantity
    ) -> Double? {
        let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch quantity {
        case .bodyMass:
            switch unit {
            case "lb", "lbs":
                return WeightUnits.kilograms(from: value, in: .lbs)
            case "kg":
                return WeightUnits.kilograms(from: value, in: .kg)
            default:
                return nil
            }
        case .bodyFatPercentage:
            guard unit == "%" else { return nil }
            return value / 100
        case .dietaryEnergyConsumed:
            switch unit {
            case "kcal", "cal":
                return value
            default:
                return nil
            }
        case .waistCircumference:
            switch unit {
            case "in":
                return value * metersPerInternationalInch
            case "cm":
                return value / 100
            case "m":
                return value
            default:
                return nil
            }
        }
    }
}
