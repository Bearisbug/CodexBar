import Testing
@testable import CodexBar
@testable import CodexBarCore

struct ProviderDetectionPolicyTests {
    @Test
    func fresh_install_detects_Codex_and_Claude_Desktop_without_unconfigured_Gemini() {
        let enabled = ProviderDetectionPolicy.enabledProviders(signals: .init(
            codexCLIInstalled: true,
            claudeCLIInstalled: false,
            claudeDesktopInstalled: true,
            geminiCLIInstalled: true,
            geminiConfigured: false,
            antigravityAvailable: false))

        #expect(enabled == [.codex, .claude])
    }

    @Test
    func configured_Gemini_CLI_is_detected() {
        let enabled = ProviderDetectionPolicy.enabledProviders(signals: .init(
            codexCLIInstalled: false,
            claudeCLIInstalled: false,
            claudeDesktopInstalled: false,
            geminiCLIInstalled: true,
            geminiConfigured: true,
            antigravityAvailable: false))

        #expect(enabled == [.gemini])
    }

    @Test
    func Codex_remains_the_fallback_when_no_provider_source_is_available() {
        let enabled = ProviderDetectionPolicy.enabledProviders(signals: .init(
            codexCLIInstalled: false,
            claudeCLIInstalled: false,
            claudeDesktopInstalled: false,
            geminiCLIInstalled: false,
            geminiConfigured: false,
            antigravityAvailable: false))

        #expect(enabled == [.codex])
    }
}
