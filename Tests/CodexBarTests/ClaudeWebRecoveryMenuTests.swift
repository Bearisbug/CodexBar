import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct ClaudeWebRecoveryMenuTests {
    @Test
    func unauthorized_error_explains_how_to_restore_web_usage() {
        #expect(
            ClaudeWebAPIFetcher.FetchError.unauthorized.localizedDescription ==
                "Sign in to claude.ai (or refresh Claude cookies) to load usage data.")
    }

    private func makeSettings() -> SettingsStore {
        let suite = "ClaudeWebRecoveryMenuTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    private func actions(
        error: String? = nil,
        source: ClaudeUsageDataSource,
        cookieSource: ProviderCookieSource = .auto,
        selectedSessionKey: Bool = false,
        attempts: [ProviderFetchAttempt] = []) -> [(String, MenuDescriptor.MenuAction)]
    {
        let settings = self.makeSettings()
        settings.claudeUsageDataSource = source
        if selectedSessionKey {
            settings.addTokenAccount(provider: .claude, label: "Session", token: "sk-ant-session-token")
        }
        settings.claudeCookieSource = cookieSource
        let fetcher = UsageFetcher()
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store.errors[.claude] = error
        store.lastFetchAttempts[.claude] = attempts

        return MenuDescriptor.build(
            provider: .claude,
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updateReady: false)
            .sections
            .flatMap(\.entries)
            .compactMap { entry in
                guard case let .action(label, action) = entry else { return nil }
                return (label, action)
            }
    }

    @Test
    func default_account_action_localizes_ambient_Claude_Code_sign_in() {
        let actions = CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hant") {
            self.actions(source: .auto)
        }

        #expect(actions.contains {
            $0.0 == "使用 Claude Code 登入…" && $0.1 == .switchAccount(.claude)
        })
        #expect(!actions.contains { $0.0 == "Add Account..." })
    }

    @Test
    func web_session_errors_show_claude_relogin_action() {
        let errors = [
            ClaudeWebAPIFetcher.FetchError.unauthorized.localizedDescription,
            ClaudeWebAPIFetcher.FetchError.noSessionKeyFound.localizedDescription,
            ClaudeWebAPIFetcher.FetchError.invalidSessionKey.localizedDescription,
        ]

        for error in errors {
            let actions = self.actions(error: error, source: .web)
            #expect(actions.contains {
                $0.0 == "Re-login at claude.ai" &&
                    $0.1 == .loginToProvider(url: "https://claude.ai/")
            })
        }
    }

    @Test
    func auto_source_shows_relogin_action_for_terminal_web_session_error() {
        let actions = self.actions(
            error: ClaudeWebAPIFetcher.FetchError.unauthorized.localizedDescription,
            source: .auto)

        #expect(actions.contains {
            $0.0 == "Re-login at claude.ai" &&
                $0.1 == .loginToProvider(url: "https://claude.ai/")
        })
    }

    @Test
    func non_web_source_does_not_replace_account_action() {
        let actions = self.actions(
            error: ClaudeWebAPIFetcher.FetchError.unauthorized.localizedDescription,
            source: .oauth)

        #expect(!actions.contains { $0.0 == "Re-login at claude.ai" })
    }

    @Test
    func manual_cookies_do_not_show_browser_relogin_action() {
        let actions = self.actions(
            error: ClaudeWebAPIFetcher.FetchError.unauthorized.localizedDescription,
            source: .web,
            cookieSource: .manual)

        #expect(!actions.contains { $0.0 == "Re-login at claude.ai" })
    }

    @Test
    func selected_session_account_does_not_show_browser_relogin_action() {
        let actions = self.actions(
            error: ClaudeWebAPIFetcher.FetchError.unauthorized.localizedDescription,
            source: .web,
            cookieSource: .auto,
            selectedSessionKey: true)

        #expect(!actions.contains { $0.0 == "Re-login at claude.ai" })
    }

    @Test
    func unavailable_web_strategy_shows_relogin_action() {
        let actions = self.actions(
            error: ProviderFetchError.noAvailableStrategy(.claude).localizedDescription,
            source: .web,
            attempts: [
                ProviderFetchAttempt(
                    strategyID: "claude.web",
                    kind: .web,
                    wasAvailable: false,
                    errorDescription: nil),
            ])

        #expect(actions.contains {
            $0.0 == "Re-login at claude.ai" &&
                $0.1 == .loginToProvider(url: "https://claude.ai/")
        })
    }

    @Test
    func generic_unavailable_error_without_web_attempt_keeps_account_action() {
        let actions = self.actions(
            error: ProviderFetchError.noAvailableStrategy(.claude).localizedDescription,
            source: .auto,
            attempts: [
                ProviderFetchAttempt(
                    strategyID: "claude.cli",
                    kind: .cli,
                    wasAvailable: false,
                    errorDescription: nil),
            ])

        #expect(!actions.contains { $0.0 == "Re-login at claude.ai" })
    }

    @Test
    func unrelated_web_error_does_not_replace_account_action() {
        let actions = self.actions(
            error: ClaudeWebAPIFetcher.FetchError.serverError(statusCode: 500).localizedDescription,
            source: .web)

        #expect(!actions.contains { $0.0 == "Re-login at claude.ai" })
    }
}
