//
//  PaletteTests.swift
//  MCPStrengthTests
//
//  What makes a palette LEGAL, as arithmetic rather than as taste.
//
//  Taste is not testable and is not tested here — whether Bunker's olive is
//  pleasant is Drake's call, made by looking at it. What is testable is the set
//  of rules a palette breaks silently: a card that stops being visible against
//  its screen, a badge that drifts into the accent, a button label that
//  disappears into its own fill. Those are the failures nobody notices in a
//  screenshot and everybody notices mid-set in a gym.
//
//  Every rule below applies to EVERY palette, so adding a fifth look means
//  answering these questions rather than discovering them later.
//

import Testing
import SwiftUI
@testable import MCPStrength

struct PaletteTests {

    // Every test below runs once per case of `AppTheme`, so a new look cannot
    // be added without being held to the same rules.

    // MARK: - The three-step stack
    //
    // surface -> fieldFill -> keypadKey. Each step has to be visible against
    // the one it sits on. The direction flips on a light palette; the
    // requirement does not.

    @Test(arguments: AppTheme.allCases)
    func cardsAreVisibleAgainstTheScreen(theme: AppTheme) {
        let palette = theme.palette
        let name = palette.name
        let ratio = palette.fieldFill.contrast(against: palette.surface)
        #expect(ratio >= 1.14, "\(name): fieldFill \(palette.fieldFill.hexString) is invisible on surface \(palette.surface.hexString) — \(ratio)")
    }

    @Test(arguments: AppTheme.allCases)
    func keysReadAsKeysOnThePad(theme: AppTheme) {
        let palette = theme.palette
        let name = palette.name
        let ratio = palette.keypadKey.contrast(against: palette.fieldFill)
        #expect(ratio >= 1.22, "\(name): keypadKey \(palette.keypadKey.hexString) melts into the pad — \(ratio)")
    }

    @Test(arguments: AppTheme.allCases)
    func theThreeStepsAreThreeDifferentColours(theme: AppTheme) {
        let palette = theme.palette
        let name = palette.name
        #expect(palette.surface != palette.fieldFill, "\(name): surface and fieldFill are the same colour")
        #expect(palette.fieldFill != palette.keypadKey, "\(name): fieldFill and keypadKey are the same colour")
    }

    // MARK: - Text

    @Test(arguments: AppTheme.allCases)
    func titlesAreReadable(theme: AppTheme) {
        let palette = theme.palette
        let name = palette.name
        let ratio = palette.textPrimary.contrast(against: palette.surface)
        #expect(ratio >= 7, "\(name): titles at \(ratio):1")
    }

    @Test(arguments: AppTheme.allCases)
    func secondaryTextIsReadable(theme: AppTheme) {
        let palette = theme.palette
        let name = palette.name
        // Dates, column headers, "Previous" — smaller and dimmer by design, but
        // still text somebody reads mid-set. WCAG AA for body copy.
        let ratio = palette.textSecondary.contrast(against: palette.surface)
        #expect(ratio >= 4.5, "\(name): secondary text at \(ratio):1")
    }

    @Test(arguments: AppTheme.allCases)
    func exerciseNamesAreReadable(theme: AppTheme) {
        let palette = theme.palette
        let name = palette.name
        let ratio = palette.accent.contrast(against: palette.surface)
        #expect(ratio >= 4.5, "\(name): accent text at \(ratio):1")
    }

    // MARK: - Labels on solid fills

    @Test(arguments: AppTheme.allCases)
    func buttonLabelsSurviveTheirFill(theme: AppTheme) {
        let palette = theme.palette
        let name = palette.name
        // Save, Start Workout, keypad Next — `onSolid` on a saturated accent.
        // 3:1 is the large-text bar, which is what a semibold 16pt button label
        // is.
        let ratio = palette.onSolid.contrast(against: palette.accent)
        #expect(ratio >= 3, "\(name): button text on accent at \(ratio):1")
    }

