//
//  SupabaseConfig.swift
//  MCPStrength
//
//  The connection to the hosted backend, and the app's single SupabaseClient.
//
//  ## Why the key below is in the repository on purpose
//
//  `publishableKey` is the PUBLISHABLE key. It is designed to be embedded in
//  client apps and is sent with every request the app makes — anyone with the
//  app on their phone can read it out of the binary in about a minute. Hiding
//  it would buy nothing and would cost the ability to build from a fresh
//  checkout.
//
//  What actually protects the data is row-level security, which is enabled on
//  all twelve tables and asserted by supabase/tests/02_rls_test.sql. Holding
//  this key gets you exactly as far as the sign-in screen and no further: every
//  policy filters on `auth.uid()`, and `anon` has been revoked from every table
//  in the schema.
//
//  ## The key that must NEVER appear here
//
//  The SECRET key (`sb_secret_…` / `service_role`) bypasses row-level security
//  entirely. It belongs only on a server. If it ever lands in this file, in an
//  Xcode scheme, or in a commit, treat it as compromised and rotate it in the
//  Supabase dashboard — do not merely delete the line, because git remembers.
//

import Foundation
import Supabase

/// Connection details for the hosted Supabase project.
enum SupabaseConfig {
    /// Project: `mcp-strength` (ref `knrmembtnmgddzyyvyvq`), us-east-1.
    static let url = URL(string: "https://knrmembtnmgddzyyvyvq.supabase.co")!

    /// The publishable key — safe to ship, see the file comment.
    static let publishableKey = "sb_publishable_Br0kmmH0kncQRLuXxdl3EQ_M6liLV2S"

    /// Where confirmation and password-reset links must land. The site page
    /// hands the same URL to the app (`mcpstrength://auth/callback`).
    static let authCallbackURL = URL(string: "https://mcpstrength.com/auth/callback")!

    /// True for the HTTPS universal link and the custom-scheme fallback.
    static func isAuthCallback(_ url: URL) -> Bool {
        if url.scheme == "mcpstrength" {
            return url.host == "auth"
        }
        guard url.host == "mcpstrength.com" || url.host == "www.mcpstrength.com" else {
            return false
        }
        return url.path.hasPrefix("/auth/callback")
    }
}

/// The app's single `SupabaseClient`.
///
/// One instance, deliberately. The client owns the auth session — including the
/// refresh timer that keeps a signed-in user signed in — and a second instance
/// would run a second timer against the same stored session, with two
/// independent ideas of when the token expires.
///
/// The session itself is persisted by supabase-swift's default local storage,
/// which on Apple platforms is the KEYCHAIN, not UserDefaults. That matters:
/// the stored value is a refresh token, and a refresh token is a credential.
/// Verified against `AuthLocalStorage.defaultLocalStorage` in supabase-swift
/// 2.55.1 rather than assumed.
enum SupabaseClientProvider {
    /// `nonisolated` because this target builds with
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would otherwise put
    /// this property on the main actor — and a default argument (as in
    /// `AuthController.init(client:)`) is evaluated in a NONISOLATED context,
    /// so referring to it there is a warning today and an error in a later
    /// Swift version.
    ///
    /// Safe because `SupabaseClient` is declared `Sendable` upstream: it is
    /// built to be shared across actors, which is the whole reason one instance
    /// can serve the whole app.
    nonisolated static let shared = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.publishableKey
    )
}
