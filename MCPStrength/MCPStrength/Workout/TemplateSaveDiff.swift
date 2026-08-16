//
//  TemplateSaveDiff.swift
//  MCPStrength
//
//  Decide, from ids alone, what Save does to each row under a template.
//
//  The editor holds edits in value-type drafts so ✕ can discard without a
//  transaction. That is deliberate. The trap is that a draft hydrated from an
//  existing row used to mint a FRESH UUID, so by Save there was nothing linking
//  the draft back to the row it came from. A diff was impossible by
//  construction, and the only remaining write was tombstone-everything then
//  insert a new subtree. Locally that is just wasteful. Once a row can travel,
//  correcting one weight tells the server every exercise and every set was
//  deleted and a brand-new set created.
//
//  Identity is the join key. loadDraft now carries the existing row's id;
//  addExercise / addSet still mint a fresh one. This function then classifies
//  each id as KEPT (the row already exists — update it in place), ADDED (no
//  such row — insert), or REMOVED (the row is gone from the drafts —
//  tombstone). The same rule runs at both levels: exercises under the
//  template, then the sets under each surviving exercise.
//
//  Order is a field, not a side effect. A template's exercises and sets are
//  positional, so a surviving row carries the index it should occupy after
//  Save, not merely the fact that it survived. Reorder is therefore KEPT with
//  a new index — never a delete plus an insert.
//
//  Lives here (no SwiftUI, no ModelContext) so the classification can be
//  tested without standing up a store. save() is private inside a View and
//  cannot be.
//

import Foundation

enum TemplateSaveDiff {

    /// A surviving draft (kept or added) and the `order` it should be written
    /// at. Removed rows have no new index — they are leaving.
    struct Placement: Equatable {
        let id: UUID
        let newOrder: Int
    }

    /// One level of the tree: the draft ids versus the live row ids.
    struct Level: Equatable {
        static let empty = Level(kept: [], added: [], removed: [])

        let kept: [Placement]
        let added: [Placement]
        let removed: [UUID]
    }

    /// Exercise-level classification, plus a set-level classification for
    /// each KEPT exercise, keyed by that exercise's id.
    ///
    /// ADDED exercises are omitted from `setsByKeptExercise` on purpose:
    /// every set under a new exercise is new, and save() inserts them with
    /// the exercise. REMOVED exercises are omitted for the same reason in
    /// reverse: SoftDelete.templateExercise already cascades to their sets,
    /// and listing those sets here would invite a second, partial tombstone
    /// that drifts from the cascade.
    struct Plan: Equatable {
        let exercises: Level
        let setsByKeptExercise: [UUID: Level]
    }

    /// `drafts` is the current editor order — index is the intended `order`.
    /// `existing` is the live rows under the template; membership is the
    /// only input that matters for KEPT / ADDED / REMOVED, and sequence
    /// is preserved only so `removed` is stable.
    static func plan(
        drafts: [(id: UUID, setIDs: [UUID])],
        existing: [(id: UUID, setIDs: [UUID])]
    ) -> Plan {
        let exercises = classify(
            draftIDs: drafts.map(\.id),
            existingIDs: existing.map(\.id)
        )

        let existingSets = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0.setIDs) })
        let draftSets = Dictionary(uniqueKeysWithValues: drafts.map { ($0.id, $0.setIDs) })

        var setsByKeptExercise: [UUID: Level] = [:]
        for item in exercises.kept {
            setsByKeptExercise[item.id] = classify(
                draftIDs: draftSets[item.id] ?? [],
                existingIDs: existingSets[item.id] ?? []
            )
        }
        return Plan(exercises: exercises, setsByKeptExercise: setsByKeptExercise)
    }

    /// The identity rule, one level at a time. A draft id that is already
    /// among the live rows is KEPT; a draft id the store has never seen is
    /// ADDED; a live id that no draft still holds is REMOVED. Fields are
    /// not an input — a weight change and a no-op save classify identically,
    /// which is what makes "update in place" possible. save() decides
    /// whether a KEPT row's fields actually moved.
    static func classify(draftIDs: [UUID], existingIDs: [UUID]) -> Level {
        let existingSet = Set(existingIDs)
        let draftSet = Set(draftIDs)

        var kept: [Placement] = []
        var added: [Placement] = []
        for (order, id) in draftIDs.enumerated() {
            if existingSet.contains(id) {
                kept.append(Placement(id: id, newOrder: order))
            } else {
                added.append(Placement(id: id, newOrder: order))
            }
        }
        let removed = existingIDs.filter { !draftSet.contains($0) }
        return Level(kept: kept, added: added, removed: removed)
    }
}
