//
//  AuthFormValidationTests.swift
//  MCPStrengthTests
//
//  Covers the sign-in form's validation rules and the backend-error wording.
//
//  These are the parts of sign-in with actual rules in them. The screen itself
//  can only be checked structurally, and the network round trip cannot be
//  checked here at all — which is exactly why the rules live outside the view.
//
//  Two properties matter more than the individual cases:
//
//    * Validation must be LOOSER than the server's, never stricter. A form that
//      refuses a password the backend would have accepted leaves the user with
//      no way to tell who is objecting.
//    * An error message must never be the raw error. Several tests below assert
//      on what the user is told, not on what was thrown.
//

import Testing
import Foundation
@testable import MCPStrength

struct AuthFormValidationTests {

    // MARK: - Email

    @Test func acceptsAnOrdinaryAddress() {
        #expect(AuthFormValidator.validateEmail("drake@drakebuilds.biz") == nil)
    }

    @Test func acceptsPlusAddressingAndSubdomains() {
        // Both are valid and both are what a naive regex rejects. The cost of
        // rejecting them is a user who cannot sign up at all.
        #expect(AuthFormValidator.validateEmail("drake+gym@mail.example.co.uk") == nil)
    }

    @Test func rejectsEmpty() {
        #expect(AuthFormValidator.validateEmail("") == .emailEmpty)
        #expect(AuthFormValidator.validateEmail("   ") == .emailEmpty)
    }

    @Test func rejectsObviousTypos() {
        #expect(AuthFormValidator.validateEmail("drake") == .emailMalformed)
        #expect(AuthFormValidator.validateEmail("drake@") == .emailMalformed)
        #expect(AuthFormValidator.validateEmail("@example.com") == .emailMalformed)
        #expect(AuthFormValidator.validateEmail("drake@example") == .emailMalformed)
        #expect(AuthFormValidator.validateEmail("a@b.") == .emailMalformed)
        #expect(AuthFormValidator.validateEmail("two@at@example.com") == .emailMalformed)
        #expect(AuthFormValidator.validateEmail("has space@example.com") == .emailMalformed)
    }

    // MARK: - Normalisation
    //
    // The case-folding here is not cosmetic. Signing up as "Drake@x.com" and
    // later signing in as "drake@x.com" must reach the same account, or a
    // user's entire history appears to have vanished.

    @Test func normalisationLowercasesAndTrims() {
        #expect(AuthFormValidator.normalized(email: "  Drake@Example.COM ") == "drake@example.com")
    }

    @Test func normalisationIsIdempotent() {
        let once = AuthFormValidator.normalized(email: " Drake@Example.com ")
        #expect(AuthFormValidator.normalized(email: once) == once)
    }

    // MARK: - Sign in

    @Test func signInAcceptsAnyNonEmptyPassword() {
        // Length is NOT checked on sign-in. An existing account may predate any
        // rule we invent, and refusing to even attempt it would lock the owner
        // out of their own data with no recourse in the app.
        #expect(AuthFormValidator.validateSignIn(email: "a@b.com", password: "x") == nil)
    }

