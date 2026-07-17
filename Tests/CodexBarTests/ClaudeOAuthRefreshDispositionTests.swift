import Foundation
import Testing
@testable import CodexBarCore

struct ClaudeOAuthRefreshDispositionTests {
    @Test
    func invalid_grant_is_terminal() {
        let data = Data(#"{"error":"invalid_grant"}"#.utf8)
        #expect(ClaudeOAuthCredentialsStore
            .refreshFailureDispositionForTesting(statusCode: 400, data: data) == "terminalInvalidGrant")
    }

    @Test
    func other_error_is_transient() {
        let data = Data(#"{"error":"invalid_request"}"#.utf8)
        #expect(ClaudeOAuthCredentialsStore
            .refreshFailureDispositionForTesting(statusCode: 400, data: data) == "transientBackoff")
    }

    @Test
    func undecodable_body_is_transient() {
        let data = Data("not-json".utf8)
        #expect(ClaudeOAuthCredentialsStore
            .refreshFailureDispositionForTesting(statusCode: 401, data: data) == "transientBackoff")
        #expect(ClaudeOAuthCredentialsStore.extractOAuthErrorCodeForTesting(from: data) == nil)
    }

    @Test
    func non_auth_status_is_not_handled() {
        let data = Data(#"{"error":"invalid_grant"}"#.utf8)
        #expect(ClaudeOAuthCredentialsStore.refreshFailureDispositionForTesting(statusCode: 500, data: data) == nil)
    }
}
