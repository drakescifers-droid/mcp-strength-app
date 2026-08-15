//
//  ListOrdering.swift
//  MCPStrength
//
//  Reorder an item by moving its id between two ordered id lists — templates
//  in a folder (or the unfiled list), exercises in a workout. Position is
//  meaningful: a drop inserts at the row under the finger, it does not
//  append. This file owns that pure rule so it can be unit-tested without a
//  store and shared by the drop handlers — computing an index from a CGPoint
//  would be untestable and fragile.
//

import Foundation

enum ListOrdering {
    /// Moves `id` from `source` to `destination` at `index`.
    ///
    /// `index` is the desired final position IN THE DESTINATION LIST AFTER
    /// `id` has been removed from wherever it was. The alternative convention
    /// (index in the pre-removal list) differs by one when moving DOWN within
    /// the same list; that off-by-one is the most likely defect here.
    ///
    /// Same-list: when `source` and `destination` hold the same ids, `id` is
    /// removed then inserted at `index`, and the resulting array is returned
    /// as both tuple members.
    ///
    /// Cross-list: `id` is removed from `source` and inserted into
    /// `destination` at `index`.
    ///
    /// `index` is clamped into `0...destination.count` (after removal). A drop
    /// past the last card is ordinary, not an error. If `id` is not in
    /// `source`, both lists are returned unchanged.
    static func move(
        _ id: UUID,
        from source: [UUID],
        to destination: [UUID],
        at index: Int
    ) -> (source: [UUID], destination: [UUID]) {
        guard source.contains(id) else {
            return (source, destination)
        }

        // Same membership, not sequence equality: the caller builds both
        // arrays from the same folder, but "hold the same ids" is the contract.
        if Set(source) == Set(destination) {
            var list = source
            list.removeAll { $0 == id }
            let clamped = min(max(index, 0), list.count)
            list.insert(id, at: clamped)
            return (list, list)
        }

        var newSource = source
        newSource.removeAll { $0 == id }
        var newDestination = destination
        let clamped = min(max(index, 0), newDestination.count)
        newDestination.insert(id, at: clamped)
        return (newSource, newDestination)
    }
}
