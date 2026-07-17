import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct ZaiTokenAccountEnvironmentTests {
    @Test
    func zai_selected_team_account_injects_team_scope_environment() {
        let settings = Self.makeSettingsStore(suite: "ZaiTokenAccountEnvironmentTests-team-app")
        settings.addTokenAccount(
            provider: .zai,
            label: "Team",
            token: "account-token",
            usageScope: "team",
            organizationID: " org-account ",
            workspaceID: " proj-account ")

        let env = ProviderRegistry.makeEnvironment(
            base: [
                ZaiSettingsReader.bigModelOrganizationKey: "org-env",
                ZaiSettingsReader.bigModelProjectKey: "proj-env",
            ],
            provider: .zai,
            settings: settings,
            tokenOverride: nil)

        #expect(env[ZaiSettingsReader.apiTokenKey] == "account-token")
        #expect(env[ZaiSettingsReader.bigModelOrganizationKey] == "org-account")
        #expect(env[ZaiSettingsReader.bigModelProjectKey] == "proj-account")
    }

    @Test
    func zai_selected_personal_account_clears_inherited_team_environment() {
        let settings = Self.makeSettingsStore(suite: "ZaiTokenAccountEnvironmentTests-personal-app")
        settings.addTokenAccount(
            provider: .zai,
            label: "Personal",
            token: "account-token",
            usageScope: "personal")

        let env = ProviderRegistry.makeEnvironment(
            base: [
                ZaiSettingsReader.bigModelOrganizationKey: "org-env",
                ZaiSettingsReader.bigModelProjectKey: "proj-env",
            ],
            provider: .zai,
            settings: settings,
            tokenOverride: nil)

        #expect(env[ZaiSettingsReader.apiTokenKey] == "account-token")
        #expect(env[ZaiSettingsReader.bigModelOrganizationKey] == nil)
        #expect(env[ZaiSettingsReader.bigModelProjectKey] == nil)
    }

    @Test
    func zai_account_switched_back_to_personal_clears_stored_team_context() throws {
        let settings = Self.makeSettingsStore(suite: "ZaiTokenAccountEnvironmentTests-team-to-personal")
        settings.addTokenAccount(
            provider: .zai,
            label: "Team",
            token: "account-token",
            usageScope: "team",
            organizationID: "org-account",
            workspaceID: "proj-account")
        let account = try #require(settings.selectedTokenAccount(for: .zai))

        settings.updateTokenAccount(
            provider: .zai,
            accountID: account.id,
            usageScope: .some("personal"),
            organizationID: .some(nil),
            workspaceID: .some(nil))

        let updated = try #require(settings.selectedTokenAccount(for: .zai))
        #expect(updated.usageScope == "personal")
        #expect(updated.organizationID == nil)
        #expect(updated.workspaceID == nil)
    }

    @Test
    func zai_selected_team_account_overrides_app_settings_snapshot() {
        let settings = Self.makeSettingsStore(suite: "ZaiTokenAccountEnvironmentTests-team-snapshot")
        settings.addTokenAccount(
            provider: .zai,
            label: "Team",
            token: "account-token",
            usageScope: "team",
            organizationID: " org-account ",
            workspaceID: " proj-account ")

        let snapshot = ProviderRegistry.makeSettingsSnapshot(settings: settings, tokenOverride: nil).zai

        #expect(snapshot?.usageScope == .team)
        #expect(snapshot?.teamContext?.organizationID == "org-account")
        #expect(snapshot?.teamContext?.projectID == "proj-account")
    }

    @Test
    func zai_explicit_team_account_does_not_inherit_provider_team_context() {
        let settings = Self.makeSettingsStore(suite: "ZaiTokenAccountEnvironmentTests-empty-team-snapshot")
        settings.addTokenAccount(
            provider: .zai,
            label: "Team",
            token: "account-token",
            usageScope: "team")

        let snapshot = ProviderRegistry.makeSettingsSnapshot(settings: settings, tokenOverride: nil).zai

        #expect(snapshot?.usageScope == .team)
        #expect(snapshot?.teamContext == nil)
    }

    @Test
    func zai_token_account_usage_scope_and_project_id_round_trip_through_JSON() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "label": "Team",
          "token": "account-token",
          "addedAt": 0,
          "lastUsed": null,
          "usageScope": "team",
          "organizationId": "org-team",
          "workspaceID": "proj-team"
        }
        """
        let account = try JSONDecoder().decode(ProviderTokenAccount.self, from: Data(json.utf8))
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(account)) as? [String: Any]

        #expect(account.sanitizedUsageScope == "team")
        #expect(account.sanitizedOrganizationID == "org-team")
        #expect(account.sanitizedWorkspaceID == "proj-team")
        #expect(encoded?["usageScope"] as? String == "team")
        #expect(encoded?["organizationId"] as? String == "org-team")
        #expect(encoded?["workspaceID"] as? String == "proj-team")
    }
}

extension ZaiTokenAccountEnvironmentTests {
    fileprivate static func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        return SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            cursorCookieStore: InMemoryCookieHeaderStore(),
            opencodeCookieStore: InMemoryCookieHeaderStore(),
            factoryCookieStore: InMemoryCookieHeaderStore(),
            minimaxCookieStore: InMemoryMiniMaxCookieStore(),
            minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(),
            kimiTokenStore: InMemoryKimiTokenStore(),
            kimiK2TokenStore: InMemoryKimiK2TokenStore(),
            augmentCookieStore: InMemoryCookieHeaderStore(),
            ampCookieStore: InMemoryCookieHeaderStore(),
            copilotTokenStore: InMemoryCopilotTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore())
    }
}
