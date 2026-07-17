import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ClaudeKeychainLiveProofTests {
    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["LIVE_CLAUDE_KEYCHAIN_PROOF"] == "1"
    }

    @Test
    func live_background_Auto_skips_the_opaque_Claude_Keychain_boundary() async {
        guard Self.isEnabled else { return }
        let mode = ClaudeOAuthKeychainPromptPreference.storedMode()
        guard mode == .onlyOnUserAction || mode == .never else {
            Issue.record("Live proof requires a restrictive stored Claude Keychain prompt mode; found \(mode.rawValue)")
            return
        }

        let outcome = await ClaudeOAuthDelegatedRefreshCoordinator.withIsolatedStateForTesting {
            await ProviderInteractionContext.$current.withValue(.background) {
                await ClaudeOAuthDelegatedRefreshCoordinator.attempt(timeout: 8)
            }
        }

        #expect(outcome == .skippedByPromptPolicy)
    }

    @Test
    func live_explicit_user_auth_probe_reports_Claude_login() async throws {
        guard Self.isEnabled else { return }
        let binary = try #require(TTYCommandRunner.which("claude"))

        let isLoggedIn = await ProviderInteractionContext.$current.withValue(.userInitiated) {
            await ClaudeCLIAuthStatusProbe.isLoggedIn(
                binary: binary,
                environment: ProcessInfo.processInfo.environment,
                timeout: 8)
        }

        #expect(isLoggedIn)
    }
}
