import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct CodexPresentationCharacterizationTests {
    @Test
    func weekly_only_Codex_menu_rendering_omits_session_row() {
        let settings = self.makeSettingsStore(suite: "CodexPresentationCharacterizationTests-weekly-only")
        settings.statusChecksEnabled = false

        let fetcher = UsageFetcher()
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: RateWindow(
                    usedPercent: 20,
                    windowMinutes: 10080,
                    resetsAt: nil,
                    resetDescription: "Apr 6, 2026"),
                updatedAt: Date(),
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: "codex@example.com",
                    accountOrganization: nil,
                    loginMethod: "free")),
            provider: .codex)

        let descriptor = MenuDescriptor.build(
            provider: .codex,
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updateReady: false,
            includeContextualActions: false)

        let lines = self.textLines(from: descriptor)
        #expect(!lines.contains(where: { $0.hasPrefix("Session:") }))
        #expect(lines.contains(where: { $0.hasPrefix("Weekly:") }))
    }

    @Test
    func Codex_menu_does_not_surface_identity_from_another_provider_snapshot() {
        let settings = self.makeSettingsStore(suite: "CodexPresentationCharacterizationTests-provider-silo")
        settings.statusChecksEnabled = false

        let fetcher = UsageFetcher(environment: [:])
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 12, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date(),
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: "codex@example.com",
                    accountOrganization: nil,
                    loginMethod: "free")),
            provider: .codex)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 40, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date(),
                identity: ProviderIdentitySnapshot(
                    providerID: .claude,
                    accountEmail: "claude@example.com",
                    accountOrganization: nil,
                    loginMethod: "max")),
            provider: .claude)

        let descriptor = MenuDescriptor.build(
            provider: .codex,
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updateReady: false,
            includeContextualActions: false)

        let lines = self.textLines(from: descriptor)
        #expect(lines.contains("Account: codex@example.com"))
        #expect(lines.contains("Plan: Free"))
        #expect(!lines.contains("Account: claude@example.com"))
        #expect(!lines.contains("Plan: Max"))
    }

    @Test
    func Codex_menu_omits_account_row_when_hiding_personal_info() {
        let settings = self.makeSettingsStore(suite: "CodexPresentationCharacterizationTests-hide-account")
        settings.statusChecksEnabled = false
        settings.hidePersonalInfo = true

        let fetcher = UsageFetcher(environment: [:])
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 12, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date(),
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: "codex@example.com",
                    accountOrganization: nil,
                    loginMethod: "free")),
            provider: .codex)

        let descriptor = MenuDescriptor.build(
            provider: .codex,
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updateReady: false,
            includeContextualActions: false)

        let lines = self.textLines(from: descriptor)
        #expect(!lines.contains(where: { $0.hasPrefix("Account:") }))
        #expect(!lines.contains(where: { $0.contains("codex@example.com") }))
        #expect(!lines.contains(where: { $0.contains("Hidden") }))
        #expect(lines.contains("Plan: Free"))
    }

    @Test
    func Codex_menu_maps_prolite_plan_to_multiplier_display_name() {
        let settings = self.makeSettingsStore(suite: "CodexPresentationCharacterizationTests-prolite")
        settings.statusChecksEnabled = false

        let fetcher = UsageFetcher(environment: [:])
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 12, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date(),
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: "codex@example.com",
                    accountOrganization: nil,
                    loginMethod: "prolite")),
            provider: .codex)

        let descriptor = MenuDescriptor.build(
            provider: .codex,
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updateReady: false,
            includeContextualActions: false)

        let lines = self.textLines(from: descriptor)
        #expect(lines.contains("Plan: Pro 5x"))
        #expect(!lines.contains("Plan: Pro Lite"))
        #expect(!lines.contains("Plan: Prolite"))
    }

    @Test
    func Codex_menu_prefers_snapshot_identity_over_conflicting_fallback_account_info() throws {
        let settings = self.makeSettingsStore(suite: "CodexPresentationCharacterizationTests-snapshot-precedence")
        settings.statusChecksEnabled = false
        let managedHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-presentation-fallback-\(UUID().uuidString)", isDirectory: true)
        let managedAccount = ManagedCodexAccount(
            id: UUID(),
            email: "fallback@example.com",
            managedHomePath: managedHome.path,
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        try Self.writeCodexAuthFile(homeURL: managedHome, email: "fallback@example.com", plan: "plus")
        settings._test_activeManagedCodexAccount = managedAccount
        settings._test_activeManagedCodexRemoteHomePath = managedHome.path
        settings.codexActiveSource = .managedAccount(id: managedAccount.id)
        defer {
            settings._test_activeManagedCodexAccount = nil
            settings._test_activeManagedCodexRemoteHomePath = nil
            try? FileManager.default.removeItem(at: managedHome)
        }

        let fetcher = UsageFetcher(environment: [:])
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 12, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date(),
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: "snapshot@example.com",
                    accountOrganization: nil,
                    loginMethod: "enterprise")),
            provider: .codex)

        let fallback = store.accountInfo(for: .codex)
        #expect(fallback.email == "fallback@example.com")
        #expect(fallback.plan == "plus")

        let descriptor = MenuDescriptor.build(
            provider: .codex,
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updateReady: false,
            includeContextualActions: false)

        let lines = self.textLines(from: descriptor)
        #expect(lines.contains("Account: snapshot@example.com"))
        #expect(lines.contains("Plan: Enterprise"))
        #expect(!lines.contains("Account: fallback@example.com"))
        #expect(!lines.contains("Plan: Plus"))
    }

    @Test
    func Codex_menu_falls_back_per_field_when_snapshot_identity_is_partial() {
        let settings = self.makeSettingsStore(suite: "CodexPresentationCharacterizationTests-partial-fallback")
        settings.statusChecksEnabled = false
        let managedHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-presentation-partial-\(UUID().uuidString)", isDirectory: true)
        let managedAccount = ManagedCodexAccount(
            id: UUID(),
            email: "fallback@example.com",
            managedHomePath: managedHome.path,
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        try? Self.writeCodexAuthFile(homeURL: managedHome, email: "fallback@example.com", plan: "plus")
        settings._test_activeManagedCodexAccount = managedAccount
        settings._test_activeManagedCodexRemoteHomePath = managedHome.path
        settings.codexActiveSource = .managedAccount(id: managedAccount.id)
        defer {
            settings._test_activeManagedCodexAccount = nil
            settings._test_activeManagedCodexRemoteHomePath = nil
            try? FileManager.default.removeItem(at: managedHome)
        }

        let fetcher = UsageFetcher(environment: [:])
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 12, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date(),
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: "snapshot@example.com",
                    accountOrganization: nil,
                    loginMethod: nil)),
            provider: .codex)

        let descriptor = MenuDescriptor.build(
            provider: .codex,
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updateReady: false,
            includeContextualActions: false)

        let lines = self.textLines(from: descriptor)
        #expect(lines.contains("Account: snapshot@example.com"))
        #expect(lines.contains("Plan: Plus"))
        #expect(!lines.contains("Account: fallback@example.com"))
    }

    @Test
    func managed_OpenAI_web_targeting_uses_active_managed_Codex_identity_and_scope() {
        let settings = self.makeSettingsStore(suite: "CodexPresentationCharacterizationTests-managed-openai-web")
        let managedAccount = ManagedCodexAccount(
            id: UUID(),
            email: "managed@example.com",
            managedHomePath: "/tmp/managed-codex-home",
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        settings._test_activeManagedCodexAccount = managedAccount
        settings.codexActiveSource = .managedAccount(id: managedAccount.id)
        defer { settings._test_activeManagedCodexAccount = nil }

        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)

        #expect(store.codexAccountEmailForOpenAIDashboard() == managedAccount.email)
        #expect(store.codexCookieCacheScopeForOpenAIWeb() == .managedAccount(managedAccount.id))
    }

    @Test
    func live_OpenAI_web_targeting_uses_live_Codex_identity_without_managed_scope() {
        let settings = self.makeSettingsStore(suite: "CodexPresentationCharacterizationTests-live-openai-web")
        let managedAccount = ManagedCodexAccount(
            id: UUID(),
            email: "managed@example.com",
            managedHomePath: "/tmp/managed-codex-home",
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        let liveAccount = ObservedSystemCodexAccount(
            email: "system@example.com",
            codexHomePath: "/tmp/live-codex-home",
            observedAt: Date())
        settings._test_activeManagedCodexAccount = managedAccount
        settings._test_liveSystemCodexAccount = liveAccount
        settings.codexActiveSource = .liveSystem
        defer {
            settings._test_activeManagedCodexAccount = nil
            settings._test_liveSystemCodexAccount = nil
        }

        let store = UsageStore(
            fetcher: UsageFetcher(environment: ["CODEX_HOME": liveAccount.codexHomePath]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)

        #expect(store.codexAccountEmailForOpenAIDashboard() == liveAccount.email)
        #expect(store.codexAccountEmailForOpenAIDashboard() != managedAccount.email)
        #expect(store.codexCookieCacheScopeForOpenAIWeb() == nil)
    }

    @Test
    func same_email_managed_and_live_Codex_resolves_to_live_for_OpenAI_web_targeting() {
        let settings = self.makeSettingsStore(suite: "CodexPresentationCharacterizationTests-same-email-prefers-live")
        let managedAccount = ManagedCodexAccount(
            id: UUID(),
            email: "person@example.com",
            managedHomePath: "/tmp/managed-codex-home",
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        let liveAccount = ObservedSystemCodexAccount(
            email: "PERSON@example.com",
            codexHomePath: "/tmp/live-codex-home",
            observedAt: Date())
        settings._test_activeManagedCodexAccount = managedAccount
        settings._test_liveSystemCodexAccount = liveAccount
        settings.codexActiveSource = .managedAccount(id: managedAccount.id)
        defer {
            settings._test_activeManagedCodexAccount = nil
            settings._test_liveSystemCodexAccount = nil
        }

        let store = UsageStore(
            fetcher: UsageFetcher(environment: ["CODEX_HOME": liveAccount.codexHomePath]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)

        #expect(settings.codexResolvedActiveSource == .liveSystem)
        #expect(store.codexAccountEmailForOpenAIDashboard() == "person@example.com")
        #expect(store.codexAccountEmailForOpenAIDashboard() != liveAccount.email)
        #expect(store.codexCookieCacheScopeForOpenAIWeb() == nil)
    }

    @Test
    func live_OpenAI_web_targeting_does_not_reuse_stale_managed_Codex_snapshot_identity() {
        let settings = self.makeSettingsStore(suite: "CodexPresentationCharacterizationTests-stale-managed-snapshot")
        let isolatedHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-presentation-openai-web-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: isolatedHome, withIntermediateDirectories: true)
        let managedAccount = ManagedCodexAccount(
            id: UUID(),
            email: "managed@example.com",
            managedHomePath: "/tmp/managed-codex-home",
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)

        settings._test_activeManagedCodexAccount = managedAccount
        settings._test_codexReconciliationEnvironment = ["CODEX_HOME": isolatedHome.path]
        settings.codexActiveSource = .liveSystem
        defer {
            settings._test_activeManagedCodexAccount = nil
            settings._test_codexReconciliationEnvironment = nil
            try? FileManager.default.removeItem(at: isolatedHome)
        }

        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: Date(),
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: managedAccount.email,
                    accountOrganization: nil,
                    loginMethod: nil)),
            provider: .codex)

        #expect(store.codexAccountEmailForOpenAIDashboard() == nil)
        #expect(store.codexAccountEmailForOpenAIDashboard() != managedAccount.email)
        #expect(store.codexCookieCacheScopeForOpenAIWeb() == nil)
    }

    @Test
    func zai_menu_descriptor_includes_Tokens_MCP_and_5_hour_rows() {
        let settings = self.makeSettingsStore(suite: "CodexPresentationCharacterizationTests-zai-three-quota")
        settings.statusChecksEnabled = false

        let fetcher = UsageFetcher(environment: [:])
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 9,
                    windowMinutes: 10080,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: 50,
                    windowMinutes: nil,
                    resetsAt: nil,
                    resetDescription: nil),
                tertiary: RateWindow(
                    usedPercent: 25,
                    windowMinutes: 300,
                    resetsAt: nil,
                    resetDescription: nil),
                updatedAt: Date(),
                identity: ProviderIdentitySnapshot(
                    providerID: .zai,
                    accountEmail: nil,
                    accountOrganization: nil,
                    loginMethod: "pro")),
            provider: .zai)

        let descriptor = MenuDescriptor.build(
            provider: .zai,
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updateReady: false,
            includeContextualActions: false)

        let lines = self.textLines(from: descriptor)
        #expect(lines.contains(where: { $0.hasPrefix("Tokens:") }))
        #expect(lines.contains(where: { $0.hasPrefix("MCP:") }))
        #expect(lines.contains(where: { $0.hasPrefix("5-hour:") }))
    }

    private func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings._test_activeManagedCodexAccount = nil
        settings._test_activeManagedCodexRemoteHomePath = nil
        settings._test_unreadableManagedCodexAccountStore = false
        settings._test_managedCodexAccountStoreURL = nil
        settings._test_liveSystemCodexAccount = nil
        settings._test_codexReconciliationEnvironment = nil
        return settings
    }

    private func textLines(from descriptor: MenuDescriptor) -> [String] {
        descriptor.sections
            .flatMap(\.entries)
            .compactMap { entry -> String? in
                guard case let .text(text, _) = entry else { return nil }
                return text
            }
    }

    private static func writeCodexAuthFile(homeURL: URL, email: String, plan: String) throws {
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        let auth = [
            "tokens": [
                "accessToken": "access-token",
                "refreshToken": "refresh-token",
                "idToken": Self.fakeJWT(email: email, plan: plan),
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: auth)
        try data.write(to: homeURL.appendingPathComponent("auth.json"))
    }

    private static func fakeJWT(email: String, plan: String) -> String {
        let header = (try? JSONSerialization.data(withJSONObject: ["alg": "none"])) ?? Data()
        let payload = (try? JSONSerialization.data(withJSONObject: [
            "email": email,
            "chatgpt_plan_type": plan,
        ])) ?? Data()

        func base64URL(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
        }

        return "\(base64URL(header)).\(base64URL(payload))."
    }
}
