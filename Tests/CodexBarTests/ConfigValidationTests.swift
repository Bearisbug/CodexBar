import CodexBarCore
import Foundation
import Testing

struct ConfigValidationTests {
    @Test
    func fresh_config_defaults_Alibaba_Token_Plan_to_International() throws {
        let config = CodexBarConfig.makeDefault()
        let provider = try #require(config.providerConfig(for: .alibabatokenplan))
        let issues = CodexBarConfigValidator.validate(config)

        #expect(provider.region == AlibabaTokenPlanAPIRegion.international.rawValue)
        #expect(!issues.contains(where: { $0.provider == .alibabatokenplan }))
    }

    @Test
    func normalization_preserves_legacy_Alibaba_Token_Plan_region() throws {
        let config = CodexBarConfig(providers: [
            ProviderConfig(id: .alibabatokenplan, region: nil),
        ]).normalized()
        let provider = try #require(config.providerConfig(for: .alibabatokenplan))

        #expect(provider.region == nil)
    }

    @Test
    func normalization_adds_missing_Alibaba_Token_Plan_as_China_mainland() throws {
        let config = CodexBarConfig(providers: [
            ProviderConfig(id: .codex),
        ]).normalized()
        let provider = try #require(config.providerConfig(for: .alibabatokenplan))

        #expect(provider.region == AlibabaTokenPlanAPIRegion.chinaMainland.rawValue)
    }