    @Test func signInRequiresAPassword() {
        #expect(
            AuthFormValidator.validateSignIn(email: "a@b.com", password: "") == .passwordEmpty
        )
    }

    @Test func signInChecksEmailBeforePassword() {
        // With both wrong, the email complaint wins — it is the field the user
        // reaches first, and reporting the last error sends them up the form.
        #expect(AuthFormValidator.validateSignIn(email: "nope", password: "") == .emailMalformed)
    }

    // MARK: - Sign up

    @Test func signUpAcceptsAMatchingPairAtTheMinimum() {
        let minimum = String(repeating: "a", count: AuthFormValidator.minimumPasswordLength)
        #expect(
            AuthFormValidator.validateSignUp(
                email: "a@b.com", password: minimum, confirmation: minimum
            ) == nil
        )
    }

    @Test func signUpRejectsOneBelowTheMinimum() {
        let short = String(repeating: "a", count: AuthFormValidator.minimumPasswordLength - 1)
        #expect(
            AuthFormValidator.validateSignUp(
                email: "a@b.com", password: short, confirmation: short
            ) == .passwordTooShort(minimum: AuthFormValidator.minimumPasswordLength)
        )
    }

    @Test func signUpRejectsAMismatch() {
        #expect(
            AuthFormValidator.validateSignUp(
                email: "a@b.com", password: "longenough", confirmation: "longenougi"
            ) == .confirmationMismatch
        )
    }

    @Test func lengthIsReportedBeforeMismatch() {
        // A short password typed differently twice is wrong in two ways. Report
        // the length, because fixing the mismatch alone leaves it still
        // rejected — and the user has no idea why the second attempt failed.
        #expect(
            AuthFormValidator.validateSignUp(
                email: "a@b.com", password: "abc", confirmation: "xyz"
            ) == .passwordTooShort(minimum: AuthFormValidator.minimumPasswordLength)
        )
    }

    @Test func everyIssueSaysSomething() {
        let issues: [AuthFieldIssue] = [
            .emailEmpty, .emailMalformed, .passwordEmpty,
            .passwordTooShort(minimum: 6), .confirmationMismatch,
        ]
        for issue in issues {
            #expect(!issue.message.isEmpty, "\(issue) has no message")
            // No developer vocabulary in anything a user reads.
            let lowered = issue.message.lowercased()
            #expect(!lowered.contains("nil"))
            #expect(!lowered.contains("error"))
            #expect(!lowered.contains("invalid"))
        }
    }

    // MARK: - Error wording

    private struct StubError: Error, CustomStringConvertible {
        let description: String
    }

    @Test func wrongCredentialsDoNotRevealWhetherTheAccountExists() {
        let message = AuthErrorPresenter.message(
            for: StubError(description: "AuthError.api(message: \"Invalid login credentials\")")
        )
        // Whether a given email has an account here is not something a stranger
        // at the sign-in screen gets to find out.
        let lowered = message.lowercased()
        #expect(!lowered.contains("no account"))
        #expect(!lowered.contains("not found"))
        #expect(!lowered.contains("wrong password"))
        #expect(message.contains("do not match"))
    }

    @Test func unconfirmedEmailSaysWhatToDo() {
        let message = AuthErrorPresenter.message(
            for: StubError(description: "AuthError.api(message: \"Email not confirmed\")")
        )
        #expect(message.lowercased().contains("confirmation link"))
    }

    @Test func duplicateSignUpPointsAtSigningIn() {
        let message = AuthErrorPresenter.message(
            for: StubError(description: "AuthError.api(message: \"User already registered\")")
        )
        #expect(message.lowercased().contains("signing in"))
    }

    // These are `URLError`s passed as `any Error`, exactly as they arrive from
    // the client — NOT strings describing them. That distinction is the point:
    // this test first failed because the presenter was matching
    // `String(describing:)` against "network"/"offline", and a URLError
    // stringifies to `URLError(_nsError: … Code=-1009 "(null)")`, which
    // contains no such word. Every offline user got the generic failure.
    @Test(arguments: [
        URLError.Code.notConnectedToInternet,
        .networkConnectionLost,
        .timedOut,
        .cannotConnectToHost,
        .dataNotAllowed,
    ])
    func offlineReassuresThatLocalDataIsSafe(code: URLError.Code) {
        let message = AuthErrorPresenter.message(for: URLError(code) as any Error)
        // The true and useful thing to say. A local-first app losing its
        // connection has NOT lost anything.
        #expect(message.lowercased().contains("saved on this phone"))
    }

    @Test func aRealServerRejectionIsNotMistakenForBeingOffline() {
        // `.badServerResponse` is a URLError too, but the server was reached
        // and answered. Telling the user "no connection" would send them to
        // check their wifi over a problem that is not theirs.
        let message = AuthErrorPresenter.message(for: URLError(.badServerResponse) as any Error)
        #expect(!message.lowercased().contains("no connection"))
    }

    @Test func anUnrecognisedErrorNeverLeaksItsInternals() {
        let ugly = StubError(
            description: "PostgrestError(code: \"PGRST301\", hint: nil, details: Optional(\"JWT expired at line 42 of AuthClient.swift\"))"
        )
        let message = AuthErrorPresenter.message(for: ugly)

        // Assert the fallback is REACHED before asserting what it omits —
        // otherwise this passes for the wrong reason if the mapping changes.
        #expect(message == "Something went wrong signing you in. Try again in a moment.")
        #expect(!message.contains("PGRST301"))
        #expect(!message.contains("AuthClient.swift"))
        #expect(!message.contains("JWT"))
    }
}