    @Test(arguments: AppTheme.allCases)
    func deleteStripLabelSurvivesItsFill(theme: AppTheme) {
        let palette = theme.palette
        let name = palette.name
        let ratio = palette.onSolid.contrast(against: palette.destructive)
        #expect(ratio >= 3, "\(name): Delete on the red strip at \(ratio):1")
    }

    /// **A KNOWN EXCEPTION, PINNED SO IT CANNOT GET WORSE.**
    ///
    /// White on the Finish green is 2.08:1 on the dark palettes — below the 3:1
    /// every other solid button clears. This is inherited, not introduced: it is
    /// the exact green the app shipped with, and the four looks kept it so the
    /// switch changed nothing about what "go" looks like.
    ///
    /// The fix, when it is wanted, is one value: `success` at `#17A65A` reads
    /// 3.16:1 and is still unmistakably the same green. Until somebody decides
    /// that, this test stops it drifting further down.
    @Test(arguments: AppTheme.allCases)
    func finishButtonIsTheOneKnownWeakPair(theme: AppTheme) {
        let palette = theme.palette
        let name = palette.name
        let ratio = palette.onSolid.contrast(against: palette.success)
        #expect(ratio >= 2.0, "\(name): Finish label at \(ratio):1 — worse than the inherited 2.08")
    }

    // MARK: - The badge alphabet
    //
    // W / D / R / F are a language. They fail by becoming confusable, not by
    // becoming invisible, so the rule is a hue separation and not a contrast.

