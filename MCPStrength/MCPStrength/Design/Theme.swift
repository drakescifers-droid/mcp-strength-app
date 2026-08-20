//
//  Theme.swift
//  MCPStrength
//
//  The design token layer. This is the only file in the app that names a
//  palette — every other screen says `Theme.accent`, never a hex value and
//  never a palette.
//
//  The tokens are now RESOLVED, not fixed: each one reads through to whichever
//  `Palette` is currently on (see Palette.swift, ThemeStore.swift). Call sites
//  did not change when themes arrived, and will not change when a fifth look is
//  added — that is the whole return on having had this indirection from day one.
//
//  A NOTE ON HOW A SWITCH ACTUALLY REPAINTS. These are plain statics, so SwiftUI
//  has no dependency on them and will not re-run a body just because one
//  changed. The root view is keyed on the selected theme instead
//  (`MCPStrengthApp`), which rebuilds the tree once, on switch. That is a
//  deliberate trade: one rebuild at the moment somebody picks a look, against
//  threading an environment value through 300-odd call sites.
//

import SwiftUI

// MARK: - Colour tokens

/// Semantic colour namespace. Call sites read `Theme.accent`, `Theme.surface`,
/// etc. — never a raw `Color(...)`, a hex literal, or a `Palette`.
enum Theme {

    /// The palette every token below resolves through.
    ///
    /// `nonisolated(unsafe)` is honest rather than clever: this is written once
    /// at launch and again only when somebody taps a theme in Settings, both on
    /// the main actor, and read from view bodies which are also main-actor.
    /// Marking `Theme` itself `@MainActor` would drag `ButtonStyle`'s
    /// nonisolated statics along with it for no gain.
    nonisolated(unsafe) private(set) static var palette: Palette = AppTheme.fallback.palette

    /// Point every token at a different look. Called by `ThemeStore`; nothing
    /// else should need it.
    static func use(_ theme: AppTheme) {
        palette = theme.palette
    }

    // Surfaces
    /// Screen and sheet background.
    static var surface: Color { palette.surface.color }
    /// Weight/reps entry chips — a step away from the surface, in whichever
    /// direction the palette runs (darker on the dark looks, warmer on Blush).
    static var fieldFill: Color { palette.fieldFill.color }
    /// Custom number-keypad keys — a further step from `fieldFill` so they read
    /// as buttons on the pad, not as more of the pad.
    static var keypadKey: Color { palette.keypadKey.color }

    // Accents
    /// Exercise names, rest-timer text, links.
    static var accent: Color { palette.accent.color }
    /// Desaturated fill sitting behind accent-coloured text (tinted button idiom).
    static var accentFill: Color { palette.accentFill.color }

    // Status
    /// The Finish button.
    static var success: Color { palette.success.color }
    /// Cancel Workout text — and, by alias, the failure-set badge.
    static var destructive: Color { palette.destructive.color }
    /// Desaturated fill behind destructive-coloured text (tinted button idiom).
    static var destructiveFill: Color { palette.destructiveFill.color }

    // Text
    static var textPrimary: Color { palette.textPrimary.color }
    /// Dates, durations, column headers, "Previous" values.
    static var textSecondary: Color { palette.textSecondary.color }
    /// The label ON a solid fill — Save, Start Workout, Finish, keypad Next,
    /// the swipe-to-delete strip.
    ///
    /// Not the same job as `textPrimary`, even though every dark palette gives
    /// them the same value. A title and a button label want opposite answers
    /// the moment the screen goes light, and the two places that used to say
    /// raw `.white` (keypad Next, delete strip) say this instead.
    static var onSolid: Color { palette.onSolid.color }

    // Set-type badge hues
    /// The W set badge.
    static var warmup: Color { palette.warmup.color }
    /// The D set badge.
    static var dropSet: Color { palette.dropSet.color }
    /// The R set badge (rest-pause / myo-rep). Teal, so it cannot be read as
    /// warm-up orange, drop purple, failure red, or accent blue.
    static var restPause: Color { palette.restPause.color }

    /// The Health backfill strip. Not `warmup`: that is a set-type badge, and
    /// a notice that reused it would look like a warm-up set sitting in
    /// Settings. Sampled from the reference (`IMG_2996.PNG`).
    static var notice: Color { palette.notice.color }
    /// Text and the Add control on `notice`. Dark on yellow so the sentence
    /// stays readable; accent-blue on yellow would be the rest-timer bug
    /// (a control that cannot be told from the fill).
    static var noticeText: Color { palette.noticeText.color }

    // MARK: Failure alias
    //
    // The F set badge is the *same red* as `destructive` in every palette. It
    // is an alias, not a separate token, so retuning a red for one look drags
    // the failure badge with it and the two can never drift apart.
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
    /// Template card titles. Smaller than `body` on purpose: the card is one
    /// column of a two-column grid and shares its top row with trailing
    /// controls, so 17pt truncated real template names to "New Templ…".
    static let cardTitle = Font.system(size: 15, weight: .semibold)
}
