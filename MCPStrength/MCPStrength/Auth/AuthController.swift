//
//  AuthController.swift
//  MCPStrength
//
//  Owns "who is signed in", and is the only thing in the app that talks to
//  Supabase auth.
//
//  ## Why there is a `.loading` state
//
//  A signed-in user's session lives in the keychain, and reading it back is
//  asynchronous. Starting in `.signedOut` would flash the sign-in screen on
//  every single launch before snapping to the app — which reads as "it logged
//  me out again" and is the sort of thing people uninstall over. So the app
//  starts in `.loading` and waits for supabase-swift to emit `.initialSession`,
//  which it does exactly once at startup whether or not a session was found.
//
//  ## Why sign-up has its own state
//
//  `signUp` does NOT always sign you in. With email confirmation enabled — the
//  Supabase default, and on for this project — it returns a USER and no
//  session, meaning "we sent an email, go tap the link". Collapsing that into
//  "signed out" produces the worst bug in any sign-up form: you fill it in, you
//  tap the button, it succeeds, and you are returned to the same empty form
//  with nothing to indicate what happened or what to do next.
//

import Foundation
import Observation
import Supabase

/// Who is signed in, as far as the app is concerned.
enum AuthState: Equatable {
    /// Reading the stored session. The launch state; never returned to.
    case loading
    /// No session. Show the sign-in screen.
    case signedOut
    /// A live session. The app proper is reachable.
    case signedIn(userID: UUID, email: String?)
    /// Signed up, waiting on the confirmation email.
    case awaitingConfirmation(email: String)
}

@MainActor
@Observable
final class AuthController {

    private(set) var state: AuthState = .loading

    /// The message under the form. Nil when there is nothing to say.
    private(set) var errorMessage: String?

    /// True while a request is in flight — disables the buttons so a double tap
    /// cannot fire two sign-ups.
    private(set) var isBusy = false

    private let client: SupabaseClient
    private var observationTask: Task<Void, Never>?

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
    }

    // NO deinit CANCELLING THE OBSERVATION, deliberately. Under Swift 6 a
    // `deinit` is nonisolated and cannot touch main-actor state, and the
    // workarounds for that (a nonisolated(unsafe) box, an unstructured
    // detached cancel) buy nothing here: this controller is created once by
    // `MCPStrengthApp` and lives for the whole process. The observation task
    // captures `self` weakly, so it does not keep the controller alive, and it
    // ends on its own when the auth stream finishes.
    //
    // If this type ever becomes something created per-screen, that changes and
    // the task must be cancelled — but then `.task` on the view is the right
    // owner of its lifetime, not `deinit`.

    // MARK: - Session observation

    /// Begin watching the session. Call once, from the app root.
    ///
    /// Everything that changes `state` to signed-in or signed-out flows through
    /// HERE rather than through the return value of `signIn`/`signOut`. One
    /// path in means the UI cannot disagree with the client about whether there
    /// is a session — including for the changes the app never asked for, like a
    /// refresh token that has expired or been revoked.
    func start() {
        guard observationTask == nil else { return }

        observationTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in client.auth.authStateChanges {
                self.apply(event: event, session: session)
            }
        }
    }

    private func apply(event: AuthChangeEvent, session: Session?) {
        switch event {
        case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
            if let session {
                state = .signedIn(userID: session.user.id, email: session.user.email)
                errorMessage = nil
            } else if case .awaitingConfirmation = state {
                // `.initialSession` with no session arriving while the
                // confirmation notice is up must not wipe it. The user has not
                // been signed out — they were never signed in yet.
                break
            } else {
                state = .signedOut
            }

        case .signedOut:
            state = .signedOut

        default:
            // passwordRecovery, mfaChallengeVerified and any case added by a
            // future version of supabase-swift. Ignoring an unrecognised event
            // is right: guessing at its meaning is how a user gets signed out
            // by an event that meant nothing of the kind.
            break
        }
    }

    // MARK: - Actions

    func signIn(email: String, password: String) async {
        if let issue = AuthFormValidator.validateSignIn(email: email, password: password) {
            errorMessage = issue.message
            return
        }

        await perform {
            _ = try await self.client.auth.signIn(
                email: AuthFormValidator.normalized(email: email),
                password: password
            )
            // No state assignment here on purpose — the auth-state stream is
            // the single path in. See `start()`.
        }
    }

    func signUp(email: String, password: String, confirmation: String) async {
        if let issue = AuthFormValidator.validateSignUp(
            email: email, password: password, confirmation: confirmation
        ) {
            errorMessage = issue.message
            return
        }

        let normalized = AuthFormValidator.normalized(email: email)

        await perform {
            let response = try await self.client.auth.signUp(
                email: normalized,
                password: password
            )

            switch response {
            case .session:
                // Email confirmation is off; the stream will deliver the
                // session and move the app on.
                break
            case .user:
                // Confirmation is required. Nothing arrives on the stream until
                // the link is tapped, so this is the one state the stream
                // cannot tell us about and the one we must set ourselves.
                self.state = .awaitingConfirmation(email: normalized)
            }
        }
    }

    func signOut() async {
        await perform {
            try await self.client.auth.signOut()
        }
    }

    func sendPasswordReset(email: String) async -> Bool {
        if let issue = AuthFormValidator.validateEmail(email) {
            errorMessage = issue.message
            return false
        }
        var sent = false
        await perform {
            try await self.client.auth.resetPasswordForEmail(
                AuthFormValidator.normalized(email: email)
            )
            sent = true
        }
        return sent
    }

    /// Return to the form from the confirmation notice — a mistyped address is
    /// otherwise a dead end that only a force-quit escapes.
    func returnToSignIn() {
        state = .signedOut
        errorMessage = nil
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Shared request wrapper

    private func perform(_ work: @escaping () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            try await work()
        } catch {
            errorMessage = AuthErrorPresenter.message(for: error)
        }
    }
}
