//
//  ThemeStore.swift
//  MCPStrength
//
//  Owns "which look is on". Small on purpose: it holds the choice, writes it
//  down, and points `Theme` at the matching palette.
//
//  WHY THE CHOICE IS LOCAL AND NOT SYNCED. Weight unit and calorie rate live in
//  `AppSettings` and travel to the server, because they change what a NUMBER
//  MEANS and two devices disagreeing about that is a data problem. A palette
//  changes nothing about the data — it is a per-device preference in the same
//  family as brightness, and syncing it would mean a schema change, a
//  migration, and a phone repainting itself because an iPad was recoloured.
//  `UserDefaults`, deliberately.
//

import SwiftUI
import Observation

@Observable
final class ThemeStore {

    private static let storageKey = "appTheme"

    private let defaults: UserDefaults

    /// The live choice. Setting it writes the value down and repaints the app.
    var selected: AppTheme {
        didSet {
            guard selected != oldValue else { return }
            defaults.set(selected.rawValue, forKey: Self.storageKey)
            Theme.use(selected)
        }
    }

    var palette: Palette { selected.palette }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // An unrecognised or absent stored value is not an error worth
        // reporting — it is a fresh install, or a build that dropped a palette.
        // Both want the default rather than a crash.
        let stored = defaults.string(forKey: Self.storageKey)
        let resolved = stored.flatMap(AppTheme.init(rawValue:)) ?? .fallback
        self.selected = resolved
        // Pushed here rather than in `didSet`, which does not run for the
        // initial assignment. Without this line a relaunch paints the default
        // palette while the picker shows the stored one.
        Theme.use(resolved)
    }
}
