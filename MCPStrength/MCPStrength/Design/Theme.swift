//
//  Theme.swift
//  MCPStrength
//
//  The design token layer. This is the only file in the app that is allowed to
//  hold colour literals — every other screen says `Theme.accent`, never a hex
//  value. Adding a light palette later means swapping the bodies of the `Color`
//  properties below (e.g. to resolve from an asset catalog) without touching a
//  single call site.
//

import SwiftUI

// MARK: - Colour tokens

/// Semantic colour namespace. Call sites read `Theme.accent`, `Theme.surface`,
/// etc. — never a raw `Color(...)` or hex literal.
enum Theme {
    // Surfaces
    /// Screen and sheet background.
    static let surface = Color(red: 0.160784, green: 0.192157, blue: 0.211765)
    /// Weight/reps entry chips — slightly darker than the surface.
    static let fieldFill = Color(red: 0.121569, green: 0.145098, blue: 0.164706)

    // Accents
    /// Exercise names, rest-timer text, links.
    static let accent = Color(red: 0.207843, green: 0.654902, blue: 1.0)
    /// Desaturated fill sitting behind accent-coloured text (tinted button idiom).
    static let accentFill = Color(red: 0.172549, green: 0.305882, blue: 0.407843)

    // Status
    /// The Finish button.
    static let success = Color(red: 0.180392, green: 0.803922, blue: 0.439216)
    /// Cancel Workout text — and, by alias, the failure-set badge.
    static let destructive = Color(red: 1.0, green: 0.349020, blue: 0.392157)
    /// Desaturated fill behind destructive-coloured text (tinted button idiom).
    static let destructiveFill = Color(red: 0.243137, green: 0.207843, blue: 0.227451)

    // Text
    static let textPrimary = Color(red: 1.0, green: 1.0, blue: 1.0)
    /// Dates, durations, column headers, "Previous" values.
    static let textSecondary = Color(red: 0.580392, green: 0.596078, blue: 0.603922)

    // Set-type badge hues
    /// The W set badge.
    static let warmup = Color(red: 1.0, green: 0.631373, blue: 0.231373)
    /// The D set badge.
    static let dropSet = Color(red: 0.533333, green: 0.149020, blue: 0.988235)

    // MARK: Failure alias
    //
    // The F set badge is the *same red* as `destructive`, verified across both
    // reference screenshots (docs/01-data-model.md gives F as red; the sampled
    // value is #FF5964). It is an alias, not a separate literal, so a future
    // retune of the destructive red drags the failure badge with it.
    /// The F set badge — identical to `destructive` by design.
    static var failure: Color { destructive }
}

// MARK: - Spacing scale

/// Semantic spacing. Named, not numeric, so a screen says `.padding(.screenMargin)`
/// or `Spacing.screenMargin` rather than guessing 16.
enum Spacing {
    /// Full-width horizontal screen edge margin.
    static let screenMargin: CGFloat = 16
    /// Vertical padding inside a primary/tinted button.
    static let buttonVertical: CGFloat = 14
    /// Compact internal padding (chips, badges, tight rows).
    static let compact: CGFloat = 8
    /// A step up for section separation.
    static let comfortable: CGFloat = 12
    /// Generous block separation.
    static let spacious: CGFloat = 24
}

// MARK: - Radius scale

/// Corner radii, named by where they apply.
enum Radius {
    /// Primary/tinted full-width buttons.
    static let button: CGFloat = 12
    /// Weight/reps entry chips.
    static let chip: CGFloat = 8
    /// Set-type badges — small rounded squares.
    static let badge: CGFloat = 6
    /// Cards and sheet tops.
    static let card: CGFloat = 16
}

// MARK: - Typography scale

/// A small type scale. Named by role so call sites stay declarative.
enum Typography {
    static let title = Font.system(size: 20, weight: .semibold)
    static let body = Font.system(size: 17)
    /// Dates, durations, column headers, "Previous" values.
    static let secondary = Font.system(size: 14)
    /// The number inside a weight/reps entry chip.
    static let chipValue = Font.system(size: 17, weight: .semibold)
    /// The glyph inside a set-type badge.
    static let badge = Font.system(size: 13, weight: .bold)
    /// Button labels.
    static let button = Font.system(size: 16, weight: .semibold)
}
