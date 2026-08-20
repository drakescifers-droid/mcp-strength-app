//
//  AuthRedirectTests.swift
//  MCPStrengthTests
//

import Testing
import Foundation
@testable import MCPStrength

struct AuthRedirectTests {

    @Test func httpsCallbackOnApexIsOurs() {
        let url = URL(string: "https://mcpstrength.com/auth/callback#access_token=x")!
        #expect(SupabaseConfig.isAuthCallback(url))
    }

    @Test func httpsCallbackOnWwwIsOurs() {
        let url = URL(string: "https://www.mcpstrength.com/auth/callback")!
        #expect(SupabaseConfig.isAuthCallback(url))
    }

    @Test func customSchemeCallbackIsOurs() {
        let url = URL(string: "mcpstrength://auth/callback?code=abc")!
        #expect(SupabaseConfig.isAuthCallback(url))
    }

    @Test func randomHttpsIsNotOurs() {
        let url = URL(string: "https://mcpstrength.com/privacy")!
        #expect(!SupabaseConfig.isAuthCallback(url))
    }

    @Test func otherCustomSchemeIsNotOurs() {
        let url = URL(string: "https://example.com/auth/callback")!
        #expect(!SupabaseConfig.isAuthCallback(url))
    }

    @Test func openSchemeIsNotAnAuthCallback() {
        let url = URL(string: "mcpstrength://open")!
        #expect(!SupabaseConfig.isAuthCallback(url))
    }
}
