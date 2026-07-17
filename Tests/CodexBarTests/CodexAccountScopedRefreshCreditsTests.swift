import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

extension CodexAccountScopedRefreshTests {
    @Test
    func credits_refresh_honors_explicit_codex_oauth_source_without_raw_CLI_fallback() async throws {
        let settings = self.makeSettingsStore(suite: "CodexAccountScopedRefreshTests-oauth-credits-source")
        settings.refreshFrequency = .manual
        settings.codexUsageDataSource = .oauth
        settings._test_liveSystemCodexAccount = self.liveAccount(email: "alpha@example.com")

        let store = self.makeUsageStore(
            settings: settings,
            environmentBase: ["CODEX_CLI_PATH": "/missing/codex"])
        let usage = self.codexSnapshot(email: "alpha@example.com", usedPercent: 10)
        store._setSnapshotForTesting(usage, provider: .codex)

        let oauthStrategy = TestCodexFetchStrategy(
            loader: { usage },
            credits: self.credits(remaining: 77),
            id: "codex.oauth",
            kind: .oauth,
            sourceLabel: "codex.oauth")
        let cliStrategy = ThrowingTestCodexFetchStrategy {
            throw TestRefreshError(message: "CLI strategy should not run for explicit OAuth credits refresh")
        }
        let baseSpec = try #require(store.providerSpecs[.codex])
        store.providerSpecs[.codex] = Self.makeCodexProviderSpec(baseSpec: baseSpec) { context in
            switch context.sourceMode {
            case .oauth:
                [oauthStrategy]
            case .cli:
                [cliStrategy]
            case .auto:
                [oauthStrategy, cliStrategy]
            case .web, .api:
                []
            }
        }

        await store.refreshCreditsIfNeeded()

        #expect(store.credits?.remaining == 77)
        #expect(store.lastCreditsError == nil)
        #expect(store.lastCreditsSource == .api)
    }

    @Test
    func auto_credits_refresh_falls_back_when_oauth_usage_omits_credits() async throws {
        let settings = self.makeSettingsStore(suite: "CodexAccountScopedRefreshTests-auto-credits-fallback")
        settings.refreshFrequency = .manual
        settings.codexUsageDataSource = .auto
        settings._test_liveSystemCodexAccount = self.liveAccount(email: "alpha@example.com")

        let store = self.makeUsageStore(settings: settings)
        let usage = self.codexSnapshot(email: "alpha@example.com", usedPercent: 10)
        store._setSnapshotForTesting(usage, provider: .codex)

        let oauthStrategy = TestCodexFetchStrategy(
            loader: { usage },
            credits: nil,
            id: "codex.oauth",
            kind: .oauth,
            sourceLabel: "codex.oauth")
        let cliStrategy = TestCodexFetchStrategy(
            loader: { usage },
            credits: self.credits(remaining: 41),
            id: "codex.cli",
            kind: .cli,
            sourceLabel: "codex.cli")
        let baseSpec = try #require(store.providerSpecs[.codex])
        store.providerSpecs[.codex] = Self.makeCodexProviderSpec(baseSpec: baseSpec) { context in
            switch context.sourceMode {
            case .auto:
                [oauthStrategy, cliStrategy]
            case .oauth:
                [oauthStrategy]
            case .cli:
                [cliStrategy]
            case .web, .api:
                []
            }
        }

        await store.refreshCreditsIfNeeded()

        #expect(store.credits?.remaining == 41)
        #expect(store.lastCreditsError == nil)
        #expect(store.lastCreditsSource == .api)
    }
}
