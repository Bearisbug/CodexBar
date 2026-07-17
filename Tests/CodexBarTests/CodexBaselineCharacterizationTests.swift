import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CodexBaselineCharacterizationTests {
    private func makeContext(
        runtime: ProviderRuntime,
        sourceMode: ProviderSourceMode,
        env: [String: String] = [:],
        settings: ProviderSettingsSnapshot? = nil,
        includeCredits: Bool = false,
        codexArguments: [String]? = nil) -> ProviderFetchContext
    {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        let fetcher = if let codexArguments {
            UsageFetcher(
                environment: env,
                initializeTimeoutSeconds: 20.0,
                requestTimeoutSeconds: 3.0,
                codexArguments: codexArguments)
        } else {
            UsageFetcher(environment: env, initializeTimeoutSeconds: 20.0, requestTimeoutSeconds: 3.0)
        }
        return ProviderFetchContext(
            runtime: runtime,
            sourceMode: sourceMode,
            includeCredits: includeCredits,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: settings,
            fetcher: fetcher,
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection)
    }

    private func strategyIDs(
        runtime: ProviderRuntime,
        sourceMode: ProviderSourceMode,
        env: [String: String] = [:],
        settings: ProviderSettingsSnapshot? = nil) async -> [String]
    {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .codex)
        let context = self.makeContext(runtime: runtime, sourceMode: sourceMode, env: env, settings: settings)
        let strategies = await descriptor.fetchPlan.pipeline.resolveStrategies(context)
        return strategies.map(\.id)
    }

    private func fetchOutcome(
        runtime: ProviderRuntime,
        sourceMode: ProviderSourceMode,
        env: [String: String] = [:],
        settings: ProviderSettingsSnapshot? = nil,
        includeCredits: Bool = false,
        codexArguments: [String]? = nil) async -> ProviderFetchOutcome
    {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .codex)
        let context = self.makeContext(
            runtime: runtime,
            sourceMode: sourceMode,
            env: env,
            settings: settings,
            includeCredits: includeCredits,
            codexArguments: codexArguments)
        return await descriptor.fetchPlan.fetchOutcome(context: context, provider: .codex)
    }

    private struct StubCodexCLI {
        let executable: String
        let arguments: [String]
    }

    private func makeStubCodexCLI() -> StubCodexCLI {
        let script = """
        if [ -n "${CODEXBAR_STUB_COUNTER:-}" ]; then
          printf '%s\\n' start >> "$CODEXBAR_STUB_COUNTER"
        fi

        while IFS= read -r line; do
          case "$line" in
            *'"method":"initialized"'*|*'"method": "initialized"'*)
              ;;
            *'"method":"initialize"'*|*'"method": "initialize"'*)
              printf '%s\\n' '{"id":1,"result":{}}'
              ;;
            *'"method"'*account*rateLimits*read*)
              if [ "${CODEXBAR_STUB_CREDITS_ONLY:-}" = "1" ]; then
                response='{"id":2,"result":{"rateLimits":{"credits":'
                response="${response}"'{"hasCredits":true,"unlimited":false,"balance":"7"}}}}'
                printf '%s\\n' "$response"
              else
                response='{"id":2,"result":{"rateLimits":{"credits":'
                response="${response}"'{"hasCredits":true,"unlimited":false,"balance":"7"},'
                if [ "${CODEXBAR_STUB_MONTHLY_LIMIT:-}" = "1" ]; then
                  response="${response}"'"individualLimit":{"limit":100000,"used":7761,'
                  response="${response}"'"remainingPercent":92.239,"resetsAt":1782864000},'
                fi
                response="${response}"'"primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1766948068},'
                response="${response}"'"secondary":{"usedPercent":43,"windowDurationMins":10080,'
                response="${response}"'"resetsAt":1767407914}}}}'
                printf '%s\\n' "$response"
              fi
              ;;
            *'"method"'*account*read*)
              response='{"id":3,"result":{"account":{"type":"chatgpt","email":"stub@example.com",'
              response="${response}"'"planType":"pro"},"requiresOpenaiAuth":false}}'
              printf '%s\\n' "$response"
              ;;
          esac
        done
        """
        return StubCodexCLI(executable: "/bin/sh", arguments: ["-c", script])
    }

    private func makeEmptyCodexHome() throws -> URL {
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-empty-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        return homeURL
    }

    private func makeUnavailableOAuthHome() throws -> URL {
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-oauth-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)

        let credentials = CodexOAuthCredentials(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            idToken: nil,
            accountId: "account-id",
            lastRefresh: Date())
        try CodexOAuthCredentialsStore.save(credentials, env: ["CODEX_HOME": homeURL.path])

        let configURL = homeURL.appendingPathComponent("config.toml")
        try "chatgpt_base_url = \"http://127.0.0.1:9\"".write(to: configURL, atomically: true, encoding: .utf8)

        return homeURL
    }

    @Test
    func app_auto_pipeline_order_is_OAuth_then_CLI_without_web() async {
        let strategyIDs = await self.strategyIDs(runtime: .app, sourceMode: .auto)
        #expect(strategyIDs == ["codex.oauth", "codex.cli"])
    }

    @Test
    func CLI_auto_pipeline_order_is_OAuth_then_CLI_without_web() async {
        let strategyIDs = await self.strategyIDs(runtime: .cli, sourceMode: .auto)
        #expect(strategyIDs == ["codex.oauth", "codex.cli"])
    }

    @Test
    func explicit_fetch_plan_modes_keep_single_Codex_strategy_selection() async {
        let appCases: [(ProviderSourceMode, [String])] = [
            (.oauth, ["codex.oauth"]),
            (.cli, ["codex.cli"]),
            (.web, ["codex.web.dashboard"]),
        ]

        for (sourceMode, expected) in appCases {
            let strategyIDs = await self.strategyIDs(runtime: .app, sourceMode: sourceMode)
            #expect(strategyIDs == expected)
        }

        for (sourceMode, expected) in appCases {
            let strategyIDs = await self.strategyIDs(runtime: .cli, sourceMode: sourceMode)
            #expect(strategyIDs == expected)
        }
    }

    @Test
    func app_auto_records_unavailable_OAuth_before_successful_CLI_fallback() async throws {
        let stubCLI = self.makeStubCodexCLI()
        let codexHome = try self.makeEmptyCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHome) }
        let env = [
            "CODEX_CLI_PATH": stubCLI.executable,
            "CODEX_HOME": codexHome.path,
        ]

        let outcome = await self.fetchOutcome(
            runtime: .app,
            sourceMode: .auto,
            env: env,
            codexArguments: stubCLI.arguments)

        #expect(outcome.attempts.map(\.strategyID) == ["codex.oauth", "codex.cli"])
        #expect(outcome.attempts.map(\.wasAvailable) == [false, true])

        switch outcome.result {
        case let .success(result):
            #expect(result.sourceLabel == "codex-cli")
            #expect(result.usage.accountEmail(for: .codex) == "stub@example.com")
            #expect(result.usage.loginMethod(for: .codex) == "pro")
        case let .failure(error):
            Issue.record("Unexpected failure: \(error)")
        }
    }

    @Test
    func app_auto_does_not_fall_back_from_non_auth_failing_OAuth() async throws {
        let stubCLI = self.makeStubCodexCLI()
        let oauthHome = try self.makeUnavailableOAuthHome()
        defer { try? FileManager.default.removeItem(at: oauthHome) }

        let env = [
            "CODEX_CLI_PATH": stubCLI.executable,
            "CODEX_HOME": oauthHome.path,
        ]

        let outcome = await self.fetchOutcome(
            runtime: .app,
            sourceMode: .auto,
            env: env,
            codexArguments: stubCLI.arguments)

        #expect(outcome.attempts.map(\.strategyID) == ["codex.oauth"])
        #expect(outcome.attempts.map(\.wasAvailable) == [true])
        #expect(outcome.attempts[0].errorDescription?.isEmpty == false)

        switch outcome.result {
        case .success:
            Issue.record("Expected non-auth OAuth failure to stop before CLI fallback")
        case let .failure(error as CodexOAuthFetchError):
            switch error {
            case .networkError:
                break
            default:
                Issue.record("Expected network error, got \(error)")
            }
        case let .failure(error):
            Issue.record("Unexpected failure: \(error)")
        }
    }

    @Test
    func Codex_CLI_strategy_fetches_usage_and_credits_with_one_app_server_process() async {
        let stubCLI = self.makeStubCodexCLI()
        let counterURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-stub-counter-\(UUID().uuidString)", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: counterURL) }

        let env = [
            "CODEX_CLI_PATH": stubCLI.executable,
            "CODEXBAR_STUB_COUNTER": counterURL.path,
        ]

        let outcome = await self.fetchOutcome(
            runtime: .app,
            sourceMode: .cli,
            env: env,
            includeCredits: true,
            codexArguments: stubCLI.arguments)

        switch outcome.result {
        case let .success(result):
            #expect(result.sourceLabel == "codex-cli")
            #expect(result.usage.primary?.usedPercent == 12)
            #expect(result.credits?.remaining == 7)
        case let .failure(error):
            Issue.record("Unexpected failure: \(error)")
        }

        let count = (try? String(contentsOf: counterURL, encoding: .utf8))?
            .split(whereSeparator: \.isNewline)
            .count ?? 0
        #expect(count == 1)
    }

    @Test
    func Codex_CLI_strategy_keeps_credits_when_rate_limit_windows_are_absent() async {
        let stubCLI = self.makeStubCodexCLI()

        let outcome = await self.fetchOutcome(
            runtime: .app,
            sourceMode: .cli,
            env: [
                "CODEX_CLI_PATH": stubCLI.executable,
                "CODEXBAR_STUB_CREDITS_ONLY": "1",
            ],
            includeCredits: true,
            codexArguments: stubCLI.arguments)

        switch outcome.result {
        case let .success(result):
            #expect(result.sourceLabel == "codex-cli")
            #expect(result.usage.primary == nil)
            #expect(result.usage.secondary == nil)
            #expect(result.usage.accountEmail(for: .codex) == "stub@example.com")
            #expect(result.credits?.remaining == 7)
        case let .failure(error):
            Issue.record("Unexpected failure: \(error)")
        }
    }

    @Test
    func Codex_CLI_strategy_maps_monthly_credit_limit() async {
        let stubCLI = self.makeStubCodexCLI()

        let outcome = await self.fetchOutcome(
            runtime: .app,
            sourceMode: .cli,
            env: [
                "CODEX_CLI_PATH": stubCLI.executable,
                "CODEXBAR_STUB_MONTHLY_LIMIT": "1",
            ],
            includeCredits: true,
            codexArguments: stubCLI.arguments)

        switch outcome.result {
        case let .success(result):
            let limit = try? #require(result.credits?.codexCreditLimit)
            #expect(limit?.limit == 100_000)
            #expect(limit?.used == 7761)
            #expect(limit?.remaining == 92239)
            #expect(limit?.remainingPercent == 92.239)
            #expect(limit?.resetsAt == Date(timeIntervalSince1970: 1_782_864_000))
        case let .failure(error):
            Issue.record("Unexpected failure: \(error)")
        }
    }

    @Test
    func CLI_auto_records_unavailable_OAuth_before_successful_CLI() async throws {
        let stubCLI = self.makeStubCodexCLI()
        let codexHome = try self.makeEmptyCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHome) }
        let settings = ProviderSettingsSnapshot.make(
            codex: .init(
                usageDataSource: .auto,
                cookieSource: .auto,
                manualCookieHeader: nil,
                managedAccountStoreUnreadable: true))

        let outcome = await self.fetchOutcome(
            runtime: .cli,
            sourceMode: .auto,
            env: [
                "CODEX_CLI_PATH": stubCLI.executable,
                "CODEX_HOME": codexHome.path,
            ],
            settings: settings,
            codexArguments: stubCLI.arguments)

        #expect(outcome.attempts.map(\.strategyID) == ["codex.oauth", "codex.cli"])
        #expect(outcome.attempts.map(\.wasAvailable) == [false, true])

        switch outcome.result {
        case let .success(result):
            #expect(result.sourceLabel == "codex-cli")
            #expect(result.usage.accountEmail(for: .codex) == "stub@example.com")
        case let .failure(error):
            Issue.record("Unexpected failure: \(error)")
        }
    }

    @Test
    func CLI_auto_tries_OAuth_before_missing_CLI_fallback() async throws {
        let oauthHome = try self.makeUnavailableOAuthHome()
        defer { try? FileManager.default.removeItem(at: oauthHome) }
        let settings = ProviderSettingsSnapshot.make(
            codex: .init(
                usageDataSource: .auto,
                cookieSource: .auto,
                manualCookieHeader: nil,
                managedAccountStoreUnreadable: true))

        let outcome = await self.fetchOutcome(
            runtime: .cli,
            sourceMode: .auto,
            env: [
                "CODEX_CLI_PATH": "/missing/codex",
                "CODEX_HOME": oauthHome.path,
            ],
            settings: settings)

        #expect(outcome.attempts.map(\.strategyID) == ["codex.oauth"])
        #expect(outcome.attempts.map(\.wasAvailable) == [true])

        switch outcome.result {
        case .success:
            Issue.record("Expected unavailable OAuth endpoint to fail before CLI fallback")
        case let .failure(error as CodexOAuthFetchError):
            if case .networkError = error {
                break
            }
            Issue.record("Expected network error, got \(error)")
        case let .failure(error):
            Issue.record("Unexpected failure: \(error)")
        }
    }
}
