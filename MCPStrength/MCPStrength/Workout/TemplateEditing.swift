//
//  TemplateEditing.swift
//  MCPStrength
//
//  The copy-suffix rule for Template names. A duplicate must not collide
//  with an existing name (comparison is case-insensitive), and the first
//  free suffix is "(copy)", then "(copy 2)", "(copy 3)", … so two taps
//  cannot land on the same string. Lives here so the card menu and the
//  tests share one implementation rather than drifting.
//

import Foundation

enum TemplateEditing {
    /// Next unused copy name for `original`.
    ///
    /// `"Push Day"` with nothing taken → `"Push Day (copy)"`. If that
    /// string (or a case-variant of it) is already in `existing`, the
    /// result is `"Push Day (copy 2)"`, then `" (copy 3)"`, and so on.
    /// Never returns a name already in `existing`.
    static func duplicateName(of original: String, existing: [String]) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        let first = "\(original) (copy)"
        if !taken.contains(first.lowercased()) {
            return first
        }
        var n = 2
        while true {
            let candidate = "\(original) (copy \(n))"
            if !taken.contains(candidate.lowercased()) {
                return candidate
            }
            n += 1
        }
    }
}
