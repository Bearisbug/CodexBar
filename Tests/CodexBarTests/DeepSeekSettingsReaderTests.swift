import Foundation
import Testing
@testable import CodexBarCore

struct DeepSeekSettingsReaderTests {
    @Test
    func reads_DEEPSEEK_API_KEY() {
        let env = ["DEEPSEEK_API_KEY": "sk-abc123"]
        #expect(DeepSeekSettingsReader.apiKey(environment: env) == "sk-abc123")
    }

    @Test
    func falls_back_to_DEEPSEEK_KEY() {
        let env = ["DEEPSEEK_KEY": "sk-fallback"]
        #expect(DeepSeekSettingsReader.apiKey(environment: env) == "sk-fallback")
    }

    @Test
    func DEEPSEEK_API_KEY_takes_priority_over_DEEPSEEK_KEY() {
        let env = ["DEEPSEEK_API_KEY": "sk-primary", "DEEPSEEK_KEY": "sk-secondary"]
        #expect(DeepSeekSettingsReader.apiKey(environment: env) == "sk-primary")
    }

    @Test
    func trims_whitespace() {
        let env = ["DEEPSEEK_API_KEY": "  sk-trimmed  "]
        #expect(DeepSeekSettingsReader.apiKey(environment: env) == "sk-trimmed")
    }

    @Test
    func strips_double_quotes() {
        let env = ["DEEPSEEK_API_KEY": "\"sk-quoted\""]
        #expect(DeepSeekSettingsReader.apiKey(environment: env) == "sk-quoted")
    }

    @Test
    func strips_single_quotes() {
        let env = ["DEEPSEEK_KEY": "'sk-single'"]
        #expect(DeepSeekSettingsReader.apiKey(environment: env) == "sk-single")
    }

    @Test
    func returns_nil_when_no_key_present() {
        #expect(DeepSeekSettingsReader.apiKey(environment: [:]) == nil)
    }

    @Test
    func returns_nil_for_empty_key() {
        let env = ["DEEPSEEK_API_KEY": ""]
        #expect(DeepSeekSettingsReader.apiKey(environment: env) == nil)
    }

    @Test
    func returns_nil_for_whitespace_only_key() {
        let env = ["DEEPSEEK_API_KEY": "   "]
        #expect(DeepSeekSettingsReader.apiKey(environment: env) == nil)
    }

    @Test
    func reads_separate_platform_session_token() {
        let env = ["DEEPSEEK_PLATFORM_TOKEN": "  browser-session-token  "]
        #expect(DeepSeekSettingsReader.platformToken(environment: env) == "browser-session-token")
    }

    @Test
    func falls_back_to_DeepSeek_user_token_environment_key() {
        let env = ["DEEPSEEK_USER_TOKEN": "browser-user-token"]
        #expect(DeepSeekSettingsReader.platformToken(environment: env) == "browser-user-token")
    }

    @Test
    func platform_session_token_requires_the_active_credential_scope() throws {
        let accountID = UUID()
        let credential = "api-key-value"
        let scope = try #require(DeepSeekSettingsReader.profileScope(
            selectedTokenAccountID: accountID,
            apiKey: credential))
        let environment = [
            DeepSeekSettingsReader.platformTokenEnvironmentKey: "platform-session",
            DeepSeekSettingsReader.profileScopeEnvironmentKey: scope,
        ]

        #expect(DeepSeekSettingsReader.scopedPlatformToken(
            environment: environment,
            selectedTokenAccountID: accountID,
            apiKey: credential) == "platform-session")
        #expect(DeepSeekSettingsReader.scopedPlatformToken(
            environment: environment,
            selectedTokenAccountID: UUID(),
            apiKey: credential) == nil)
        #expect(DeepSeekSettingsReader.scopedPlatformToken(
            environment: [DeepSeekSettingsReader.platformTokenEnvironmentKey: "platform-session"],
            selectedTokenAccountID: accountID,
            apiKey: credential) == nil)
        #expect(DeepSeekSettingsReader.scopedPlatformToken(
            environment: [DeepSeekSettingsReader.platformTokenEnvironmentKey: "platform-session"],
            selectedTokenAccountID: nil,
            apiKey: nil) == "platform-session")
    }

    @Test
    func reads_selected_Chrome_profile_id() {
        let env = [DeepSeekSettingsReader.profileIDEnvironmentKey: "  /profiles/Profile 2  "]
        #expect(DeepSeekSettingsReader.profileID(environment: env) == "chrome:Profile 2")
    }

    @Test
    func migrates_an_absolute_Chrome_profile_path_to_a_stable_identifier() {
        let environment = [
            DeepSeekSettingsReader.profileIDEnvironmentKey:
                "/Users/example/Library/Application Support/Google/Chrome/Profile 2",
        ]

        #expect(DeepSeekSettingsReader.profileID(environment: environment) == "chrome:Profile 2")
    }

    @Test
    func profile_scope_fingerprints_the_api_credential_without_storing_it() throws {
        let accountID = UUID()
        let first = try #require(DeepSeekSettingsReader.profileScope(
            selectedTokenAccountID: accountID,
            apiKey: "secret-api-key"))
        let repeated = try #require(DeepSeekSettingsReader.profileScope(
            selectedTokenAccountID: accountID,
            apiKey: "secret-api-key"))
        let replacedKey = try #require(DeepSeekSettingsReader.profileScope(
            selectedTokenAccountID: accountID,
            apiKey: "replacement-api-key"))
        let otherAccount = try #require(DeepSeekSettingsReader.profileScope(
            selectedTokenAccountID: UUID(),
            apiKey: "secret-api-key"))

        #expect(first == repeated)
        #expect(first != replacedKey)
        #expect(first != otherAccount)
        #expect(!first.contains("secret-api-key"))
    }

    @Test
    func browser_only_profile_scope_persists_without_an_API_key() throws {
        let scope = try #require(DeepSeekSettingsReader.profileScope(
            selectedTokenAccountID: nil,
            apiKey: nil))

        #expect(!scope.isEmpty)
    }
}

struct DeepSeekProviderTokenResolverTests {
    @Test
    func resolves_from_environment() {
        let env = ["DEEPSEEK_API_KEY": "sk-resolve-test"]
        let resolution = ProviderTokenResolver.deepseekResolution(environment: env)
        #expect(resolution?.token == "sk-resolve-test")
        #expect(resolution?.source == .environment)
    }

    @Test
    func returns_nil_when_key_absent() {
        let resolution = ProviderTokenResolver.deepseekResolution(environment: [:])
        #expect(resolution == nil)
    }
}
