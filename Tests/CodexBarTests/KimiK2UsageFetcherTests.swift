import Foundation
import Testing
@testable import CodexBarCore

struct KimiK2UsageFetcherTests {
    @Test(arguments: [nil, "  \n"] as [String?])
    func provider_reports_a_missing_or_blank_API_key_instead_of_a_generic_unavailable_strategy(
        apiKey: String?) async
    {
        let environment = apiKey.map { ["KIMI_K2_API_KEY": $0] } ?? [:]
        let context = Self.makeContext(environment: environment)

        let outcome = await KimiK2ProviderDescriptor.descriptor.fetchOutcome(context: context)

        guard case let .failure(error) = outcome.result else {
            Issue.record("Expected missing credentials failure")
            return
        }
        #expect(error.localizedDescription == "Missing Kimi K2 API key.")
        #expect(outcome.attempts.count == 1)
        #expect(outcome.attempts.first?.wasAvailable == true)
    }

    @Test
    func trims_API_key_before_sending_authorization() async throws {
        let fixtureKey = "test-token"
        let paddedKey = "  \(fixtureKey)\n"
        let transport = ProviderHTTPTransportHandler { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == ["Bearer", fixtureKey].joined(separator: " "))
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil))
            return (Data(#"{"credits_remaining":10}"#.utf8), response)
        }

        let snapshot = try await KimiK2UsageFetcher.fetchUsage(
            apiKey: paddedKey,
            transport: transport)

        #expect(snapshot.summary.remaining == 10)
    }

    @Test
    func maps_rejected_API_key_to_invalid_credentials() async throws {
        let transport = ProviderHTTPTransportHandler { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil))
            return (Data(#"{\"error\":\"fixture_unauthorized\"}"#.utf8), response)
        }

        do {
            try await KimiK2UsageFetcher.fetchUsage(apiKey: "test-token", transport: transport)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case KimiK2UsageError.invalidCredentials = error else { return false }
                return error.localizedDescription == "Kimi K2 API key is invalid or expired."
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test(arguments: [403, 500])
    func preserves_non_credential_responses_as_API_errors(statusCode: Int) async throws {
        let transport = ProviderHTTPTransportHandler { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil))
            return (Data(#"{"error":"fixture_failure"}"#.utf8), response)
        }

        do {
            try await KimiK2UsageFetcher.fetchUsage(apiKey: "test-token", transport: transport)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case let KimiK2UsageError.apiError(message) = error else { return false }
                return message.contains("fixture_failure")
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func parses_usage_from_nested_usage() throws {
        let json = """
        {
          "data": {
            "usage": {
              "total": 120,
              "credits_remaining": 30,
              "average_tokens": 42,
              "updated_at": "2024-01-02T03:04:05Z"
            }
          }
        }
        """

        let summary = try KimiK2UsageFetcher._parseSummaryForTesting(Data(json.utf8))
        let expectedDate = Date(timeIntervalSince1970: 1_704_164_645)

        #expect(summary.consumed == 120)
        #expect(summary.remaining == 30)
        #expect(summary.averageTokens == 42)
        #expect(abs(summary.updatedAt.timeIntervalSince1970 - expectedDate.timeIntervalSince1970) < 0.5)
    }

    @Test
    func uses_header_fallback_for_remaining_credits() throws {
        let json = """
        { "total_credits_consumed": 50 }
        """
        let headers: [AnyHashable: Any] = ["X-Credits-Remaining": "25"]

        let summary = try KimiK2UsageFetcher._parseSummaryForTesting(Data(json.utf8), headers: headers)

        #expect(summary.consumed == 50)
        #expect(summary.remaining == 25)
    }

    @Test
    func fetch_ignores_non_finite_usage_values() async throws {
        let json = """
        {
          "total_credits_consumed": "NaN",
          "credits_remaining": "Infinity",
          "average_tokens": "1e309"
        }
        """
        let transport = ProviderHTTPTransportHandler { request in
            let url = try #require(request.url)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["X-Credits-Remaining": "-Infinity"]))
            return (Data(json.utf8), response)
        }

        let snapshot = try await KimiK2UsageFetcher.fetchUsage(apiKey: "test-key", transport: transport)
        let summary = snapshot.summary

        #expect(summary.consumed == 0)
        #expect(summary.remaining == 0)
        #expect(summary.averageTokens == nil)
    }

    @Test
    func parses_numeric_timestamp_seconds() throws {
        let json = """
        {
          "timestamp": 1700000000,
          "credits_remaining": 10,
          "total_credits_consumed": 5
        }
        """

        let summary = try KimiK2UsageFetcher._parseSummaryForTesting(Data(json.utf8))
        let expected = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(abs(summary.updatedAt.timeIntervalSince1970 - expected.timeIntervalSince1970) < 0.5)
    }

    @Test
    func parses_numeric_timestamp_milliseconds() throws {
        let json = """
        {
          "timestamp": 1700000000000,
          "credits_remaining": 10,
          "total_credits_consumed": 5
        }
        """

        let summary = try KimiK2UsageFetcher._parseSummaryForTesting(Data(json.utf8))
        let expected = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(abs(summary.updatedAt.timeIntervalSince1970 - expected.timeIntervalSince1970) < 0.5)
    }

    @Test
    func treats_exact_millisecond_cutoff_as_milliseconds() throws {
        let json = """
        {
          "timestamp": 1000000000000,
          "credits_remaining": 10,
          "total_credits_consumed": 5
        }
        """

        let summary = try KimiK2UsageFetcher._parseSummaryForTesting(Data(json.utf8))

        #expect(summary.updatedAt == Date(timeIntervalSince1970: 1_000_000_000))
    }

    @Test(arguments: ["NaN", "Infinity", "1e308", "0", "-1"])
    func ignores_invalid_numeric_timestamps(timestamp: String) throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let json = """
        {
          "timestamp": "\(timestamp)",
          "credits_remaining": 10,
          "total_credits_consumed": 5
        }
        """

        let summary = try KimiK2UsageFetcher._parseSummaryForTesting(Data(json.utf8), now: now)

        #expect(summary.updatedAt == now)
    }

    @Test
    func ignores_timestamps_beyond_distant_future() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let timestamp = Date.distantFuture.timeIntervalSince1970 + 1
        let json = """
        {
          "timestamp": "\(timestamp)",
          "credits_remaining": 10,
          "total_credits_consumed": 5
        }
        """

        let summary = try KimiK2UsageFetcher._parseSummaryForTesting(Data(json.utf8), now: now)

        #expect(summary.updatedAt == now)
    }

    @Test
    func invalid_root_returns_parse_error() {
        let json = """
        [{ "total": 1 }]
        """

        do {
            _ = try KimiK2UsageFetcher._parseSummaryForTesting(Data(json.utf8))
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case let KimiK2UsageError.parseFailed(message) = error else { return false }
                return message == "Root JSON is not an object."
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func converts_api_key_credits_into_text_only_snapshot() {
        let usage = KimiK2UsageSummary(
            consumed: 10,
            remaining: 25,
            averageTokens: nil,
            updatedAt: Date()).toUsageSnapshot()

        #expect(usage.primary == nil)
        #expect(usage.identity?.providerID == .kimik2)
        #expect(usage.identity?.loginMethod == "Credits: 25 left")
    }

    private static func makeContext(environment: [String: String]) -> ProviderFetchContext {
        ProviderFetchContext(
            runtime: .cli,
            sourceMode: .api,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: nil,
            fetcher: UsageFetcher(environment: environment),
            claudeFetcher: KimiK2StubClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0))
    }
}

private struct KimiK2StubClaudeFetcher: ClaudeUsageFetching {
    func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot {
        throw KimiK2UsageError.missingCredentials
    }

    func debugRawProbe(model _: String) async -> String {
        "stub"
    }

    func detectVersion() -> String? {
        nil
    }
}