    @Test
    func reports_invalid_Alibaba_Token_Plan_region() {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .alibabatokenplan, region: "nowhere"))
        let issues = CodexBarConfigValidator.validate(config)

        #expect(issues.contains(where: {
            $0.provider == .alibabatokenplan && $0.code == "invalid_region"
        }))
    }

    @Test
    func reports_unsupported_source() {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .codex, source: .api))
        let issues = CodexBarConfigValidator.validate(config)
        #expect(issues.contains(where: { $0.code == "unsupported_source" }))
    }

    @Test
    func accepts_legacy_factory_cli_source_as_compatibility_alias() {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .factory, source: .cli))
        let issues = CodexBarConfigValidator.validate(config)
        #expect(!issues.contains(where: {
            $0.provider == .factory && $0.code == "unsupported_source"
        }))
        #expect(FactoryProviderDescriptor.descriptor.fetchPlan.sourceModes.contains(.cli))
    }

    @Test
    func reports_missing_API_key_when_source_API() {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .zai, source: .api, apiKey: nil))
        let issues = CodexBarConfigValidator.validate(config)
        #expect(issues.contains(where: { $0.code == "api_key_missing" }))
    }

    @Test
    func allows_credentialless_Wayfinder_API_source() {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(
            id: .wayfinder,
            source: .api,
            enterpriseHost: "http://127.0.0.1:9191"))
        let issues = CodexBarConfigValidator.validate(config)

        #expect(!issues.contains(where: { $0.provider == .wayfinder && $0.code == "api_key_missing" }))
    }

    @Test
    func sub2api_token_accounts_satisfy_API_credentials() {
        let accounts = ProviderTokenAccountData(
            version: 1,
            accounts: [
                ProviderTokenAccount(
                    id: UUID(),
                    label: "Primary",
                    token: "fixture",
                    addedAt: 0,
                    lastUsed: nil),
            ],
            activeIndex: 0)
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(
            id: .sub2api,
            source: .api,
            enterpriseHost: "https://sub2api.example.com",
            tokenAccounts: accounts))
        let issues = CodexBarConfigValidator.validate(config)

        #expect(!issues.contains(where: { $0.provider == .sub2api && $0.code == "api_key_missing" }))
    }

    @Test
    func sub2api_accepts_HTTPS_and_loopback_HTTP_base_URLs() {
        for host in ["https://sub2api.example.com", "http://127.0.0.1:8080"] {
            var config = CodexBarConfig.makeDefault()
            config.setProviderConfig(ProviderConfig(
                id: .sub2api,
                source: .api,
                apiKey: "fixture",
                enterpriseHost: host))
            let invalidHostIssue = CodexBarConfigValidator.validate(config).first { issue in
                issue.provider == .sub2api && issue.code == "invalid_enterprise_host"
            }

            #expect(invalidHostIssue == nil)
        }
    }

    @Test
    func sub2api_rejects_unsafe_base_URLs() {
        let invalidHosts = [
            "http://sub2api.example.com",
            "https://user:pass@sub2api.example.com",
            "https://sub2api.example.com?token=secret",
            "https://sub2api.example.com#fragment",
        ]
        for host in invalidHosts {
            var config = CodexBarConfig.makeDefault()
            config.setProviderConfig(ProviderConfig(
                id: .sub2api,
                source: .api,
                apiKey: "fixture",
                enterpriseHost: host))
            let invalidHostIssue = CodexBarConfigValidator.validate(config).first { issue in
                issue.provider == .sub2api &&
                    issue.field == "enterpriseHost" &&
                    issue.code == "invalid_enterprise_host"
            }

            #expect(invalidHostIssue != nil)
        }
    }

    @Test
    func sub2api_rejects_blank_token_accounts_as_API_credentials() {
        let accounts = ProviderTokenAccountData(
            version: 1,
            accounts: [
                ProviderTokenAccount(
                    id: UUID(),
                    label: "Blank",
                    token: "   ",
                    addedAt: 0,
                    lastUsed: nil),
            ],
            activeIndex: 0)
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(
            id: .sub2api,
            source: .api,
            enterpriseHost: "https://sub2api.example.com",
            tokenAccounts: accounts))
        let issues = CodexBarConfigValidator.validate(config)

        #expect(issues.contains(where: { $0.provider == .sub2api && $0.code == "api_key_missing" }))
    }

    @Test
    func reports_invalid_region() {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .minimax, region: "nowhere"))
        let issues = CodexBarConfigValidator.validate(config)
        #expect(issues.contains(where: { $0.code == "invalid_region" }))
    }

    @Test
    func warns_on_unsupported_token_accounts() {
        let accounts = ProviderTokenAccountData(
            version: 1,
            accounts: [ProviderTokenAccount(id: UUID(), label: "a", token: "t", addedAt: 0, lastUsed: nil)],
            activeIndex: 0)
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .gemini, tokenAccounts: accounts))
        let issues = CodexBarConfigValidator.validate(config)
        #expect(issues.contains(where: { $0.code == "token_accounts_unused" }))
    }

    @Test
    func allows_ollama_token_accounts() {
        let accounts = ProviderTokenAccountData(
            version: 1,
            accounts: [ProviderTokenAccount(id: UUID(), label: "a", token: "t", addedAt: 0, lastUsed: nil)],
            activeIndex: 0)
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .ollama, tokenAccounts: accounts))
        let issues = CodexBarConfigValidator.validate(config)
        #expect(!issues.contains(where: { $0.code == "token_accounts_unused" && $0.provider == .ollama }))
    }

    @Test
    func accepts_kilo_extras_config_field() {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .kilo, extrasEnabled: true))
        let issues = CodexBarConfigValidator.validate(config)
        #expect(!issues.contains(where: { $0.provider == .kilo && $0.field == "extrasEnabled" }))
    }

    @Test
    func allows_deepgram_project_workspace_ID() {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .deepgram, workspaceID: "project-123"))
        let issues = CodexBarConfigValidator.validate(config)
        #expect(!issues.contains(where: { $0.provider == .deepgram && $0.code == "workspace_unused" }))
    }

    @Test
    func allows_Azure_OpenAI_endpoint_and_deployment_fields() {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(
            id: .azureopenai,
            workspaceID: "chat-prod",
            enterpriseHost: "https://example-resource.openai.azure.com"))
        let issues = CodexBarConfigValidator.validate(config)

        #expect(!issues.contains(where: { $0.provider == .azureopenai && $0.code == "workspace_unused" }))
        #expect(!issues.contains(where: { $0.provider == .azureopenai && $0.code == "enterprise_host_unused" }))
    }

    @Test
    func allows_LiteLLM_endpoint() {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(
            id: .litellm,
            apiKey: "sk-test",
            enterpriseHost: "https://litellm.example.com"))
        let issues = CodexBarConfigValidator.validate(config)

        #expect(!issues.contains(where: { $0.provider == .litellm && $0.code == "enterprise_host_unused" }))
    }

    @Test
    func unsupported_enterprise_host_warning_lists_every_supported_provider() throws {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .gemini, enterpriseHost: "https://example.com"))
        let issue = try #require(CodexBarConfigValidator.validate(config).first(where: {
            $0.provider == .gemini && $0.code == "enterprise_host_unused"
        }))

        #expect(issue.message ==
            "enterpriseHost is set but only azureopenai, clawrouter, copilot, kimi, litellm, llmproxy, sub2api, and " +
            "wayfinder " +
            "support enterpriseHost.")
    }

    @Test
    func allows_OpenAI_API_project_workspace_ID() {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .openai, workspaceID: "proj_abc"))
        let issues = CodexBarConfigValidator.validate(config)

        #expect(!issues.contains(where: { $0.provider == .openai && $0.code == "workspace_unused" }))
    }

    @Test
    func allows_doubao_coding_plan_credential_fields() {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(
            id: .doubao,
            apiKey: "AKLT-config",
            secretKey: "sk-config",
            region: "cn-shanghai"))
        let issues = CodexBarConfigValidator.validate(config)

        #expect(!issues.contains(where: { $0.provider == .doubao && $0.code == "secret_key_unused" }))
        #expect(!issues.contains(where: { $0.provider == .doubao && $0.code == "region_unused" }))
    }

    @Test
    func warns_when_zai_team_token_account_is_missing_BigModel_context() {
        let accounts = ProviderTokenAccountData(
            version: 1,
            accounts: [
                ProviderTokenAccount(
                    id: UUID(),
                    label: "Team",
                    token: "token",
                    addedAt: 0,
                    lastUsed: nil,
                    usageScope: "team",
                    organizationID: "org_abc"),
            ],
            activeIndex: 0)
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .zai, tokenAccounts: accounts))
        let issues = CodexBarConfigValidator.validate(config)

        #expect(issues.contains(where: { $0.provider == .zai && $0.code == "zai_team_context_missing" }))
    }

    @Test
    func warns_on_unsupported_workspace_ID() {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .gemini, workspaceID: "workspace-123"))
        let issues = CodexBarConfigValidator.validate(config)
        #expect(issues.contains(where: { $0.provider == .gemini && $0.code == "workspace_unused" }))
        #expect(issues.contains(where: { issue in
            issue.provider == .gemini &&
                issue.code == "workspace_unused" &&
                issue.message.contains("openai")
        }))
    }

    @Test
    func config_store_default_url_honors_environment_override() {
        let url = CodexBarConfigStore.defaultURL(environment: [
            CodexBarConfigStore.pathEnvironmentKey: "~/tmp/codexbar-test-config.json",
        ])

        #expect(url.path.hasSuffix("/tmp/codexbar-test-config.json"))
    }

    @Test
    func config_store_default_url_honors_xdg_config_home() throws {
        let fileManager = FileManager.default
        let home = try Self.makeTemporaryHome()
        defer { try? fileManager.removeItem(at: home) }
        let xdgHome = home.appendingPathComponent("custom-config", isDirectory: true)

        let url = CodexBarConfigStore.defaultURL(
            home: home,
            environment: [
                CodexBarConfigStore.xdgConfigHomeEnvironmentKey: xdgHome.path,
            ],
            fileManager: fileManager)

        #expect(url == Self.configURL(in: xdgHome))
    }

    @Test
    func config_store_default_url_ignores_relative_xdg_config_home() throws {
        let fileManager = FileManager.default
        let home = try Self.makeTemporaryHome()
        defer { try? fileManager.removeItem(at: home) }
        let legacy = Self.legacyConfigURL(in: home)
        try Self.touch(legacy, fileManager: fileManager)

        let url = CodexBarConfigStore.defaultURL(
            home: home,
            environment: [
                CodexBarConfigStore.xdgConfigHomeEnvironmentKey: "relative-config",
            ],
            fileManager: fileManager)

        #expect(url == legacy)
    }

    @Test
    func config_store_default_url_creates_in_xdg_default_for_new_installs() throws {
        let fileManager = FileManager.default
        let home = try Self.makeTemporaryHome()
        defer { try? fileManager.removeItem(at: home) }

        let url = CodexBarConfigStore.defaultURL(home: home, environment: [:], fileManager: fileManager)

        #expect(url == Self.configURL(in: home.appendingPathComponent(".config", isDirectory: true)))
    }

    @Test
    func config_store_default_url_keeps_existing_legacy_config() throws {
        let fileManager = FileManager.default
        let home = try Self.makeTemporaryHome()
        defer { try? fileManager.removeItem(at: home) }
        let legacy = Self.legacyConfigURL(in: home)
        try Self.touch(legacy, fileManager: fileManager)

        let url = CodexBarConfigStore.defaultURL(home: home, environment: [:], fileManager: fileManager)

        #expect(url == legacy)
    }

    @Test
    func config_store_default_url_prefers_existing_xdg_default_over_legacy_config() throws {
        let fileManager = FileManager.default
        let home = try Self.makeTemporaryHome()
        defer { try? fileManager.removeItem(at: home) }
        let xdgDefault = Self.configURL(in: home.appendingPathComponent(".config", isDirectory: true))
        let legacy = Self.legacyConfigURL(in: home)
        try Self.touch(legacy, fileManager: fileManager)
        try Self.touch(xdgDefault, fileManager: fileManager)

        let url = CodexBarConfigStore.defaultURL(home: home, environment: [:], fileManager: fileManager)

        #expect(url == xdgDefault)
    }

    private static func makeTemporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBarConfigStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func touch(_ url: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }

    private static func configURL(in directory: URL) -> URL {
        directory
            .appendingPathComponent("codexbar", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    private static func legacyConfigURL(in home: URL) -> URL {
        home
            .appendingPathComponent(".codexbar", isDirectory: true)
            .appendingPathComponent("config.json")
    }
}
