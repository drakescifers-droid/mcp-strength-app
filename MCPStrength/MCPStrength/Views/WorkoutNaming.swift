//
//  WorkoutNaming.swift
//  MCPStrength
//
//  The time-of-day name generator for quick workouts — the ones started without
//  a template. Lifted out of ContentView so it is unit-testable: the rule
//  (docs/01-data-model.md § Workouts) is that the generated name is the FALLBACK
//  for the no-template path; a workout started from a template takes the
//  template's name instead (see TemplateStarter).
//

import Foundation

enum WorkoutNaming {

    /// "Afternoon Workout" style name from the time of day. Never empty.
    static func quickWorkoutName(for date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let part: String
        switch hour {
        case 5..<12:  part = "Morning"
        case 12..<17: part = "Afternoon"
        case 17..<21: part = "Evening"
        default:      part = "Night"
        }
        return "\(part) Workout"
    }
}
