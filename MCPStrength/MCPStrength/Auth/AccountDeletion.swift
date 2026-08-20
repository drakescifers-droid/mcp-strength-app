//
//  AccountDeletion.swift
//  MCPStrength
//
//  In-app account deletion: the server forgets the login, this phone forgets
//  the user's rows. MCP never uses the service-role client; this Edge Function
//  is the one place that does, because deleting `auth.users` cannot go through
//  RLS.
//

import Foundation
import SwiftData

enum AccountDeletion {

    /// Hosted function. Same project as sync; JWT is the user's session.
    static let endpoint = SupabaseConfig.url
        .appending(path: "functions/v1/delete-account")

    /// Ask the server to delete this login. The local wipe is a separate step
    /// so a failed network call does not empty the phone.
    static func requestServerDeletion(
        accessToken: String,
        session: URLSession = .shared
    ) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AccountDeletionError.notHTTP
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AccountDeletionError.server(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
    }

    /// Tombstone every user-owned row on this phone. Seeded exercises and
    /// measurement types stay — they are the library, not this account.
    ///
    /// Walks through `SoftDelete` so cascades stay honest. Does not call
    /// `context.delete`.
    static func wipeLocalUserData(in context: ModelContext, at date: Date = .now) throws {
        let workouts = try context.fetch(FetchDescriptor<Workout>())
        for workout in workouts where workout.deletedAt == nil {
            SoftDelete.workout(workout, at: date)
        }

        let templates = try context.fetch(FetchDescriptor<Template>())
        for template in templates where template.deletedAt == nil {
            SoftDelete.template(template, at: date)
        }

        let folders = try context.fetch(FetchDescriptor<TemplateFolder>())
        for folder in folders where folder.deletedAt == nil {
            SoftDelete.folder(folder, at: date)
        }

        let leftoverDays = try context.fetch(FetchDescriptor<ProgramDay>())
        for day in leftoverDays where day.deletedAt == nil {
            day.markDeleted(at: date)
        }

        let entries = try context.fetch(FetchDescriptor<MeasurementEntry>())
        for entry in entries where entry.deletedAt == nil {
            SoftDelete.measurementEntry(entry, at: date)
        }

        let preferences = try context.fetch(FetchDescriptor<ExercisePreference>())
        for preference in preferences where preference.deletedAt == nil {
            preference.markDeleted(at: date)
        }

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        for exercise in exercises where exercise.deletedAt == nil && exercise.isCustom {
            exercise.markDeleted(at: date)
        }

        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        for row in settings where row.deletedAt == nil {
            row.markDeleted(at: date)
        }

        try context.save()
    }
}

enum AccountDeletionError: Error, Equatable {
    case notHTTP
    case server(status: Int, body: String?)
    case notSignedIn
}

enum AccountDeletionPresenter {
    static func message(for error: any Error) -> String {
        if let urlError = error as? URLError,
           urlError.code == .notConnectedToInternet
            || urlError.code == .networkConnectionLost
            || urlError.code == .timedOut
            || urlError.code == .cannotConnectToHost {
            return "No connection. Try again when you are online — nothing on this phone was deleted."
        }
        if case AccountDeletionError.server = error {
            return "The server could not delete the account. Nothing on this phone was deleted."
        }
        return "Could not delete the account. Nothing on this phone was deleted."
    }
}
