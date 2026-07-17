import CodexBarCore
import Foundation
import Testing

struct ProviderEnvironmentResolverTests {
    @Test
    func selected_API_account_overrides_saved_and_ambient_credentials() {
        let account = Self.account(token: "account-token")
        let environment = ProviderEnvironmentResolver.resolve(
            base: [ZaiSettingsReader.apiTokenKey: "ambient-token"],
            provider: .zai,
            config: ProviderConfig(id: .zai, apiKey: "saved-token"),
            selectedAccount: account)

        #expect(environment[ZaiSettingsReader.apiTokenKey] == "account-token")
    }

    @Test
    func OpenAI_account_removes_project_scoping_from_saved_config() {
        let account = Self.account(token: "sk-admin-account")
        let environment = ProviderEnvironmentResolver.resolve(
            base: [
                OpenAIAPISettingsReader.adminAPIKeyEnvironmentKey: "ambient-token",
                OpenAIAPISettingsReader.projectIDEnvironmentKey: "ambient-project",
            ],
            provider: .openai,
            config: ProviderConfig(
                id: .openai,
                apiKey: "saved-token",
                workspaceID: "saved-project"),
            selectedAccount: account)

        #expect(environment[OpenAIAPISettingsReader.adminAPIKeyEnvironmentKey] == "sk-admin-account")
        #expect(environment[OpenAIAPISettingsReader.projectIDEnvironmentKey] == nil)
    }

    @Test
    func Claude_session_account_removes_API_and_OAuth_credentials() {
        let environment = ProviderEnvironmentResolver.resolve(
            base: [
                ClaudeAdminAPISettingsReader.alternateAdminAPIKeyEnvironmentKey: "ambient-admin",
                ClaudeOAuthCredentialsStore.environmentTokenKey: "ambient-oauth",
            ],
            provider: .claude,
            config: ProviderConfig(id: .claude, apiKey: "saved-admin"),
            selectedAccount: Self.account(token: "sk-ant-session-account"))

        for key in ClaudeAdminAPISettingsReader.apiKeyEnvironmentKeys {
            #expect(environment[key] == nil)
        }
        #expect(environment[ClaudeOAuthCredentialsStore.environmentTokenKey] == nil)
    }

    @Test
    func Claude_OAuth_account_replaces_incompatible_credentials() {
        let environment = ProviderEnvironmentResolver.resolve(
            base: [
                ClaudeAdminAPISettingsReader.alternateAdminAPIKeyEnvironmentKey: "ambient-admin",
                ClaudeOAuthCredentialsStore.environmentTokenKey: "ambient-oauth",
            ],
            provider: .claude,
            config: ProviderConfig(id: .claude, apiKey: "saved-admin"),
            selectedAccount: Self.account(token: "Bearer sk-ant-oat-account"))

        for key in ClaudeAdminAPISettingsReader.apiKeyEnvironmentKeys {
            #expect(environment[key] == nil)
        }
        #expect(environment[ClaudeOAuthCredentialsStore.environmentTokenKey] == "sk-ant-oat-account")
    }

    @Test
    func cookie_account_leaves_unrelated_provider_environment_intact() {
        let base = ["FOO": "bar"]
        let environment = ProviderEnvironmentResolver.resolve(
            base: base,
            provider: .cursor,
            config: ProviderConfig(id: .cursor),
            selectedAccount: Self.account(token: "session=account"))

        #expect(environment == base)
    }

    private static func account(token: String) -> ProviderTokenAccount {
        ProviderTokenAccount(
            id: UUID(),
            label: "Test",
            token: token,
            addedAt: 0,
            lastUsed: nil)
    }
}