    @Test(arguments: AppTheme.allCases)
    func accentCannotBeMistakenForASetType(theme: AppTheme) {
        let palette = theme.palette
        let name = palette.name
        let badges = [("W", palette.warmup), ("D", palette.dropSet),
                      ("R", palette.restPause), ("F", palette.destructive)]
        for (glyph, badge) in badges {
            let separation = palette.accent.hueSeparation(from: badge)
            #expect(separation >= 35,
                    "\(name): accent \(palette.accent.hexString) is only \(separation)° from the \(glyph) badge — a 28pt square cannot carry that distinction")
        }
    }

    @Test(arguments: AppTheme.allCases)
    func theBadgesCannotBeMistakenForEachOther(theme: AppTheme) {
        let palette = theme.palette
        let name = palette.name
        let badges = [("W", palette.warmup), ("D", palette.dropSet),
                      ("R", palette.restPause), ("F", palette.destructive)]
        for i in badges.indices {
            for j in badges.indices where j > i {
                let separation = badges[i].1.hueSeparation(from: badges[j].1)
                #expect(separation >= 35,
                        "\(name): \(badges[i].0) and \(badges[j].0) are \(separation)° apart")
            }
        }
    }

    @Test(arguments: AppTheme.allCases)
    func badgeGlyphsAreReadableOnTheirChip(theme: AppTheme) {
        let palette = theme.palette
        let name = palette.name
        // The glyph is drawn on `fieldFill`, not on the surface — see
        // SetTypeBadge.
        let badges = [("W", palette.warmup), ("D", palette.dropSet),
                      ("R", palette.restPause), ("F", palette.destructive)]
        for (glyph, badge) in badges {
            let ratio = badge.contrast(against: palette.fieldFill)
            #expect(ratio >= 3, "\(name): the \(glyph) glyph reads \(ratio):1 on its chip")
        }
    }

    // MARK: - Go vs stop

    @Test(arguments: AppTheme.allCases)
    func finishAndSaveCannotCollapseIntoOneColour(theme: AppTheme) {
        let palette = theme.palette
        let name = palette.name
        // Finish is solid success; Save and Start Workout are solid accent. Two
        // affirmative buttons that look alike is how somebody ends a session
        // they meant to save.
        let separation = palette.accent.hueSeparation(from: palette.success)
        #expect(separation >= 40, "\(name): accent is \(separation)° from the Finish green")
    }

    @Test(arguments: AppTheme.allCases)
    func noticeStripIsReadable(theme: AppTheme) {
        let palette = theme.palette
        let name = palette.name
        let ratio = palette.noticeText.contrast(against: palette.notice)
        #expect(ratio >= 4.5, "\(name): Health strip text at \(ratio):1")
    }

    @Test(arguments: AppTheme.allCases)
    func noticeIsNotWarmupOrange(theme: AppTheme) {
        let palette = theme.palette
        let name = palette.name
        // A Settings banner that looks like a W set is a bug that has been
        // fixed once already.
        #expect(palette.notice != palette.warmup, "\(name): the notice strip reuses the warm-up badge colour")
    }

    // MARK: - The language holds across looks

    @Test func darkPalettesShareOneBadgeAlphabet() {
        // Gunmetal, Bunker and Orchid change chrome only. A badge that shifted
        // when the chrome did would make W mean "warm-up, in this theme".
        let darks: [Palette] = [.gunmetal, .bunker, .orchid]
        for palette in darks.dropFirst() {
            #expect(palette.warmup == Palette.gunmetal.warmup)
            #expect(palette.dropSet == Palette.gunmetal.dropSet)
            #expect(palette.restPause == Palette.gunmetal.restPause)
            #expect(palette.destructive == Palette.gunmetal.destructive)
            #expect(palette.notice == Palette.gunmetal.notice)
            #expect(palette.noticeText == Palette.gunmetal.noticeText)
        }
    }

    @Test func blushMovesBadgeLightnessButKeepsBadgeHue() {
        // The one palette that had to retune the alphabet, because #FFA13B on
        // cream is a rumour. Orange stays orange; it only gets dark enough to
        // read.
        let pairs = [(Palette.blush.warmup, Palette.gunmetal.warmup),
                     (Palette.blush.dropSet, Palette.gunmetal.dropSet),
                     (Palette.blush.restPause, Palette.gunmetal.restPause),
                     (Palette.blush.destructive, Palette.gunmetal.destructive)]
        for (light, dark) in pairs {
            #expect(light.hueSeparation(from: dark) <= 20,
                    "\(light.hexString) is a different hue from \(dark.hexString), not a darker one")
            #expect(light.relativeLuminance < dark.relativeLuminance,
                    "\(light.hexString) is not darker than \(dark.hexString)")
        }
    }

    // MARK: - The stored choice

    @Test func gunmetalIsWhatANewDeviceWears() {
        #expect(AppTheme.fallback == .gunmetal)
    }

    @Test func storedRawValuesAreStable() {
        // These strings live in UserDefaults on a phone that is being trained
        // on. Renaming a case silently resets somebody's chosen look.
        #expect(AppTheme.gunmetal.rawValue == "gunmetal")
        #expect(AppTheme.bunker.rawValue == "bunker")
        #expect(AppTheme.orchid.rawValue == "orchid")
        #expect(AppTheme.blush.rawValue == "blush")
        #expect(AppTheme.allCases.count == 4)
    }

    @Test func onlyBlushAsksForLightSystemChrome() {
        for theme in AppTheme.allCases {
            let expected: ColorScheme = theme == .blush ? .light : .dark
            #expect(theme.palette.colorScheme == expected, "\(theme.name) asks for the wrong system chrome")
        }
    }

    // MARK: - Colour arithmetic itself

    @Test func hexRoundTrips() {
        #expect(PaletteColor(0x35A7FF).hexString == "#35A7FF")
        #expect(PaletteColor(0x000000).hexString == "#000000")
        #expect(PaletteColor(0xFFFFFF).hexString == "#FFFFFF")
    }

    @Test func contrastIsSymmetricAndBounded() {
        let white = PaletteColor(0xFFFFFF), black = PaletteColor(0x000000)
        #expect(abs(white.contrast(against: black) - 21) < 0.01)
        #expect(abs(black.contrast(against: white) - 21) < 0.01)
        #expect(abs(white.contrast(against: white) - 1) < 0.01)
    }

    @Test func hueSeparationTakesTheShortWayRound() {
        let red = PaletteColor(0xFF0000)      // 0°
        let magenta = PaletteColor(0xFF00FF)  // 300°
        #expect(abs(red.hueSeparation(from: magenta) - 60) < 0.01)
    }
}
