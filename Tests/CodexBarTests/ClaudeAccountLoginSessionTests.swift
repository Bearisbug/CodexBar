import Foundation
import Testing
@testable import CodexBarCore

/// Covers the transcript parsing of the interactive sign-in session (REQ-009, ADR-006).
/// The PTY handshake itself needs a real `claude auth login`, so it stays manual (TC-017).
struct ClaudeAccountLoginSessionTests {
    /// Real 2.1.226 output shape: an OSC 8 hyperlink whose target and visible label are
    /// both the URL, wrapped in colour codes.
    private static let realTranscript = """
    Opening browser to sign in…
    If the browser didn't open, visit: \u{1b}]8;;https://claude.com/cai/oauth/authorize?code=true\
    &client_id=9d1c250a&response_type=code&redirect_uri=https%3A%2F%2Fplatform.claude.com%2Foauth\
    %2Fcode%2Fcallback&scope=user%3Aprofile&code_challenge=L1dB_AM18H4K&code_challenge_method=S256\
    &state=5UcANA4hn\u{07}\u{1b}[94mhttps://claude.com/cai/oauth/authorize?code=true\u{1b}[39m\u{1b}]8;;\u{07}
    Paste code here if prompted >
    """

    @Test
    func extracts_the_authorization_link_from_hyperlinked_output() throws {
        let url = try #require(ClaudeAccountLoginSession.authorizationURL(in: Self.realTranscript))
        #expect(url.absoluteString.hasPrefix("https://claude.com/cai/oauth/authorize?code=true"))
        #expect(url.absoluteString.contains("code_challenge=L1dB_AM18H4K"))
        // The OSC 8 terminator must not leak into the link.
        #expect(!url.absoluteString.contains("\u{07}"))
        #expect(!url.absoluteString.contains("\u{1b}"))
    }

    @Test
    func waits_while_the_link_is_still_streaming() {
        let partial = "Opening browser to sign in…\nIf the browser didn't open, visit: https://claude.com/cai/oa"
        #expect(ClaudeAccountLoginSession.authorizationURL(in: partial) == nil)
    }

    @Test
    func reports_no_link_before_the_cli_prints_one() {
        #expect(ClaudeAccountLoginSession.authorizationURL(in: "") == nil)
        #expect(ClaudeAccountLoginSession.authorizationURL(in: "Loading…\n") == nil)
    }

    @Test
    func surfaces_the_cli_failure_line() {
        let transcript = "Opening browser to sign in…\nPaste code here if prompted > \nLogin failed: invalid code\n"
        #expect(ClaudeAccountLoginSession.failureDetail(in: transcript) == "Login failed: invalid code")
    }

    @Test
    func falls_back_to_the_last_line_when_nothing_says_failed() {
        let transcript = "Opening browser to sign in…\n\nSomething odd happened\n"
        #expect(ClaudeAccountLoginSession.failureDetail(in: transcript) == "Something odd happened")
    }

    @Test
    func interactive_login_is_unavailable_without_an_injected_runner() async throws {
        // The default service must not fall back to a headless subprocess: that is the
        // path that died with "Login failed: Socket is closed".
        let service = ClaudeAccountService(
            store: EmptyAccountStore(),
            backups: EmptyBackupStore(),
            systemCredentials: UnavailableSystemCredentials())
        await #expect(throws: ClaudeAccountServiceError.self) {
            _ = try await service.loginNewAccount()
        }
    }
}

// MARK: - Minimal doubles (the shared harness is private to ClaudeNativeAccountsTests)

private struct EmptyAccountStore: ClaudeManagedAccountStoring {
    func load() throws -> ClaudeManagedAccountSet {
        ClaudeManagedAccountSet(version: FileClaudeManagedAccountStore.currentVersion, accounts: [])
    }

    func store(_: ClaudeManagedAccountSet) throws {}
}

private struct EmptyBackupStore: ClaudeCredentialBackupStoring {
    func load(accountID _: UUID) -> ClaudeCredentialBackup? {
        nil
    }

    @discardableResult
    func store(_: ClaudeCredentialBackup, accountID _: UUID) -> Bool {
        true
    }

    func clear(accountID _: UUID) {}
}

private struct UnavailableSystemCredentials: ClaudeSystemCredentialAccessing {
    func readCurrent() async throws -> ClaudeSystemCredentials {
        throw ClaudeSystemCredentialError.keychainReadFailed(detail: "test double")
    }

    func readIdentityEmail() throws -> String? {
        nil
    }

    func write(credentialsBlob _: String, oauthAccountJSON _: Data) async throws {}
}
