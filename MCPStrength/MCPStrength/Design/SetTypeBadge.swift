//
//  SetTypeBadge.swift
//  MCPStrength
//

import SwiftUI
// SetType is defined in Models/Template.swift — import and use it, do not
// redefine it.

// MARK: - Set-type badge
//
// Renders the leading glyph for a set row. The reference (docs/01-data-model.md
// § SetType, confirmed across both screenshots):
//   normal  -> the set number, in textSecondary
//   warmup  -> "W", in warmup
//   dropSet -> "D", in dropSet
//   failure -> "F", in failure   (failure is an alias of destructive, never a
//                                separate literal — see Theme.failure)

/// A small rounded badge that renders the right glyph and colour for a set type.
/// Pass the working-set `index` (1-based) for `.normal`; it is ignored for the
/// lettered types.
struct SetTypeBadge: View {
    let setType: SetType
    var setNumber: Int

    var body: some View {
        Text(glyph)
            .font(Typography.badge)
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
            .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.badge))
    }

    private var glyph: String {
        switch setType {
        case .normal:  return "\(setNumber)"
        case .warmup:  return "W"
        case .dropSet: return "D"
        case .failure: return "F"
        }
    }

    private var color: Color {
        switch setType {
        case .normal:  return Theme.textSecondary
        case .warmup:  return Theme.warmup
        case .dropSet: return Theme.dropSet
        case .failure: return Theme.failure
        }
    }
}
