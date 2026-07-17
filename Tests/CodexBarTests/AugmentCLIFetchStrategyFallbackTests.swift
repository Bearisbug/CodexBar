import Foundation
import Testing
@testable import CodexBarCore

#if os(macOS)

/// Regression tests for #474: verify that CLI timeout errors trigger fallback
/// to the web strategy instead of stalling the refresh cycle.
struct AugmentCLIFetchStrategyFallbackTests {
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

    // SubprocessRunnerError is not an AuggieCLIError, so it hits the default
    // fallback=true path — the desired behavior for infrastructure errors.

    @Test
    func timeout_error_falls_back_to_web() {
        let strategy = AugmentCLIFetchStrategy()
        let context = self.makeContext()
        let error = SubprocessRunnerError.timedOut("auggie-account-status")
        #expect(strategy.shouldFallback(on: error, context: context) == true)
    }

    @Test
    func binary_not_found_falls_back_to_web() {
        let strategy = AugmentCLIFetchStrategy()
        let context = self.makeContext()
        let error = SubprocessRunnerError.binaryNotFound("/usr/local/bin/auggie")
        #expect(strategy.shouldFallback(on: error, context: context) == true)
    }

    @Test
    func launch_failed_falls_back_to_web() {
        let strategy = AugmentCLIFetchStrategy()
        let context = self.makeContext()
        let error = SubprocessRunnerError.launchFailed("permission denied")
        #expect(strategy.shouldFallback(on: error, context: context) == true)
    }

    @Test
    func not_authenticated_falls_back_to_web() {
        let strategy = AugmentCLIFetchStrategy()
        let context = self.makeContext()
        #expect(strategy.shouldFallback(on: AuggieCLIError.notAuthenticated, context: context) == true)
    }

    @Test
    func no_output_falls_back_to_web() {
        let strategy = AugmentCLIFetchStrategy()
        let context = self.makeContext()
        #expect(strategy.shouldFallback(on: AuggieCLIError.noOutput, context: context) == true)
    }

    @Test
    func parse_error_falls_back_to_web() {
        let strategy = AugmentCLIFetchStrategy()
        let context = self.makeContext()
        #expect(strategy.shouldFallback(on: AuggieCLIError.parseError("bad data"), context: context) == true)
    }

    @Test
    func non_zero_exit_falls_back_to_web() {
        let strategy = AugmentCLIFetchStrategy()
        let context = self.makeContext()
        let error = SubprocessRunnerError.nonZeroExit(code: 1, stderr: "crash")
        #expect(strategy.shouldFallback(on: error, context: context) == true)
    }
}

#endif
