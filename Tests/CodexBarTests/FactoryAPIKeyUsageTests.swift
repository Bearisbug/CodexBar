import Foundation
import Testing
@testable import CodexBarCore

struct FactorySettingsReaderTests {
    @Test
    func reads_FACTORY_API_KEY_from_environment() {
        let key = FactorySettingsReader.apiKey(
            environment: [FactorySettingsReader.apiTokenKey: "  fk-env-key  "])
        #expect(key == "fk-env-key")
    }

    @Test
    func strips_quotes_from_environment_API_key() {
        let key = FactorySettingsReader.apiKey(
            environment: [FactorySettingsReader.apiTokenKey: "\"fk-quoted\""])
        #expect(key == "fk-quoted")
    }

    @Test
    func falls_back_to_factory_dot_env_file() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-factory-home-\(UUID().uuidString)", isDirectory: true)
        let factoryDir = home.appendingPathComponent(".factory", isDirectory: true)
        try FileManager.default.createDirectory(at: factoryDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let envFile = factoryDir.appendingPathComponent(".env")
        try "export FACTORY_API_KEY=fk-from-dotenv\n".write(to: envFile, atomically: true, encoding: .utf8)

        let key = FactorySettingsReader.apiKey(
            environment: ["HOME": home.path])
        #expect(key == "fk-from-dotenv")
    }

    @Test
    func environment_wins_over_factory_dot_env() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-factory-home-\(UUID().uuidString)", isDirectory: true)
        let factoryDir = home.appendingPathComponent(".factory", isDirectory: true)
        try FileManager.default.createDirectory(at: factoryDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let envFile = factoryDir.appendingPathComponent(".env")
        try "FACTORY_API_KEY=fk-from-dotenv\n".write(to: envFile, atomically: true, encoding: .utf8)

        let key = FactorySettingsReader.apiKey(
            environment: [
                FactorySettingsReader.apiTokenKey: "fk-env",
                "HOME": home.path,
            ])
        #expect(key == "fk-env")
    }

    @Test
    func skips_dotenv_when_HOME_is_absent() {
        let key = FactorySettingsReader.apiKey(environment: [:])
        #expect(key == nil)
    }

    @Test
    func parses_factory_dotenv_variants() {
        #expect(
            FactorySettingsReader.parseFactoryAPIKey(fromDotEnv: "FACTORY_API_KEY=fk-plain") == "fk-plain")
        #expect(
            FactorySettingsReader.parseFactoryAPIKey(fromDotEnv: "export FACTORY_API_KEY='fk-single'")
                == "fk-single")
        #expect(
            FactorySettingsReader.parseFactoryAPIKey(fromDotEnv: "# comment\nFACTORY_API_KEY=\"fk-double\"")
                == "fk-double")
        #expect(FactorySettingsReader.parseFactoryAPIKey(fromDotEnv: "OTHER=1\n") == nil)
    }
}

struct FactoryAPIFetchStrategyTests {
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

