//
//  AuthScreen.swift
//  MCPStrength
//
//  The sign-in / create-account screen, and the two states that surround it.
//
//  This is the first thing anyone sees, and for an app whose entire job is
//  logging a set in the ninety seconds between them, that is a cost. It is
//  worth paying only because every row the backend accepts must be stamped with
//  an owner: row-level security filters on `auth.uid()`, so there is no syncing
//  a single workout before the app knows who you are. See docs/05-database.md.
//
//  `.textContentType` is set on every field so iCloud Keychain and 1Password
//  offer to fill and to SAVE. Skipping it is a silent papercut: the password
//  never gets offered for saving, and the user is left to remember one they
//  chose in a hurry.
//

import SwiftUI

// MARK: - Root gate

/// Chooses between the sign-in flow and the app, based on session state.
struct AuthGate: View {
    @Environment(AuthController.self) private var auth
    @Environment(OnboardingStore.self) private var onboarding

    var body: some View {
        // DEBUG-only, and only with an explicit launch argument. See
        // Auth/UIPreviewMode.swift for why this exists and why it cannot reach
        // a released build. It skips the GATE, not authentication — there is no
        // session, so every request would still be rejected by RLS.
        if UIPreviewMode.isEnabled {
            ContentView()
        } else {
            gatedContent
        }
    }

    @ViewBuilder
    private var gatedContent: some View {
        switch auth.state {
        case .loading:
            AuthLoadingView()
        case .signedOut:
            AuthScreen()
        case .awaitingConfirmation(let email):
            ConfirmationPendingView(email: email)
        case .signedIn:
            if onboarding.isComplete {
                ContentView()
            } else {
                OnboardingFlow()
            }
        }
    }
}

// MARK: - Launch

/// Shown for the moment it takes to read the stored session.
///
/// Deliberately NOT a spinner on an empty screen: this appears on every launch,
/// including the overwhelmingly common one where a session is found and it is
/// gone in under a second. A spinner would read as work being done.
private struct AuthLoadingView: View {
    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Sign in / create account

struct AuthScreen: View {
    @Environment(AuthController.self) private var auth

    private enum Mode: String, CaseIterable {
        case signIn = "Sign In"
        case signUp = "Create Account"
    }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var resetNotice: String?

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.spacious) {
                    header
                    modePicker
                    fields
                    messages
                    submitButton

                    if mode == .signIn {
                        forgotPasswordButton
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, Spacing.spacious)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: Spacing.compact) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
            Text("MCP Strength")
                .font(Typography.title)
                .foregroundStyle(Theme.textPrimary)
            Text("Your training, backed up and on every device.")
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, Spacing.comfortable)
    }

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .onChange(of: mode) { _, _ in
            // Clearing on switch stops "those passwords do not match" hanging
            // over a form that no longer has a confirmation field in it.
            auth.clearError()
            resetNotice = nil
            confirmation = ""
        }
    }

    private var fields: some View {
        VStack(spacing: Spacing.comfortable) {
            AuthField(
                title: "Email",
                text: $email,
                contentType: .username,
                keyboard: .emailAddress
            )

            AuthField(
                title: "Password",
                text: $password,
                contentType: mode == .signUp ? .newPassword : .password,
                isSecure: true
            )

            if mode == .signUp {
                AuthField(
                    title: "Confirm password",
                    text: $confirmation,
                    contentType: .newPassword,
                    isSecure: true
                )
            }
        }
    }

    @ViewBuilder
    private var messages: some View {
        if let error = auth.errorMessage {
            Text(error)
                .font(Typography.secondary)
                .foregroundStyle(Theme.destructive)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let resetNotice {
            Text(resetNotice)
                .font(Typography.secondary)
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var submitButton: some View {
        Button {
            Task {
                resetNotice = nil
                switch mode {
                case .signIn:
                    await auth.signIn(email: email, password: password)
                case .signUp:
                    await auth.signUp(
                        email: email, password: password, confirmation: confirmation
                    )
                }
            }
        } label: {
            if auth.isBusy {
                ProgressView().tint(Theme.textPrimary)
            } else {
                Text(mode == .signIn ? "Sign In" : "Create Account")
            }
        }
        .buttonStyle(.primaryAction)
        .disabled(auth.isBusy)
    }

    private var forgotPasswordButton: some View {
        Button("Forgot password?") {
            Task {
                if await auth.sendPasswordReset(email: email) {
                    resetNotice = "Check your email for a link to reset your password."
                }
            }
        }
        .font(Typography.secondary)
        .foregroundStyle(Theme.accent)
        .disabled(auth.isBusy)
    }
}

// MARK: - Field

/// One labelled input, styled from the tokens.
private struct AuthField: View {
    let title: String
    @Binding var text: String
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var isSecure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text(title)
                .font(Typography.secondary)
                .foregroundStyle(Theme.textSecondary)

            Group {
                if isSecure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                }
            }
            .font(Typography.body)
            .foregroundStyle(Theme.textPrimary)
            .textContentType(contentType)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(Spacing.comfortable)
            .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.chip))
        }
    }
}

// MARK: - Waiting on the confirmation email

/// Shown after sign-up when confirmation is required.
///
/// This screen exists because `signUp` succeeding does NOT mean signed in. Its
/// whole job is to say what happened and what to do next; without it, a
/// successful sign-up looks identical to a form that quietly did nothing.
private struct ConfirmationPendingView: View {
    let email: String
    @Environment(AuthController.self) private var auth

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()

            VStack(spacing: Spacing.spacious) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.accent)

                Text("Check your email")
                    .font(Typography.title)
                    .foregroundStyle(Theme.textPrimary)

                VStack(spacing: Spacing.compact) {
                    Text("We sent a confirmation link to")
                        .foregroundStyle(Theme.textSecondary)
                    Text(email)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Tap it — it should open this app — then you can sign in.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(Typography.secondary)
                .multilineTextAlignment(.center)

                // The way back. A typo in the address is otherwise a dead end
                // that only force-quitting the app escapes.
                Button("Use a different email") {
                    auth.returnToSignIn()
                }
                .buttonStyle(.tintedAccent)
            }
            .padding(.horizontal, Spacing.screenMargin)
        }
    }
}

// MARK: - Previews

#Preview("Sign in") {
    AuthScreen()
        .environment(AuthController())
        .preferredColorScheme(.dark)
}
