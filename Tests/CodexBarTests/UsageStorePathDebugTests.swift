import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct UsageStorePathDebugTests {
    @Test
    func refresh_path_debug_info_populates_snapshot() async throws {
        let suite = "UsageStorePathDebugTests-path"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore())
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .full)

        let deadline = Date().addingTimeInterval(2)
        while store.pathDebugInfo == .empty, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(store.pathDebugInfo != .empty)
        #expect(store.pathDebugInfo.effectivePATH.isEmpty == false)
    }

    @Test
    func deepseek_debug_log_includes_selected_token_account() async throws {
        let suite = "UsageStorePathDebugTests-deepseek-debug-token-account"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore())
        settings.addTokenAccount(provider: .deepseek, label: "Primary", token: "sk-deepseek-test")
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])

        let debugLog = await store.debugLog(for: UsageProvider.deepseek)

        #expect(debugLog == "DEEPSEEK_API_KEY=present source=settings-token-account")
    }

    @Test
    func crossmodel_debug_log_includes_config_backed_api_key() async throws {
        let suite = "UsageStorePathDebugTests-crossmodel-debug-config-key"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore())
        settings.crossModelAPIToken = "cm-config-test"
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])

        let debugLog = await store.debugLog(for: UsageProvider.crossmodel)

        #expect(debugLog == "CROSSMODEL_API_KEY=present source=settings-config")
    }
}
