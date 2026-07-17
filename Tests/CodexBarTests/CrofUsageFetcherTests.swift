import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CrofUsageFetcherTests {
    @Test
    func usage_URL_points_at_public_usage_API() {
        #expect(CrofUsageFetcher.usageURL.absoluteString == "https://crof.ai/usage_api/")
    }

    @Test
    func usage_response_parses_credits_and_request_quota() throws {
        let json = """
        {"credits":10.0,"requests_plan":1000,"usable_requests":998}
        """

        let snapshot = try CrofUsageFetcher._parseSnapshotForTesting(Data(json.utf8))

        #expect(snapshot.credits == 10)
        #expect(snapshot.requestsPlan == 1000)
        #expect(snapshot.usableRequests == 998)
    }

    @Test
    func usage_snapshot_maps_usable_requests_to_remaining_quota() {
        let snapshot = CrofUsageSnapshot(
            credits: 10,
            requestsPlan: 1000,
            usableRequests: 998,
            updatedAt: Date(timeIntervalSince1970: 1_777_800_000))

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 1)
        #expect(usage.primary?.windowMinutes == 1440)
        #expect(usage.primary?.resetDescription == "998 requests left")
        #expect(usage.secondary?.usedPercent == 0)
        #expect(usage.secondary?.resetDescription == "$10.00")
        #expect(usage.identity?.providerID == .crof)
        #expect(usage.identity?.loginMethod == "API key")
    }

    @Test
    func usage_snapshot_floors_credit_balance_to_cents() {
        let snapshot = CrofUsageSnapshot(
            credits: 9.9999,
            requestsPlan: 1000,
            usableRequests: 998)

        #expect(snapshot.toUsageSnapshot().secondary?.resetDescription == "$9.99")
    }

    @Test
    func usage_snapshot_resets_requests_at_next_America_Chicago_midnight() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let updatedAt = try #require(utc.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 8,
            hour: 18,
            minute: 30)))
        let expectedReset = try #require(utc.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 9,
            hour: 5)))
        let snapshot = CrofUsageSnapshot(
            credits: 10,
            requestsPlan: 1000,
            usableRequests: 998,
            updatedAt: updatedAt)

        #expect(snapshot.toUsageSnapshot().primary?.resetsAt == expectedReset)
    }

    @Test
    func usage_snapshot_clamps_overreported_usable_requests() {
        let snapshot = CrofUsageSnapshot(
            credits: 0,
            requestsPlan: 1000,
            usableRequests: 1200)

        #expect(snapshot.toUsageSnapshot().primary?.usedPercent == 0)
    }

    @Test
    func usage_snapshot_treats_zero_plan_as_exhausted() {
        let snapshot = CrofUsageSnapshot(
            credits: 0,
            requestsPlan: 0,
            usableRequests: 0)

        #expect(snapshot.toUsageSnapshot().primary?.usedPercent == 100)
    }

    @Test
    func fetch_sends_bearer_token() async throws {
        defer {
            CrofStubURLProtocol.handler = nil
            CrofStubURLProtocol.requests = []
        }
        CrofStubURLProtocol.requests = []
        CrofStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer crof-test")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            return try Self.makeResponse(
                url: url,
                body: #"{"credits":10.0,"requests_plan":1000,"usable_requests":998}"#)
        }

        let snapshot = try await CrofUsageFetcher.fetchUsage(apiKey: "crof-test", session: Self.makeSession())

        #expect(snapshot.usableRequests == 998)
        #expect(CrofStubURLProtocol.requests.map(\.url?.absoluteString) == ["https://crof.ai/usage_api/"])
    }

    @Test
    func descriptor_supports_auto_and_API_source_modes() {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .crof)
        #expect(descriptor.metadata.displayName == "Crof")
        #expect(descriptor.metadata.dashboardURL == "https://crof.ai/dashboard")
        #expect(descriptor.fetchPlan.sourceModes == [.auto, .api])
        #expect(descriptor.branding.iconResourceName == "ProviderIcon-crof")
    }

    @Test
    func settings_reader_uses_CROF_API_KEY() {
        let token = CrofSettingsReader.apiKey(environment: [
            CrofSettingsReader.apiKeyEnvironmentKeys[0]: "  crof-token  ",
        ])

        #expect(token == "crof-token")
    }

    @Test
    func token_resolver_uses_crof_environment_token() {
        let env = [CrofSettingsReader.apiKeyEnvironmentKeys[0]: "crof-token"]
        let resolution = ProviderTokenResolver.crofResolution(environment: env)

        #expect(resolution?.token == "crof-token")
        #expect(resolution?.source == .environment)
    }

    @Test
    func config_API_key_override_feeds_crof_environment() {
        let config = ProviderConfig(id: .crof, apiKey: "config-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .crof,
            config: config)

        #expect(env[CrofSettingsReader.apiKeyEnvironmentKeys[0]] == "config-token")
        #expect(ProviderTokenResolver.crofToken(environment: env) == "config-token")
    }

    @Test
    func config_API_key_leaves_existing_crof_environment_token_alone() {
        let key = CrofSettingsReader.apiKeyEnvironmentKeys[0]
        let config = ProviderConfig(id: .crof, apiKey: "config-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [key: "env-token"],
            provider: .crof,
            config: config)

        #expect(env[key] == "env-token")
        #expect(ProviderTokenResolver.crofToken(environment: env) == "env-token")
    }

    @Test
    func missing_credentials_fetch_call_throws_missing_credentials() async {
        do {
            _ = try await CrofUsageFetcher.fetchUsage(apiKey: "   ")
            Issue.record("Expected missingCredentials error")
        } catch let error as CrofUsageError {
            #expect(error == .missingCredentials)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CrofStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func makeResponse(
        url: URL,
        body: String,
        statusCode: Int = 200) throws -> (HTTPURLResponse, Data)
    {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])
        else {
            throw URLError(.badServerResponse)
        }
        return (response, Data(body.utf8))
    }
}

final class CrofStubURLProtocol: URLProtocol {
    private static let _handlerBox = LockIsolated<((URLRequest) throws -> (HTTPURLResponse, Data))?>(nil)
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { Self._handlerBox.value }
        set { Self._handlerBox.setValue(newValue) }
    }

    nonisolated(unsafe) static var requests: [URLRequest] = []

    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "crof.ai"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requests.append(self.request)
        guard let handler = Self.handler else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(self.request)
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        } catch {
            self.client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
