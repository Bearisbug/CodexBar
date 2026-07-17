import Foundation
import Testing
@testable import CodexBarCore

struct OpenCodeGoProviderStrategyTests {
    private struct StubClaudeFetcher: ClaudeUsageFetching {
        func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot {
            throw ClaudeUsageError.parseFailed("stub")
        }

        func debugRawProbe(model _: String) async -> String {
            "stub"
        }

        func detectVersion() -> String? {
            nil
        }
    }

    private func makeContext(sourceMode: ProviderSourceMode = .auto) -> ProviderFetchContext {
        let env: [String: String] = [:]
        return ProviderFetchContext(
            runtime: .app,
            sourceMode: sourceMode,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: nil,
            fetcher: UsageFetcher(environment: env),
            claudeFetcher: StubClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0))
    }

    @Test
    func auto_source_prefers_web_before_local_fallback() async {
        let descriptor = OpenCodeGoProviderDescriptor.makeDescriptor()
        let strategies = await descriptor.fetchPlan.pipeline.resolveStrategies(self.makeContext())

        #expect(strategies.map(\.id) == ["opencodego.web", "opencodego.local"])
    }

    @Test
    func web_source_does_not_include_local_fallback() async {
        let descriptor = OpenCodeGoProviderDescriptor.makeDescriptor()
        let strategies = await descriptor.fetchPlan.pipeline.resolveStrategies(self.makeContext(sourceMode: .web))

        #expect(strategies.map(\.id) == ["opencodego.web"])
    }

    @Test
    func web_strategy_falls_back_to_local_only_for_auth_setup_failures_in_auto_mode() {
        let strategy = OpenCodeGoUsageFetchStrategy()
        let autoContext = self.makeContext()
        let webContext = self.makeContext(sourceMode: .web)

        #expect(strategy.shouldFallback(on: OpenCodeGoSettingsError.missingCookie, context: autoContext))
        #expect(strategy.shouldFallback(on: OpenCodeGoSettingsError.invalidCookie, context: autoContext))
        #expect(strategy.shouldFallback(on: OpenCodeGoUsageError.invalidCredentials, context: autoContext))
        #expect(!strategy.shouldFallback(on: OpenCodeGoUsageError.networkError("timeout"), context: autoContext))
        #expect(!strategy.shouldFallback(on: OpenCodeGoSettingsError.missingCookie, context: webContext))
    }
}
