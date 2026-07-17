import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CodexUserFacingErrorTests {
    @Test
    func missing_codex_CLI_guidance_is_not_collapsed_to_not_running() {
        let store = self.makeUsageStore(suite: "CodexUserFacingErrorTests-missing-cli")
        store.errors[.codex] = "Codex not running. Try running a Codex command first. "
            + "(Codex CLI not found. Install with `npm i -g @openai/codex`.)"

        #expect(store.userFacingError(for: .codex) == CodexStatusProbeError.codexNotInstalled.localizedDescription)
    }

    @Test
    func logged_out_codex_CLI_guidance_is_not_collapsed_to_temporary_outage() {
        let store = self.makeUsageStore(suite: "CodexUserFacingErrorTests-cli-login-required")
        store.errors[.codex] =
            "Codex connection failed: codex account authentication required to read rate limits"

        #expect(
            store.userFacingError(for: .codex) ==
                "Codex CLI is not signed in. Run `codex login --device-auth`, then refresh.")
    }

    @Test
    func cached_logged_out_codex_CLI_failure_preserves_cached_suffix() {
        let store = self.makeUsageStore(suite: "CodexUserFacingErrorTests-cached-cli-login-required")
        store.lastCreditsError =
            "Last Codex credits refresh failed: Codex connection failed: "
                + "codex account authentication required to read rate limits. Cached values from 2m ago."

        #expect(
            store.userFacingLastCreditsError ==
                "Codex CLI is not signed in. Run `codex login --device-auth`, then refresh. "
                + "Cached values from 2m ago.")
    }

    @Test
    func expired_codex_auth_is_sanitized() {
        let store = self.makeUsageStore(suite: "CodexUserFacingErrorTests-expired-auth")
        store.errors[.codex] = """
        Codex connection failed: failed to fetch codex rate limits: GET https://chatgpt.com/backend-api/wham/usage \
        failed: 401 Unauthorized; content-type=text/plain; body={\"error\":{\"message\":\"Provided authentication \
        token is expired. Please try signing in again.\",\"code\":\"token_expired\"}}
        """

        #expect(store.userFacingError(for: .codex) == "Codex session expired. Sign in again.")
    }

    @Test
    func transport_codex_error_is_sanitized() {
        let store = self.makeUsageStore(suite: "CodexUserFacingErrorTests-transport")
        store.errors[.codex] =
            "Codex connection failed: failed to fetch codex rate limits: "
                + "GET https://chatgpt.com/backend-api/wham/usage failed: 500"

        #expect(store.userFacingError(for: .codex) == "Codex usage is temporarily unavailable. Try refreshing.")
    }

    @Test
    func decode_mismatch_codex_error_is_sanitized() {
        let store = self.makeUsageStore(suite: "CodexUserFacingErrorTests-decode-mismatch")
        store.errors[.codex] =
            "Codex connection failed: failed to fetch codex rate limits: "
                + "Decode error for https://chatgpt.com/backend-api/wham/usage: "
                + "unknown variant `prolite`, expected one of `guest`, `free`, `go`, `plus`, `pro`"

        #expect(store.userFacingError(for: .codex) == "Codex usage is temporarily unavailable. Try refreshing.")
    }

    @Test
    func cached_credits_failure_preserves_cached_suffix_while_sanitizing_body() {
        let store = self.makeUsageStore(suite: "CodexUserFacingErrorTests-cached-credits")
        store.lastCreditsError =
            "Last Codex credits refresh failed: Codex connection failed: failed to fetch codex rate limits: "
                + "GET https://chatgpt.com/backend-api/wham/usage failed: 500; body={\"error\":{}} "
                + "Cached values from 2m ago."

        #expect(
            store.userFacingLastCreditsError ==
                "Codex usage is temporarily unavailable. Try refreshing. Cached values from 2m ago.")
    }

    @Test
    func localized_cached_credits_failure_preserves_cached_suffix_while_sanitizing_body() {
        let result = CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hant") {
            let store = self.makeUsageStore(suite: "CodexUserFacingErrorTests-localized-cached-credits")
            store.lastCreditsError =
                "Last Codex credits refresh failed: Codex connection failed: failed to fetch codex rate limits: "
                    + "GET https://chatgpt.com/backend-api/wham/usage failed: 500 Cached values from 2m ago."

            return store.userFacingLastCreditsError
        }

        #expect(result == "Codex 使用量暫時無法取得。請嘗試重新整理。 使用 2m ago 的快取值。")
    }

    @Test
    func cached_missing_codex_CLI_failure_preserves_cached_suffix() {
        let store = self.makeUsageStore(suite: "CodexUserFacingErrorTests-cached-missing-cli")
        store.lastCreditsError =
            "Last Codex credits refresh failed: Codex CLI not found. "
                + "Install with `npm i -g @openai/codex`. Cached values from 2m ago."

        #expect(
            store.userFacingLastCreditsError ==
                CodexStatusProbeError.codexNotInstalled.localizedDescription + " Cached values from 2m ago.")
    }

    @Test
    func browser_mismatch_remains_unchanged() {
        let store = self.makeUsageStore(suite: "CodexUserFacingErrorTests-browser-mismatch")
        store.lastOpenAIDashboardError =
            "OpenAI cookies are for ratulsarna@gmail.com, not rdsarna@gmail.com. "
                + "Switch chatgpt.com account, then refresh OpenAI cookies."

        #expect(
            store.userFacingLastOpenAIDashboardError ==
                "OpenAI cookies are for ratulsarna@gmail.com, not rdsarna@gmail.com. "
                + "Switch chatgpt.com account, then refresh OpenAI cookies.")
    }

    @Test
    func frame_load_interrupted_becomes_retry_guidance() {
        let store = self.makeUsageStore(suite: "CodexUserFacingErrorTests-frame-load")
        store.lastOpenAIDashboardError = "Frame load interrupted"

        #expect(
            store.userFacingLastOpenAIDashboardError ==
                "OpenAI web refresh was interrupted. Refresh OpenAI cookies and try again.")
    }

    @Test
    func open_A_I_web_timeout_becomes_retry_guidance() {
        let store = self.makeUsageStore(suite: "CodexUserFacingErrorTests-openai-web-timeout")
        store.lastOpenAIDashboardError = "The operation couldn’t be completed. (NSURLErrorDomain error -1001.)"

        #expect(
            store.userFacingLastOpenAIDashboardError ==
                "OpenAI web refresh timed out. Refresh OpenAI cookies and try again.")
    }

    @Test
    func localized_cached_open_A_I_web_timeout_preserves_cached_suffix() {
        let result = CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hant") {
            let store = self.makeUsageStore(suite: "CodexUserFacingErrorTests-localized-openai-web-timeout")
            store.lastOpenAIDashboardError =
                "Last OpenAI dashboard refresh failed: "
                    + "The operation couldn’t be completed. (NSURLErrorDomain error -1001.). "
                    + "Cached values from 2m ago."

            return store.userFacingLastOpenAIDashboardError
        }

        #expect(
            result ==
                "OpenAI Web 重新整理逾時。請重新整理 OpenAI Cookie 後再試一次。 使用 2m ago 的快取值。")
    }

    @Test
    func open_A_I_web_network_error_becomes_connection_guidance() {
        let store = self.makeUsageStore(suite: "CodexUserFacingErrorTests-openai-web-network")
        store.lastOpenAIDashboardError = "The operation couldn’t be completed. (NSURLErrorDomain error -1004.)"
        let expected = [
            "OpenAI web refresh hit a network error.",
            "Check your connection, then refresh OpenAI cookies and try again.",
        ].joined(separator: " ")

        #expect(store.userFacingLastOpenAIDashboardError == expected)
    }

    @Test
    func non_codex_providers_keep_raw_errors() {
        let store = self.makeUsageStore(suite: "CodexUserFacingErrorTests-non-codex")
        store.errors[.claude] = "Claude probe failed with debug detail"

        #expect(store.userFacingError(for: .claude) == "Claude probe failed with debug detail")
    }

    @Test
    func successful_provider_diagnostic_does_not_make_usage_stale() {
        let settings = self.makeSettingsStore(suite: "CodexUserFacingErrorTests-success-diagnostic")
        let store = self.makeUsageStore(settings: settings)
        store.diagnostics[.grok] = GrokStatusProbe.teamUsageUnavailableMessage

        #expect(store.userFacingError(for: .grok) == GrokStatusProbe.teamUsageUnavailableMessage)
        #expect(!store.isStale(provider: .grok))

        let pane = ProvidersPane(settings: settings, store: store)
        let display = pane._test_providerErrorDisplay(for: .grok)
        #expect(display?.preview == GrokStatusProbe.teamUsageUnavailableMessage)
        #expect(display?.full == GrokStatusProbe.teamUsageUnavailableMessage)
    }

    @Test
    func providers_pane_codex_model_uses_sanitized_values() {
        let settings = self.makeSettingsStore(suite: "CodexUserFacingErrorTests-pane-model")
        let store = self.makeUsageStore(settings: settings)
        store.errors[.codex] =
            "Codex connection failed: failed to fetch codex rate limits: "
                + "GET https://chatgpt.com/backend-api/wham/usage failed: 500"
        store.lastCreditsError =
            "Last Codex credits refresh failed: Codex connection failed: failed to fetch codex rate limits: "
                + "GET https://chatgpt.com/backend-api/wham/usage failed: 500 "
                + "Cached values from 1m ago."
        store.lastOpenAIDashboardError = "Frame load interrupted"

        let pane = ProvidersPane(settings: settings, store: store)
        let model = pane._test_menuCardModel(for: .codex)

        #expect(model.subtitleText == "Codex usage is temporarily unavailable. Try refreshing.")
        #expect(
            model.creditsHintText ==
                "OpenAI web refresh was interrupted. Refresh OpenAI cookies and try again.")
        #expect(
            model.creditsHintCopyText ==
                "OpenAI web refresh was interrupted. Refresh OpenAI cookies and try again.")
        #expect(
            model.creditsText == "Codex usage is temporarily unavailable. Try refreshing. Cached values from 1m ago.")
    }

    @Test
    func menu_card_hides_optional_codex_setup_diagnostics_kept_by_providers_pane() throws {
        let settings = self.makeSettingsStore(suite: "CodexUserFacingErrorTests-menu-diagnostics")
        let store = self.makeUsageStore(settings: settings)
        store.lastCreditsError = UsageError.noRateLimitsFound.errorDescription
        store.lastOpenAIDashboardError =
            "No matching OpenAI web session found. Sign in to chatgpt.com, then refresh OpenAI cookies."

        let fetcher = UsageFetcher(environment: [:])
        let menuModel = try withStatusItemControllerForTesting(
            store: store,
            settings: settings,
            fetcher: fetcher)
        { controller in
            try #require(controller.menuCardModel(for: .codex))
        }
        let pane = ProvidersPane(settings: settings, store: store)
        let settingsModel = pane._test_menuCardModel(for: .codex)
        let settingsDiagnostic = pane._test_openAIWebDiagnostic(for: .codex)
        let settingsInfoRows = ProviderMetricsInlineView.infoRows(
            for: settingsModel,
            openAIWebDiagnostic: settingsDiagnostic)

        #expect(menuModel.creditsText == nil)
        #expect(menuModel.creditsHintText == nil)
        #expect(settingsModel.creditsText == UsageError.noRateLimitsFound.errorDescription)
        #expect(settingsModel.creditsHintText?.contains("No matching OpenAI web session found") == true)
        #expect(settingsInfoRows.contains { row in
            row.id == .openAIWeb && row.value.contains("No matching OpenAI web session found")
        })
    }

    @Test
    func providers_pane_codex_error_display_keeps_raw_full_text_for_copy() {
        let settings = self.makeSettingsStore(suite: "CodexUserFacingErrorTests-pane-error-display")
        let store = self.makeUsageStore(settings: settings)
        let raw =
            "Codex connection failed: failed to fetch codex rate limits: "
                + "GET https://chatgpt.com/backend-api/wham/usage failed: 500; body={\"error\":{}}"
        store.errors[.codex] = raw

        let pane = ProvidersPane(settings: settings, store: store)
        let display = pane._test_providerErrorDisplay(for: .codex)

        #expect(display?.preview == "Codex usage is temporarily unavailable. Try refreshing.")
        #expect(display?.full == raw)
    }

    private func makeUsageStore(suite: String) -> UsageStore {
        let settings = self.makeSettingsStore(suite: suite)
        return self.makeUsageStore(settings: settings)
    }

    private func makeUsageStore(settings: SettingsStore) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
    }

    private func makeSettingsStore(suite: String) -> SettingsStore {
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
