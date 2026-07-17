import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct CLIDiagnoseCommandTests {
    @Test
    func diagnose_help_describes_generic_JSON_export() {
        let help = CodexBarCLI.diagnoseHelp(version: "0.0.0")

        #expect(help.contains("codexbar diagnose --provider <name|all> --format json"))
        #expect(help.contains("codexbar diagnose --provider all --format json"))
        #expect(help.contains("--redact"))
        #expect(help.contains("--output <path>"))
        #expect(help.contains("safe JSON export"))
        #expect(help.contains("raw API tokens"))
    }

    @Test
    func diagnose_output_writer_creates_parent_directories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBarDiagnoseTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let output = root.appendingPathComponent("nested/diagnostic.json")
        try CodexBarCLI.writeDiagnosticExport(#"{"provider":"minimax"}"#, to: output.path)

        let contents = try String(contentsOf: output, encoding: .utf8)
        #expect(contents == #"{"provider":"minimax"}"#)
    }

    private func makeSettingsWithMiniMaxCookie(_ manualCookieHeader: String) -> ProviderSettingsSnapshot {
        ProviderSettingsSnapshot(
            debugMenuEnabled: false,
            debugKeepCLISessionsAlive: false,
            codex: nil,
            claude: nil,
            cursor: nil,
            opencode: nil,
            opencodego: nil,
            alibaba: nil,
            factory: nil,
            minimax: ProviderSettingsSnapshot.MiniMaxProviderSettings(
                cookieSource: .manual,
                manualCookieHeader: manualCookieHeader,
                apiRegion: .global),
            manus: nil,
            zai: nil,
            copilot: nil,
            kilo: nil,
            kimi: nil,
            augment: nil,
            amp: nil,
            ollama: nil)
    }

    @Test
    func diagnose_auth_mode_uses_settings_backed_MiniMax_manual_cookie_when_env_token_is_absent() {
        let settings = self.makeSettingsWithMiniMaxCookie("Cookie: session_id=demo-cookie")

        let authMode = CodexBarCLI._resolveMiniMaxAuthModeForTesting(
            environment: [:],
            settings: settings)

        #expect(authMode == .cookie)
    }

    @Test
    func diagnose_auth_mode_keeps_apiToken_precedence_over_settings_cookie() {
        let settings = self.makeSettingsWithMiniMaxCookie("Cookie: session_id=demo-cookie")

        let authMode = CodexBarCLI._resolveMiniMaxAuthModeForTesting(
            environment: [MiniMaxAPISettingsReader.apiTokenKey: "sk-api-demo-token"],
            settings: settings)

        #expect(authMode == .apiToken)
    }

    @Test
    func generic_diagnose_auth_summary_detects_provider_config() {
        let summary = CodexBarCLI._diagnosticAuthSummaryForTesting(
            provider: .openai,
            account: nil,
            config: ProviderConfig(id: .openai, apiKey: "sk-test"),
            environment: [:],
            settings: nil)

        #expect(summary.configured)
        #expect(summary.modes == ["api"])
    }

    @Test
    func generic_diagnose_auth_summary_detects_provider_environment_credentials() {
        let summary = CodexBarCLI._diagnosticAuthSummaryForTesting(
            provider: .openai,
            account: nil,
            config: nil,
            environment: [OpenAIAPISettingsReader.apiKeyEnvironmentKey: "sk-test"],
            settings: nil)

        #expect(summary.configured)
        #expect(summary.modes == ["api"])
    }

    @Test
    func generic_diagnose_auth_summary_detects_Chutes_environment_credentials() {
        let summary = CodexBarCLI._diagnosticAuthSummaryForTesting(
            provider: .chutes,
            account: nil,
            config: nil,
            environment: [ChutesSettingsReader.apiKeyEnvironmentKey: "chutes-test"],
            settings: nil)

        #expect(summary.configured)
        #expect(summary.modes == ["api"])
    }

    @Test
    func generic_diagnose_auth_summary_detects_CrossModel_environment_credentials() {
        let summary = CodexBarCLI._diagnosticAuthSummaryForTesting(
            provider: .crossmodel,
            account: nil,
            config: nil,
            environment: [CrossModelSettingsReader.envKey: "cm-test"],
            settings: nil)

        #expect(summary.configured)
        #expect(summary.modes == ["api"])
    }

    @Test
    func generic_diagnose_auth_summary_requires_complete_Bedrock_credentials() {
        let partial = CodexBarCLI._diagnosticAuthSummaryForTesting(
            provider: .bedrock,
            account: nil,
            config: ProviderConfig(id: .bedrock, apiKey: "access-only"),
            environment: [BedrockSettingsReader.accessKeyIDKey: "access-only"],
            settings: nil)
        #expect(!partial.configured)
        #expect(partial.modes.isEmpty)

        let complete = CodexBarCLI._diagnosticAuthSummaryForTesting(
            provider: .bedrock,
            account: nil,
            config: nil,
            environment: [
                BedrockSettingsReader.accessKeyIDKey: "access",
                BedrockSettingsReader.secretAccessKeyKey: "secret",
            ],
            settings: nil)
        #expect(complete.configured)
        #expect(complete.modes == ["api"])
    }

    @Test
    func generic_diagnose_auth_summary_does_not_assume_ambient_credentials() {
        let summary = CodexBarCLI._diagnosticAuthSummaryForTesting(
            provider: .codex,
            account: nil,
            config: nil,
            environment: [:],
            settings: nil)

        #expect(!summary.configured)
        #expect(summary.modes.isEmpty)
    }
}
