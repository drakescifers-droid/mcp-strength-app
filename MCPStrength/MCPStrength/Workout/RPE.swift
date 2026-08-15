//
//  RPE.swift
//  MCPStrength
//
//  RPE (rate of perceived exertion) is the prescribed/actual effort field. The
//  vocabulary is fixed and comes from a real lifting API: 6, 7, 7.5, 8, 8.5,
//  9, 9.5, 10. Out-of-range or non-half-step values are invalid. RPE is
//  OPTIONAL everywhere — most sets will not have one — so an empty RPE is
//  completely normal and must never block saving or completing a set.
//

import Foundation

enum RPE {
    /// The only RPE values the app accepts. Lifters use this exact vocabulary
    /// ("leave one or two in the tank" = 8). 6.5 is intentionally absent.
    static let allowedValues: [Double] = [6, 7, 7.5, 8, 8.5, 9, 9.5, 10]

    /// True iff `value` is one of the accepted RPE steps.
    static func isValid(_ value: Double) -> Bool {
        allowedValues.contains(value)
    }

    /// Render an RPE value for display: whole numbers drop the `.0` (8 not 8.0),
    /// half steps keep one decimal (8.5).
    static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
