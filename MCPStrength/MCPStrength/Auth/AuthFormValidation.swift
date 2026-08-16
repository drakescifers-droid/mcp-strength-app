//
//  AuthFormValidation.swift
//  MCPStrength
//
//  Field validation for the sign-in form, and the mapping from a backend auth
//  error to a sentence a human can act on.
//
//  This lives outside the view for the same reason RepRangeParser does: it is
//  the part with rules, and rules are the part worth testing. A view can only
//  be checked structurally.
//
//  ## The client is NOT the authority
//
//  These checks exist to catch the obvious before a network round trip — an
//  empty box, a missing @, a password typed differently twice. The SERVER
//  decides what is actually acceptable, and its answer can change without this
//  file knowing (a password policy is a project setting). So validation here is
//  deliberately LOOSER than the server's, never stricter: anything this file
//  rejects would certainly have failed, and anything it allows may still be
//  refused, in which case `AuthErrorPresenter` turns that refusal into English.
//
//  Being stricter than the server is the failure worth avoiding. It produces a
//  form that refuses a password the backend would have accepted, with no way
//  for the user to tell who is objecting or why.
//

import Foundation

// MARK: - Field validation

/// What the form found wrong, if anything. One case per thing worth saying.
enum AuthFieldIssue: Equatable, Sendable {
    case emailEmpty
    case emailMalformed
    case passwordEmpty
    case passwordTooShort(minimum: Int)
    case confirmationMismatch

    /// The message shown under the form. Written as a statement of what to do,
    /// not a diagnosis — "Passwords do not match", not "Validation error 3".
    var message: String {
        switch self {
        case .emailEmpty:
            "Enter your email address."
        case .emailMalformed:
            "That does not look like an email address."
        case .passwordEmpty:
            "Enter your password."
        case .passwordTooShort(let minimum):
            "Your password needs at least \(minimum) characters."
        case .confirmationMismatch:
            "Those passwords do not match."
        }
    }
}

enum AuthFormValidator {

    /// Supabase's own default minimum. Kept as a named constant so the reason
    /// for the number is findable: it is the SERVER's rule, mirrored here only
    /// to save a round trip. If the project's password policy is raised in the
    /// dashboard, the server starts rejecting passwords this file still allows
    /// — which is the safe direction, and `AuthErrorPresenter` handles the
    /// resulting `weakPassword` error.
    static let minimumPasswordLength = 6

    /// Validate a sign-in attempt (email + password, no confirmation field).
    static func validateSignIn(email: String, password: String) -> AuthFieldIssue? {
        if let issue = validateEmail(email) { return issue }
        if password.isEmpty { return .passwordEmpty }
        return nil
    }

    /// Validate a sign-up attempt, including the confirmation field.
    static func validateSignUp(
        email: String,
        password: String,
        confirmation: String
    ) -> AuthFieldIssue? {
        if let issue = validateEmail(email) { return issue }
        if password.isEmpty { return .passwordEmpty }
        if password.count < minimumPasswordLength {
            return .passwordTooShort(minimum: minimumPasswordLength)
        }
        // Checked AFTER length, so retyping a too-short password reports the
        // real problem rather than sending the user round the loop twice.
        if password != confirmation { return .confirmationMismatch }
        return nil
    }

    /// Deliberately permissive. A full RFC 5322 address is far stranger than
    /// anyone expects, and a clever regex here rejects valid addresses — which
    /// looks to the user like the app is broken and has no workaround. The only
    /// job is catching a blank box and an obvious typo; the server, and then
    /// the confirmation email, are what really establish that an address works.
    static func validateEmail(_ email: String) -> AuthFieldIssue? {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .emailEmpty }

        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              parts[1].contains("."),
              !parts[1].hasPrefix("."),
              !parts[1].hasSuffix("."),
              !trimmed.contains(" ")
        else {
            return .emailMalformed
        }
        return nil
    }

    /// Email as it should be SENT: trimmed and lowercased.
    ///
    /// Addresses are case-insensitive in practice, and a phone keyboard loves
    /// to capitalise the first letter. Without this, signing up as
    /// "Drake@x.com" and later signing in as "drake@x.com" can look like two
    /// different accounts — the failure mode where a user's history appears to
    /// have vanished.
    static func normalized(email: String) -> String {
        email.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

// MARK: - Turning backend errors into sentences

/// Maps an error from the auth backend to something worth showing.
///
/// Raw errors here are JSON blobs and HTTP codes. Showing one to a user is the
/// same class of mistake as displaying a fabricated zero: it looks like
/// information and carries none. Every branch below is a case where the user
/// can actually DO something differently.
enum AuthErrorPresenter {

    /// Connection failures worth calling "you are offline" rather than "we
    /// broke". All are conditions where retrying later genuinely works.
    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .networkConnectionLost,
        .timedOut,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed,
        .internationalRoamingOff,
        .dataNotAllowed,
        .secureConnectionFailed,
    ]

    static func message(for error: any Error) -> String {
        // TYPED CHECK FIRST, and this ordering is the whole lesson of the bug
        // that produced it. This started out matching `String(describing:)`
        // against "network"/"offline"/"timed out", which looks reasonable and
        // silently never fires: a URLError stringifies to
        // `URLError(_nsError: Error Domain=NSURLErrorDomain Code=-1009 "(null)")`
        // — no such word anywhere in it. Every offline user would have been
        // told "something went wrong", the one message that is both unhelpful
        // and false, when the true answer is that nothing was lost.
        if let urlError = error as? URLError, offlineCodes.contains(urlError.code) {
            return "No connection. Your workouts are still saved on this phone."
        }

        let raw = String(describing: error).lowercased()

        // Wrong email or wrong password. Deliberately does NOT say which:
        // "no account with that email" tells anyone who asks whether a given
        // person has an account here, and that is health-adjacent data.
        if raw.contains("invalid login credentials") || raw.contains("invalid_credentials") {
            return "That email and password do not match an account."
        }
        if raw.contains("email not confirmed") || raw.contains("email_not_confirmed") {
            return "Check your email and tap the confirmation link, then sign in."
        }
        if raw.contains("user already registered") || raw.contains("user_already_exists") {
            return "There is already an account with that email. Try signing in instead."
        }
        if raw.contains("weak") && raw.contains("password") {
            return "That password is too easy to guess. Try a longer one."
        }
        if raw.contains("over_email_send_rate_limit") || raw.contains("rate limit") {
            return "Too many attempts just now. Wait a minute and try again."
        }
        // Kept as a backstop for connection failures that arrive WRAPPED —
        // supabase-swift boxes some transport errors rather than rethrowing the
        // URLError, and those do carry readable text.
        if raw.contains("offline") || raw.contains("network connection")
            || raw.contains("timed out") || raw.contains("internet connection") {
            return "No connection. Your workouts are still saved on this phone."
        }

        // The honest fallback. It does not pretend to know what happened, and
        // it does not paste a stack trace at somebody trying to log a workout.
        return "Something went wrong signing you in. Try again in a moment."
    }
}