    private func makeContext(
        env: [String: String] = [:],
        sourceMode: ProviderSourceMode = .api) -> ProviderFetchContext
    {
        ProviderFetchContext(
            runtime: .cli,
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
    func descriptor_prefers_api_then_web_in_auto_mode() async {
        let strategies = await FactoryProviderDescriptor.descriptor.fetchPlan.pipeline
            .resolveStrategies(self.makeContext(sourceMode: .auto))
        #expect(strategies.map(\.id) == ["factory.api", "factory.web"])
    }

    @Test
    func legacy_cli_source_aliases_auto_strategies() async {
        let modes = FactoryProviderDescriptor.descriptor.fetchPlan.sourceModes
        #expect(modes.contains(.cli))
        #expect(modes.contains(.api))
        #expect(modes.contains(.web))

        let cli = await FactoryProviderDescriptor.descriptor.fetchPlan.pipeline
            .resolveStrategies(self.makeContext(sourceMode: .cli))
        let auto = await FactoryProviderDescriptor.descriptor.fetchPlan.pipeline
            .resolveStrategies(self.makeContext(sourceMode: .auto))
        #expect(cli.map(\.id) == auto.map(\.id))
        #expect(cli.map(\.id) == ["factory.api", "factory.web"])
    }

    @Test
    func descriptor_isolates_api_and_web_source_modes() async {
        let api = await FactoryProviderDescriptor.descriptor.fetchPlan.pipeline
            .resolveStrategies(self.makeContext(sourceMode: .api))
        let web = await FactoryProviderDescriptor.descriptor.fetchPlan.pipeline
            .resolveStrategies(self.makeContext(sourceMode: .web))
        #expect(api.map(\.id) == ["factory.api"])
        #expect(web.map(\.id) == ["factory.web"])
    }

    @Test
    func api_strategy_available_in_api_mode_without_key() async {
        let strategy = FactoryAPIFetchStrategy()
        #expect(await strategy.isAvailable(self.makeContext(sourceMode: .api)))
    }

    @Test
    func api_strategy_skipped_in_auto_mode_without_key() async {
        let strategy = FactoryAPIFetchStrategy()
        #expect(await !strategy.isAvailable(self.makeContext(sourceMode: .auto)))
    }

    @Test
    func api_strategy_available_in_auto_mode_when_key_present() async {
        let strategy = FactoryAPIFetchStrategy()
        let context = self.makeContext(
            env: [FactorySettingsReader.apiTokenKey: "fk-test"],
            sourceMode: .auto)
        #expect(await strategy.isAvailable(context))
    }

    @Test
    func api_strategy_falls_back_in_auto_and_cli_but_not_explicit_api_mode() {
        let strategy = FactoryAPIFetchStrategy()
        #expect(strategy.shouldFallback(
            on: FactoryStatusProbeError.unauthorizedAPIKey,
            context: self.makeContext(sourceMode: .auto)))
        #expect(strategy.shouldFallback(
            on: FactoryStatusProbeError.unauthorizedAPIKey,
            context: self.makeContext(sourceMode: .cli)))
        #expect(!strategy.shouldFallback(
            on: FactoryStatusProbeError.unauthorizedAPIKey,
            context: self.makeContext(sourceMode: .api)))
    }

    @Test
    func api_strategy_surfaces_missing_key_in_api_mode() async {
        let strategy = FactoryAPIFetchStrategy()
        do {
            _ = try await strategy.fetch(self.makeContext(env: [:], sourceMode: .api))
            Issue.record("Expected missingAPIKey")
        } catch let error as FactoryStatusProbeError {
            #expect(error == .missingAPIKey)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

struct FactoryAPIKeyProbeFetchTests {
    @Test
    func fetch_with_api_key_uses_bearer_billing_limits_path() async throws {
        let transport = FactoryAPIKeyStubTransport()
        transport.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.host == "api.factory.ai", url.path == "/api/app/auth/me" {
                let body = """
                {
                  "organization": {
                    "id": "org_1",
                    "name": "Acme",
                    "subscription": {
                      "factoryTier": "team",
                      "orbSubscription": {
                        "plan": { "name": "Team", "id": "plan_1" },
                        "status": "active"
                      }
                    }
                  }
                }
                """
                return Self.makeResponse(url: url, body: body)
            }
            if url.host == "api.factory.ai", url.path == "/api/billing/limits" {
                let body = """
                {
                  "usesTokenRateLimitsBilling": true,
                  "limits": {
                    "standard": {
                      "fiveHour": { "usedPercent": 12, "secondsRemaining": 3600 },
                      "weekly": { "usedPercent": 34, "secondsRemaining": 86400 },
                      "monthly": { "usedPercent": 56, "secondsRemaining": 604800 }
                    }
                  },
                  "extraUsageBalanceCents": 0,
                  "extraUsageAllowed": false,
                  "tokenRateLimitsRolloutEligible": true
                }
                """
                return Self.makeResponse(url: url, body: body)
            }
            return Self.makeResponse(url: url, body: "{}", statusCode: 404)
        }

        let probe = FactoryStatusProbe(
            timeout: 1.0,
            browserDetection: BrowserDetection(
                homeDirectory: "/tmp/codexbar-empty-browser-home",
                cacheTTL: 0,
                fileExists: { _ in false },
                directoryContents: { _ in nil }),
            transport: transport)

        let snapshot = try await probe.fetch(apiKey: "fk-test-key")
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.usedPercent == 12)
        #expect(usage.secondary?.usedPercent == 34)
        #expect(usage.tertiary?.usedPercent == 56)
        #expect(transport.requests.contains { request in
            request.url?.path == "/api/billing/limits"
                && request.value(forHTTPHeaderField: "Authorization") == "Bearer fk-test-key"
        })
    }

    @Test
    func fetch_with_api_key_maps_401_to_notLoggedIn_for_strategy_remapping() async {
        let transport = FactoryAPIKeyStubTransport()
        transport.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.path == "/api/app/auth/me" {
                return Self.makeResponse(url: url, body: "{}", statusCode: 401)
            }
            return Self.makeResponse(url: url, body: "{}", statusCode: 404)
        }

        let probe = FactoryStatusProbe(
            timeout: 1.0,
            browserDetection: BrowserDetection(
                homeDirectory: "/tmp/codexbar-empty-browser-home",
                cacheTTL: 0,
                fileExists: { _ in false },
                directoryContents: { _ in nil }),
            transport: transport)

        do {
            _ = try await probe.fetch(apiKey: "fk-bad")
            Issue.record("Expected notLoggedIn")
        } catch let error as FactoryStatusProbeError {
            #expect(error == .notLoggedIn)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func preserves_api_host_401_over_app_host_404_for_unauthorized_mapping() async {
        let transport = FactoryAPIKeyStubTransport()
        transport.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.host == "api.factory.ai", url.path == "/api/app/auth/me" {
                return Self.makeResponse(url: url, body: "{}", statusCode: 401)
            }
            if url.host == "app.factory.ai", url.path == "/api/app/auth/me" {
                return Self.makeResponse(url: url, body: "{}", statusCode: 404)
            }
            return Self.makeResponse(url: url, body: "{}", statusCode: 404)
        }

        let probe = FactoryStatusProbe(
            timeout: 1.0,
            browserDetection: BrowserDetection(
                homeDirectory: "/tmp/codexbar-empty-browser-home",
                cacheTTL: 0,
                fileExists: { _ in false },
                directoryContents: { _ in nil }),
            transport: transport)

        do {
            _ = try await probe.fetch(apiKey: "fk-bad")
            Issue.record("Expected notLoggedIn")
        } catch let error as FactoryStatusProbeError {
            #expect(error == .notLoggedIn)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func preserves_api_host_403_over_app_host_404_for_unauthorized_mapping() async {
        let transport = FactoryAPIKeyStubTransport()
        transport.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.host == "api.factory.ai", url.path == "/api/app/auth/me" {
                return Self.makeResponse(url: url, body: #"{"detail":"forbidden"}"#, statusCode: 403)
            }
            if url.host == "app.factory.ai", url.path == "/api/app/auth/me" {
                return Self.makeResponse(url: url, body: "{}", statusCode: 404)
            }
            return Self.makeResponse(url: url, body: "{}", statusCode: 404)
        }

        let probe = FactoryStatusProbe(
            timeout: 1.0,
            browserDetection: BrowserDetection(
                homeDirectory: "/tmp/codexbar-empty-browser-home",
                cacheTTL: 0,
                fileExists: { _ in false },
                directoryContents: { _ in nil }),
            transport: transport)

        do {
            _ = try await probe.fetch(apiKey: "fk-bad")
            Issue.record("Expected networkError HTTP 403")
        } catch let error as FactoryStatusProbeError {
            switch error {
            case let .networkError(message):
                #expect(message.contains("HTTP 403"))
            default:
                Issue.record("Expected networkError, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func api_strategy_falls_back_on_recoverable_api_failures_in_auto_mode() {
        let strategy = FactoryAPIFetchStrategy()
        let autoContext = ProviderFetchContext(
            runtime: .cli,
            sourceMode: .auto,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: [:],
            settings: nil,
            fetcher: UsageFetcher(environment: [:]),
            claudeFetcher: StubClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0))
        let apiContext = ProviderFetchContext(
            runtime: .cli,
            sourceMode: .api,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: [:],
            settings: nil,
            fetcher: UsageFetcher(environment: [:]),
            claudeFetcher: StubClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0))

        #expect(strategy.shouldFallback(
            on: FactoryStatusProbeError.networkError("HTTP 500"),
            context: autoContext))
        #expect(strategy.shouldFallback(
            on: FactoryStatusProbeError.parseFailed("bad json"),
            context: autoContext))
        #expect(strategy.shouldFallback(
            on: FactoryStatusProbeError.unauthorizedAPIKey,
            context: autoContext))
        #expect(strategy.shouldFallback(
            on: URLError(.timedOut),
            context: autoContext))
        #expect(!strategy.shouldFallback(
            on: CancellationError(),
            context: autoContext))
        #expect(!strategy.shouldFallback(
            on: FactoryStatusProbeError.networkError("HTTP 500"),
            context: apiContext))
        #expect(!strategy.shouldFallback(
            on: FactoryStatusProbeError.parseFailed("bad json"),
            context: apiContext))
    }

    @Test
    func empty_api_key_throws_missingAPIKey() async {
        let probe = FactoryStatusProbe(
            browserDetection: BrowserDetection(cacheTTL: 0),
            transport: FactoryAPIKeyStubTransport())
        do {
            _ = try await probe.fetch(apiKey: "   ")
            Issue.record("Expected missingAPIKey")
        } catch let error as FactoryStatusProbeError {
            #expect(error == .missingAPIKey)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

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

    private static func makeResponse(
        url: URL,
        body: String,
        statusCode: Int = 200) -> (HTTPURLResponse, Data)
    {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        return (response, Data(body.utf8))
    }
}

private final class FactoryAPIKeyStubTransport: ProviderHTTPTransport, @unchecked Sendable {
    var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    var requests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.requests.append(request)
        guard let handler else {
            throw URLError(.badServerResponse)
        }
        let (response, data) = try handler(request)
        return (data, response)
    }
}
