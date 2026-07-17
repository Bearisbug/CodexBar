import CodexBarCore
import Testing
@testable import CodexBar

struct KeychainPromptCoordinatorTests {
    @Test
    func detects_raw_SwiftPM_debug_executable() {
        #expect(KeychainPromptCoordinator.isUnbundledCodexBarExecutable(
            "/Users/me/CodexBar/.build/arm64-apple-macosx/debug/CodexBar"))
        #expect(KeychainPromptCoordinator.isUnbundledCodexBarExecutable(
            "/Users/me/CodexBar/.build/debug/CodexBar"))
    }

    @Test
    func detects_raw_SwiftPM_release_executable() {
        #expect(KeychainPromptCoordinator.isUnbundledCodexBarExecutable(
            "/Users/me/CodexBar/.build/arm64-apple-macosx/release/CodexBar"))
    }

    @Test
    func detects_custom_SwiftPM_scratch_path() {
        #expect(KeychainPromptCoordinator.isUnbundledCodexBarExecutable(
            "/tmp/codexbar-build/arm64-apple-macosx/debug/CodexBar"))
    }

    @Test
    func keeps_packaged_app_keychain_behavior() {
        #expect(!KeychainPromptCoordinator.isUnbundledCodexBarExecutable(
            "/Applications/CodexBar.app/Contents/MacOS/CodexBar"))
        #expect(!KeychainPromptCoordinator.isUnbundledCodexBarExecutable(
            "/Users/me/CodexBar/.build/package/CodexBar.app/Contents/MacOS/CodexBar"))
    }

    @Test
    func ignores_unrelated_executable_paths() {
        #expect(!KeychainPromptCoordinator.isUnbundledCodexBarExecutable(
            "/Users/me/CodexBar/.build/debug/CodexBarCLI"))
        #expect(!KeychainPromptCoordinator.isUnbundledCodexBarExecutable(""))
        #expect(!KeychainPromptCoordinator.isUnbundledCodexBarExecutable("CodexBar"))
    }

    @Test
    func browser_cookie_alert_explains_password_handling_and_opt_out() {
        let model = KeychainPromptCoordinator.browserCookieAlertModel(label: "Chrome Safe Storage")

        #expect(model.title == "Keychain Access Required")
        #expect(model.message.contains("Chrome Safe Storage"))
        #expect(model.message.contains("macOS—not CodexBar—handles any Mac login password entry"))
        #expect(model.message.contains("Settings → Advanced"))
        #expect(model.primaryButtonTitle == "OK")
        #expect(model.learnMoreButtonTitle == "Learn More…")
        #expect(model.documentationURL.hasSuffix("/docs/keychain-prompts.md"))
    }

    @Test
    func provider_alert_preserves_the_requested_keychain_purpose() {
        let context = KeychainPromptContext(
            kind: .claudeOAuth,
            service: "Claude Code-credentials",
            account: nil)

        let model = KeychainPromptCoordinator.alertModel(for: context)

        #expect(model.message.contains("Claude Code OAuth token"))
        #expect(model.message.contains("fetch your Claude usage"))
        #expect(model.learnMoreButtonTitle == "Learn More…")
    }
}
