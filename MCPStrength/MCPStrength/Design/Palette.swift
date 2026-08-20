//
//  Palette.swift
//  MCPStrength
//
//  The four looks the app can wear. `Theme` is still the only thing the rest of
//  the app talks to — this file is what `Theme` reads from.
//
//  Two layers, and the split is the whole design:
//
//    * CHROME — surface / fieldFill / keypadKey / accent / accentFill /
//      textPrimary / textSecondary / onSolid. A palette exists to change these.
//    * LANGUAGE — the set-type hues (W / D / R / F) and the notice pair. These
//      stay put across the dark palettes, because a badge that changes colour
//      when you change theme stops being a badge and starts being decoration.
//      `blush` is the one palette that moves them, and it moves LIGHTNESS, not
//      hue: orange stays orange, teal stays teal, both just dark enough to read
//      on cream. See `PaletteTests` — the separations are pinned there, not
//      left to eyeballing.
//
//  Colours are stored as components rather than as `Color`, because the rules
//  that make a palette legal (a field fill that is visible on its surface, an
//  accent that cannot be mistaken for the F badge) are arithmetic on those
//  components, and `Color` will not hand them back reliably.
//

import SwiftUI

// MARK: - A single colour

/// One colour, kept as sRGB components so the palette rules can be computed
/// rather than trusted. `init(0x2E86FF)` reads like the hex it came from.
struct PaletteColor: Equatable, Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(_ hex: UInt32) {
        red   = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue  = Double(hex & 0xFF) / 255
    }

    var color: Color { Color(red: red, green: green, blue: blue) }

    /// Hex, uppercase, `#RRGGBB` — for the theme picker's caption and for test
    /// failure messages that would otherwise report three unreadable Doubles.
    var hexString: String {
        String(format: "#%02X%02X%02X",
               Int((red * 255).rounded()),
               Int((green * 255).rounded()),
               Int((blue * 255).rounded()))
    }

    /// WCAG relative luminance.
    var relativeLuminance: Double {
        func channel(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// Hue in degrees, 0..<360. Used for the separation rules: the badge
    /// alphabet only works while the letters are far enough apart in hue that
    /// a 28pt square cannot be misread.
    var hueDegrees: Double {
        let maxC = max(red, green, blue)
        let minC = min(red, green, blue)
        let delta = maxC - minC
        guard delta > 0 else { return 0 }
        let h: Double
        switch maxC {
        case red:   h = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        case green: h = (blue - red) / delta + 2
        default:    h = (red - green) / delta + 4
        }
        let degrees = h * 60
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// WCAG contrast ratio, 1...21.
    func contrast(against other: PaletteColor) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Shortest way round the wheel, 0...180.
    func hueSeparation(from other: PaletteColor) -> Double {
        let d = abs(hueDegrees - other.hueDegrees)
        return min(d, 360 - d)
    }
}

// MARK: - A palette

/// One complete look: every token the app paints from, in one value.
struct Palette: Equatable, Hashable, Sendable {
    let name: String
    /// One line, shown under the name in the picker. Says what the look IS, not
    /// what it is made of — the hex values are already on screen.
    let blurb: String

    /// Whether system-provided chrome (navigation titles, pickers, keyboards,
    /// the status bar) should render light-on-dark or dark-on-light. Those
    /// controls take their colours from the environment colour scheme and never
    /// from our tokens, so this has to be declared per palette rather than
    /// inferred at the call site.
    let colorScheme: ColorScheme

    // Chrome
    let surface: PaletteColor
    let fieldFill: PaletteColor
    let keypadKey: PaletteColor
    let accent: PaletteColor
    let accentFill: PaletteColor
    let textPrimary: PaletteColor
    let textSecondary: PaletteColor
    /// The label ON a solid accent / success fill — Save, Start Workout,
    /// Finish, keypad Next, the swipe-to-delete strip.
    ///
    /// This is the token a light palette forced into existence. On every dark
    /// look it happens to equal `textPrimary`, which is why the app got this
    /// far without it; on `blush` the two pull opposite ways — titles go
    /// near-black, button labels stay white — and one token cannot do both.
    let onSolid: PaletteColor

    // Status
    let success: PaletteColor
    let destructive: PaletteColor
    let destructiveFill: PaletteColor

    // Set-type badges
    let warmup: PaletteColor
    let dropSet: PaletteColor
    let restPause: PaletteColor

    // Notices
    let notice: PaletteColor
    let noticeText: PaletteColor
}

// MARK: - The looks

extension Palette {
    /// Cold and hard. The default, and the descendant of the original Slate
    /// palette: blacker ground, deeper blue, a wider step between a card and
    /// the screen behind it. Every badge is unchanged from Slate, so nothing
    /// anybody learned about W / D / R / F was invalidated by the switch.
    static let gunmetal = Palette(
        name: "Gunmetal",
        blurb: "Cold and hard. Near-black, deep blue.",
        colorScheme: .dark,
        surface: PaletteColor(0x1B2229),
        fieldFill: PaletteColor(0x0D1115),
        keypadKey: PaletteColor(0x2A333B),
        accent: PaletteColor(0x2E86FF),
        accentFill: PaletteColor(0x14304F),
        textPrimary: PaletteColor(0xFFFFFF),
        textSecondary: PaletteColor(0x8B949C),
        onSolid: PaletteColor(0xFFFFFF),
        success: PaletteColor(0x2ECD70),
        destructive: PaletteColor(0xFF5964),
        destructiveFill: PaletteColor(0x33252A),
        warmup: PaletteColor(0xFFA13B),
        dropSet: PaletteColor(0x8826FC),
        restPause: PaletteColor(0x20D5B1),
        notice: PaletteColor(0xECC12E),
        noticeText: PaletteColor(0x251E0A)
    )

    /// Warm and matte. Olive-graphite ground, bone rather than pure white, and
    /// a steel accent with the glare taken out — the one to reach for if a
    /// bright blue on near-black is too much between sets.
    static let bunker = Palette(
        name: "Bunker",
        blurb: "Warm and matte. Olive graphite, bone text.",
        colorScheme: .dark,
        surface: PaletteColor(0x23261F),
        fieldFill: PaletteColor(0x171A14),
        keypadKey: PaletteColor(0x313629),
        accent: PaletteColor(0x4E97D9),
        accentFill: PaletteColor(0x24404F),
        textPrimary: PaletteColor(0xF5F3EC),
        textSecondary: PaletteColor(0x9A9C8C),
        onSolid: PaletteColor(0xFFFFFF),
        success: PaletteColor(0x2ECD70),
        destructive: PaletteColor(0xFF5964),
        destructiveFill: PaletteColor(0x362B28),
        warmup: PaletteColor(0xFFA13B),
        dropSet: PaletteColor(0x8826FC),
        restPause: PaletteColor(0x20D5B1),
        notice: PaletteColor(0xECC12E),
        noticeText: PaletteColor(0x251E0A)
    )

    /// Plum ground, orchid accent — and the accent hue is the whole point.
    /// A rose or hot pink lands within ~25° of the F badge, which is a 28pt
    /// square: at that distance the two stop being distinguishable. Orchid sits
    /// 44° off F and 45° off D, which is why this palette is orchid and not
    /// pink. `PaletteTests` holds that line.
    static let orchid = Palette(
        name: "Orchid",
        blurb: "Plum ground, orchid accent. Dark, not black.",
        colorScheme: .dark,
        surface: PaletteColor(0x2B2333),
        fieldFill: PaletteColor(0x160F1D),
        keypadKey: PaletteColor(0x3A3043),
        // Two percent darker than the orchid this was mocked in (#DE6EC7),
        // which is invisible next to it and is what takes white-on-accent from
        // 2.93 to 3.26 — i.e. over the bar Save and Start Workout are held to.
        accent: PaletteColor(0xD962BF),
        accentFill: PaletteColor(0x4A2B4E),
        textPrimary: PaletteColor(0xFFF4F8),
        textSecondary: PaletteColor(0xA192A8),
        onSolid: PaletteColor(0xFFFFFF),
        success: PaletteColor(0x2ECD70),
        destructive: PaletteColor(0xFF5964),
        destructiveFill: PaletteColor(0x3B2830),
        warmup: PaletteColor(0xFFA13B),
        dropSet: PaletteColor(0x8826FC),
        restPause: PaletteColor(0x20D5B1),
        notice: PaletteColor(0xECC12E),
        noticeText: PaletteColor(0x251E0A)
    )

    /// The light one. The whole stack inverts — cream screen, warm cards, white
    /// keys — and it is the only palette that reports `.light`, which is what
    /// finally makes the system chrome follow the app instead of being pinned
    /// dark. Set-type hues survive; their LIGHTNESS does not, because
    /// `#FFA13B` on cream is a rumour rather than a badge.
    static let blush = Palette(
        name: "Blush",
        blurb: "Light and warm. Cream screen, plum accent.",
        colorScheme: .light,
        surface: PaletteColor(0xFBF6F5),
        fieldFill: PaletteColor(0xF0E5E6),
        keypadKey: PaletteColor(0xFFFFFF),
        accent: PaletteColor(0x9B3A94),
        accentFill: PaletteColor(0xF4E1F2),
        textPrimary: PaletteColor(0x221A20),
        textSecondary: PaletteColor(0x7C6B72),
        onSolid: PaletteColor(0xFFFFFF),
        success: PaletteColor(0x0F8A52),
        destructive: PaletteColor(0xCE2B41),
        destructiveFill: PaletteColor(0xF9DEE1),
        warmup: PaletteColor(0xA65A06),
        dropSet: PaletteColor(0x6A1FC7),
        restPause: PaletteColor(0x067A69),
        notice: PaletteColor(0xF5C518),
        noticeText: PaletteColor(0x241D07)
    )
}

// MARK: - The choice

/// The palettes as a stored, ordered choice. The raw value is what lands in
/// `UserDefaults`, so **do not rename a case** — a renamed case reads back as
/// "unrecognised" and silently drops the user to the default.
enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case gunmetal
    case bunker
    case orchid
    case blush

    var id: String { rawValue }

    var palette: Palette {
        switch self {
        case .gunmetal: return .gunmetal
        case .bunker:   return .bunker
        case .orchid:   return .orchid
        case .blush:    return .blush
        }
    }

    var name: String { palette.name }

    /// What a device that has never chosen wears.
    static let fallback = AppTheme.gunmetal
}
