//
//  MeasurementLatest.swift
//  MCPStrength
//
//  Pure helpers over `[MeasurementEntry]` for the measurements screen. The list shows ONLY the
//  latest value per type, and that computation must not be a sort buried in a view body — it is
//  a pure function so it can be unit-tested with fixed dates and fixture orderings.
//
//  The underlying data is a time series; the list is a summary of it. A per-type detail screen
//  shows the full history newest-first (see MeasurementTypeDetailScreen).
//

import Foundation

/// Pure helpers for selecting the latest entry per type.
///
/// "Latest" = greatest `recordedAt`. When two entries share the same `recordedAt`, the tie
/// breaks toward the entry appearing LATER in the input array. `MeasurementEntry` has no
/// creation timestamp, so callers should pass entries in creation order (oldest first); the
/// tiebreak then keeps the most recently created entry, matching the reference screen's intent.
enum MeasurementLatest {

    /// Returns the latest entry among `entries`, or nil if `entries` is empty.
    ///
    /// Latest = greatest `recordedAt`; ties break toward the later element in `entries`
    /// (i.e. the most recently created, assuming the caller passes entries in creation order).
    static func latest(in entries: [MeasurementEntry]) -> MeasurementEntry? {
        entries.enumerated().max(by: { a, b in
            if a.element.recordedAt != b.element.recordedAt {
                return a.element.recordedAt < b.element.recordedAt
            }
            return a.offset < b.offset
        })?.element
    }

    /// Groups `entries` by their type id and returns the latest entry for each type that has at
    /// least one entry. Types with no entries are simply absent from the result (a body part you
    /// have never measured is unknown, not zero). Entries with no associated type are skipped.
    static func latestByTypeID(_ entries: [MeasurementEntry]) -> [UUID: MeasurementEntry] {
        var result: [UUID: MeasurementEntry] = [:]
        for entry in entries {
            guard let typeID = entry.type?.id else { continue }
            // Iterate in array order; on an equal recordedAt, the later element replaces the
            // earlier one, so the most recently created wins the tie (see type-level doc).
            if let existing = result[typeID] {
                if entry.recordedAt > existing.recordedAt
                    || entry.recordedAt == existing.recordedAt {
                    result[typeID] = entry
                }
            } else {
                result[typeID] = entry
            }
        }
        return result
    }
}
