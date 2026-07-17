import CodexBarCore
import Foundation
import Testing

@Suite(.serialized)
struct CodexActiveSourceConfigTests {
    @Test
    func legacy_config_without_codex_active_source_decodes_to_nil() throws {
        let legacyJSON = """
        {
            "version": 1,
            "providers": [
                {
                    "id": "codex"
                }
            ]
        }
        """

        let decoded = try JSONDecoder().decode(
            CodexBarConfig.self,
            from: Data(legacyJSON.utf8))

        #expect(decoded.providerConfig(for: .codex)?.codexActiveSource == nil)
        #expect(decoded.providerConfig(for: .codex)?.quotaWarnings == nil)
    }

    @Test
    func provider_config_round_trips_quota_warning_overrides() throws {
        let config = CodexBarConfig(
            providers: [
                ProviderConfig(
                    id: .codex,
                    quotaWarnings: QuotaWarningConfig(
                        session: QuotaWarningWindowConfig(thresholds: [10]),
                        weekly: QuotaWarningWindowConfig(thresholds: [50, 20]))),
            ])

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CodexBarConfig.self, from: data)
        let quotaWarnings = try #require(decoded.providerConfig(for: .codex)?.quotaWarnings)

        #expect(quotaWarnings.thresholds(for: .session, global: [80]) == [10])
        #expect(quotaWarnings.thresholds(for: .weekly, global: [80]) == [50, 20])
    }

    @Test
    func quota_warning_window_enabled_defaults_stay_backward_compatible() throws {
        let legacyJSON = """
        {
            "version": 1,
            "providers": [
                {
                    "id": "codex",
                    "quotaWarnings": {
                        "session": { "thresholds": [10] },
                        "weekly": { "enabled": false }
                    }
                }
            ]
        }
        """

        let decoded = try JSONDecoder().decode(CodexBarConfig.self, from: Data(legacyJSON.utf8))
        let quotaWarnings = try #require(decoded.providerConfig(for: .codex)?.quotaWarnings)

        #expect(quotaWarnings.isEnabled(for: .session, global: false) == true)
        #expect(quotaWarnings.isEnabled(for: .weekly, global: true) == false)
        #expect(quotaWarnings.hasOverride(for: .session) == true)
        #expect(quotaWarnings.hasOverride(for: .weekly) == true)
    }

    @Test
    func provider_config_encodes_live_system_active_source_with_expected_schema() throws {
        let config = CodexBarConfig(
            providers: [
                ProviderConfig(
                    id: .codex,
                    codexActiveSource: .liveSystem),
            ])

        let data = try JSONEncoder().encode(config)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let providers = try #require(object?["providers"] as? [[String: Any]])
        let provider = try #require(providers.first(where: { $0["id"] as? String == "codex" }))
        let activeSource = try #require(provider["codexActiveSource"] as? [String: Any])

        #expect(activeSource.count == 1)
        #expect(activeSource["kind"] as? String == "liveSystem")
        #expect(activeSource["accountID"] == nil)
    }

    @Test
    func provider_config_encodes_managed_account_active_source_with_expected_schema() throws {
        let accountID = UUID()
        let config = CodexBarConfig(
            providers: [
                ProviderConfig(
                    id: .codex,
                    codexActiveSource: .managedAccount(id: accountID)),
            ])

        let data = try JSONEncoder().encode(config)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let providers = try #require(object?["providers"] as? [[String: Any]])
        let provider = try #require(providers.first(where: { $0["id"] as? String == "codex" }))
        let activeSource = try #require(provider["codexActiveSource"] as? [String: Any])

        #expect(activeSource.count == 2)
        #expect(activeSource["kind"] as? String == "managedAccount")
        #expect((activeSource["accountID"] as? String) == accountID.uuidString)
    }

    @Test
    func provider_config_encodes_profile_home_source_in_downgrade_readable_envelope() throws {
        let config = CodexBarConfig(
            providers: [
                ProviderConfig(
                    id: .codex,
                    codexActiveSource: .profileHome(path: "/Users/test/.codex-work"),
                    codexProfileHomePaths: ["/Users/test/.codex-work"]),
            ])

        let data = try JSONEncoder().encode(config)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let providers = try #require(object?["providers"] as? [[String: Any]])
        let provider = try #require(providers.first(where: { $0["id"] as? String == "codex" }))
        let activeSource = try #require(provider["codexActiveSource"] as? [String: Any])

        #expect(activeSource.count == 2)
        #expect(activeSource["kind"] as? String == "liveSystem")
        #expect(activeSource["homePath"] as? String == "/Users/test/.codex-work")
        #expect(provider["codexProfileHomePaths"] as? [String] == ["/Users/test/.codex-work"])

        let releasedConfig = try JSONDecoder().decode(ReleasedCodexBarConfig.self, from: data)
        #expect(releasedConfig.providers.first?.codexActiveSource == .liveSystem)
    }

    @Test
    func provider_config_round_trips_live_system_active_source() throws {
        let config = CodexBarConfig(
            providers: [
                ProviderConfig(
                    id: .codex,
                    codexActiveSource: .liveSystem),
            ])

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CodexBarConfig.self, from: data)

        #expect(decoded.providerConfig(for: .codex)?.codexActiveSource == .liveSystem)
    }

    @Test
    func provider_config_round_trips_managed_account_active_source() throws {
        let accountID = UUID()
        let config = CodexBarConfig(
            providers: [
                ProviderConfig(
                    id: .codex,
                    codexActiveSource: .managedAccount(id: accountID)),
            ])

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CodexBarConfig.self, from: data)

        #expect(decoded.providerConfig(for: .codex)?.codexActiveSource == .managedAccount(id: accountID))
    }

    @Test
    func provider_config_round_trips_profile_home_active_source() throws {
        let config = CodexBarConfig(
            providers: [
                ProviderConfig(
                    id: .codex,
                    codexActiveSource: .profileHome(path: "/Users/test/.codex-work"),
                    codexProfileHomePaths: ["/Users/test/.codex-work"]),
            ])

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CodexBarConfig.self, from: data)
        let providerConfig = decoded.providerConfig(for: .codex)

        #expect(providerConfig?.codexActiveSource == .profileHome(path: "/Users/test/.codex-work"))
        #expect(providerConfig?.codexProfileHomePaths == ["/Users/test/.codex-work"])
    }

    @Test
    func profile_home_discriminator_written_by_development_builds_still_decodes() throws {
        let data = Data(#"{"kind":"profileHome","homePath":"/Users/test/.codex-work"}"#.utf8)

        let decoded = try JSONDecoder().decode(CodexActiveSource.self, from: data)
        let canonicalData = try JSONEncoder().encode(decoded)
        let canonical = try #require(JSONSerialization.jsonObject(with: canonicalData) as? [String: Any])

        #expect(decoded == .profileHome(path: "/Users/test/.codex-work"))
        #expect(canonical["kind"] as? String == "liveSystem")
        #expect(canonical["homePath"] as? String == "/Users/test/.codex-work")
    }

    @Test
    func blank_profile_home_sentinel_falls_back_to_live_system() throws {
        let data = Data(#"{"kind":"liveSystem","homePath":"  "}"#.utf8)

        let decoded = try JSONDecoder().decode(CodexActiveSource.self, from: data)

        #expect(decoded == .liveSystem)
    }
}

private struct ReleasedCodexBarConfig: Decodable {
    let providers: [ReleasedProviderConfig]
}

private struct ReleasedProviderConfig: Decodable {
    let codexActiveSource: ReleasedCodexActiveSource?
}

private enum ReleasedCodexActiveSource: Decodable, Equatable {
    case liveSystem
    case managedAccount(id: UUID)

    private enum CodingKeys: String, CodingKey {
        case kind
        case accountID
    }

    private enum Kind: String, Decodable {
        case liveSystem
        case managedAccount
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .liveSystem:
            self = .liveSystem
        case .managedAccount:
            self = try .managedAccount(id: container.decode(UUID.self, forKey: .accountID))
        }
    }
}
