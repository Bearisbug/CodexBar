import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

struct CLIWebFallbackTests {
    private func makeContext(
        runtime: ProviderRuntime = .cli,
        sourceMode: ProviderSourceMode = .auto,
        settings: ProviderSettingsSnapshot? = nil) -> ProviderFetchContext
    {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        return ProviderFetchContext(
            runtime: runtime,
            sourceMode: sourceMode,
            includeCredits: true,
            webTimeout: 60,
            webDebugDumpHTML: false,
            verbose: false,
            env: [:],
            settings: settings,
            fetcher: UsageFetcher(),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection)
    }

    private func makeClaudeSettingsSnapshot(cookieHeader: String?) -> ProviderSettingsSnapshot {
        ProviderSettingsSnapshot.make(
            claude: .init(
                usageDataSource: .auto,
                webExtrasEnabled: false,
                cookieSource: .manual,
                manualCookieHeader: cookieHeader))
    }

    @Test
    func codex_falls_back_when_cookies_missing() {
        let context = self.makeContext()
        let strategy = CodexWebDashboardStrategy()
        #expect(strategy.shouldFallback(
            on: OpenAIDashboardBrowserCookieImporter.ImportError.noCookiesFound,
            context: context))
        #expect(strategy.shouldFallback(
            on: OpenAIDashboardBrowserCookieImporter.ImportError.noMatchingAccount(found: []),
            context: context))
        #expect(strategy.shouldFallback(
            on: OpenAIDashboardBrowserCookieImporter.ImportError.browserAccessDenied(details: "no access"),
            context: context))
        #expect(strategy.shouldFallback(
            on: OpenAIDashboardBrowserCookieImporter.ImportError.dashboardStillRequiresLogin,
            context: context))
        #expect(strategy.shouldFallback(
            on: OpenAIDashboardFetcher.FetchError.loginRequired,
            context: context))
    }

    @Test
    func codex_falls_back_for_dashboard_data_errors_in_auto() {
        let context = self.makeContext()
        let strategy = CodexWebDashboardStrategy()
        #expect(strategy.shouldFallback(
            on: OpenAIDashboardFetcher.FetchError.noDashboardData(body: "missing"),
            context: context))
    }

    @Test
    func codex_retries_fresh_browser_import_for_missing_usage_and_no_data() {
        #expect(CodexWebDashboardStrategy.shouldRetryWithFreshBrowserImport(
            after: OpenAIWebCodexError.missingUsage))
        #expect(CodexWebDashboardStrategy.shouldRetryWithFreshBrowserImport(
            after: OpenAIDashboardFetcher.FetchError.noDashboardData(body: "missing")))
        #expect(!CodexWebDashboardStrategy.shouldRetryWithFreshBrowserImport(
            after: OpenAIDashboardFetcher.FetchError.loginRequired))
        #expect(!CodexWebDashboardStrategy.shouldRetryWithFreshBrowserImport(
            after: OpenAIWebCodexError.timedOut(seconds: 30)))
    }

    @Test
    func codex_shared_deadline_timeout_has_useful_error() {
        let error = OpenAIWebCodexError.timedOut(seconds: 30)
        #expect(error.localizedDescription == "OpenAI web dashboard fetch timed out after 30 seconds.")
    }

    @Test
    func codex_display_only_falls_back_in_auto() {
        let strategy = CodexWebDashboardStrategy()
        let decision = self.makeCodexDisplayOnlyDecision()

        #expect(strategy.shouldFallback(
            on: CodexDashboardPolicyError.displayOnly(decision),
            context: self.makeContext(sourceMode: .auto)))
    }

    @Test
    func codex_display_only_does_not_fall_back_in_explicit_web() {
        let strategy = CodexWebDashboardStrategy()
        let decision = self.makeCodexDisplayOnlyDecision()

        #expect(!strategy.shouldFallback(
            on: CodexDashboardPolicyError.displayOnly(decision),
            context: self.makeContext(sourceMode: .web)))
    }

    @Test
    func codex_web_strategy_is_unavailable_when_managed_account_store_is_unreadable() async {
        let context = self.makeContext(settings: ProviderSettingsSnapshot.make(
            codex: .init(
                usageDataSource: .auto,
                cookieSource: .auto,
                manualCookieHeader: nil,
                managedAccountStoreUnreadable: true)))
        let strategy = CodexWebDashboardStrategy()
        let available = await strategy.isAvailable(context)

        #expect(!available)
    }

    @Test
    func codex_web_strategy_is_unavailable_when_selected_managed_target_is_unavailable() async {
        let context = self.makeContext(settings: ProviderSettingsSnapshot.make(
            codex: .init(
                usageDataSource: .auto,
                cookieSource: .auto,
                manualCookieHeader: nil,
                managedAccountTargetUnavailable: true)))
        let strategy = CodexWebDashboardStrategy()
        let available = await strategy.isAvailable(context)

        #expect(!available)
    }

    @Test
    func codex_web_strategy_fails_closed_when_profile_target_is_unavailable() async {
        let settings = ProviderSettingsSnapshot.make(
            codex: .init(
                usageDataSource: .auto,
                cookieSource: .auto,
                manualCookieHeader: nil,
                profileAccountTargetUnavailable: true))
        let strategy = CodexWebDashboardStrategy()

        let autoContext = self.makeContext(sourceMode: .auto, settings: settings)
        let autoAvailable = await strategy.isAvailable(autoContext)
        #expect(!autoAvailable)

        let explicitWebContext = self.makeContext(sourceMode: .web, settings: settings)
        let explicitWebAvailable = await strategy.isAvailable(explicitWebContext)
        #expect(explicitWebAvailable)
        do {
            _ = try await strategy.fetch(explicitWebContext)
            Issue.record("Expected unavailable profile target to require login")
        } catch OpenAIDashboardFetcher.FetchError.loginRequired {
            // Expected before browser import can accept an arbitrary account.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func claude_falls_back_when_no_session_key() {
        let context = self.makeContext()
        let strategy = ClaudeWebFetchStrategy(browserDetection: BrowserDetection(cacheTTL: 0))
        #expect(strategy.shouldFallback(on: ClaudeWebAPIFetcher.FetchError.noSessionKeyFound, context: context))
        #expect(strategy.shouldFallback(on: ClaudeWebAPIFetcher.FetchError.unauthorized, context: context))
    }

    @Test
    func claude_CLI_fallback_is_enabled_only_for_app_auto() {
        let webAvailableStrategy = ClaudeCLIFetchStrategy(
            useWebExtras: false,
            manualCookieHeader: nil,
            browserDetection: BrowserDetection(cacheTTL: 0),
            hasWebFallback: true)
        let webUnavailableStrategy = ClaudeCLIFetchStrategy(
            useWebExtras: false,
            manualCookieHeader: nil,
            browserDetection: BrowserDetection(cacheTTL: 0),
            hasWebFallback: false)
        let error = ClaudeUsageError.parseFailed("cli failed")
        let webAvailableSettings = self.makeClaudeSettingsSnapshot(cookieHeader: "sessionKey=sk-ant-test")
        let webUnavailableSettings = self.makeClaudeSettingsSnapshot(cookieHeader: "foo=bar")

        #expect(webAvailableStrategy.shouldFallback(
            on: error,
            context: self.makeContext(runtime: .app, sourceMode: .auto, settings: webAvailableSettings)))
        #expect(!webUnavailableStrategy.shouldFallback(
            on: error,
            context: self.makeContext(runtime: .app, sourceMode: .auto, settings: webUnavailableSettings)))
        #expect(!webAvailableStrategy.shouldFallback(
            on: error,
            context: self.makeContext(runtime: .app, sourceMode: .cli)))
        #expect(!webAvailableStrategy.shouldFallback(
            on: error,
            context: self.makeContext(runtime: .app, sourceMode: .web)))
        #expect(!webAvailableStrategy.shouldFallback(
            on: error,
            context: self.makeContext(runtime: .app, sourceMode: .oauth)))
        #expect(!webAvailableStrategy.shouldFallback(
            on: error,
            context: self.makeContext(runtime: .cli, sourceMode: .auto)))
    }

    @Test
    func claude_web_fallback_is_disabled_for_app_auto() {
        let strategy = ClaudeWebFetchStrategy(browserDetection: BrowserDetection(cacheTTL: 0))
        let error = ClaudeWebAPIFetcher.FetchError.unauthorized
        #expect(strategy.shouldFallback(on: error, context: self.makeContext(runtime: .cli, sourceMode: .auto)))
        #expect(!strategy.shouldFallback(on: error, context: self.makeContext(runtime: .app, sourceMode: .auto)))
    }

    private func makeCodexDisplayOnlyDecision() -> CodexDashboardAuthorityDecision {
        CodexDashboardAuthority.evaluate(
            CodexDashboardAuthorityInput(
                sourceKind: .liveWeb,
                proof: CodexDashboardOwnershipProofContext(
                    currentIdentity: .emailOnly(normalizedEmail: "shared@example.com"),
                    expectedScopedEmail: nil,
                    trustedCurrentUsageEmail: nil,
                    dashboardSignedInEmail: "shared@example.com",
                    knownOwners: [
                        CodexDashboardKnownOwnerCandidate(
                            identity: .providerAccount(id: "acct-alpha"),
                            normalizedEmail: "shared@example.com"),
                        CodexDashboardKnownOwnerCandidate(
                            identity: .providerAccount(id: "acct-beta"),
                            normalizedEmail: "shared@example.com"),
                    ]),
                routing: CodexDashboardRoutingHints(
                    targetEmail: "shared@example.com",
                    lastKnownDashboardRoutingEmail: nil)))
    }
}
