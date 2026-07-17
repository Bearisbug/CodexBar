import Foundation
import Testing
@testable import CodexBarCore

struct CopilotUsageFetcherTests {
    @Test
    func fetchGitHubIdentity_uses_shared_client() async throws {
        let transport = ProviderHTTPTransportStub { request in
            guard request.value(forHTTPHeaderField: "Authorization") == "token test-token-placeholder" else {
                throw URLError(.userAuthenticationRequired)
            }
            let response = try HTTPURLResponse(
                url: #require(request.url),
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            return (Data(#"{"login":"testuser","id":123}"#.utf8), response)
        }

        let identity = try await CopilotUsageFetcher.fetchGitHubIdentity(
            token: "test-token-placeholder",
            transport: transport)

        #expect(identity.login == "testuser")
        #expect(identity.id == 123)
        let requests = await transport.requests()
        #expect(requests.count == 1)
        #expect(requests.first?.url?.host == "api.github.com")
    }

    @Test
    func fetch_returns_unavailable_snapshot_for_business_token_billing_placeholders() async throws {
        let transport = ProviderHTTPTransportStub { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "token test-token-placeholder")
            let response = try HTTPURLResponse(
                url: #require(request.url),
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            let data = Data(
                """
                {
                  "copilot_plan": "business",
                  "token_based_billing": true,
                  "quota_snapshots": {
                    "premium_interactions": {
                      "entitlement": 0,
                      "remaining": 0,
                      "percent_remaining": 100,
                      "quota_id": "premium_interactions"
                    },
                    "chat": {
                      "entitlement": 0,
                      "remaining": 0,
                      "percent_remaining": 100,
                      "quota_id": "chat"
                    }
                  }
                }
                """.utf8)
            return (data, response)
        }
        let fetcher = CopilotUsageFetcher(token: "test-token-placeholder", transport: transport)

        let snapshot = try await fetcher.fetch()

        #expect(snapshot.primary == nil)
        #expect(snapshot.secondary == nil)
        #expect(snapshot.identity?.loginMethod == "Business")
    }

    @Test
    func fetch_omits_explicitly_unlimited_only_chat_quota_without_failing() async throws {
        let transport = ProviderHTTPTransportStub { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "token test-token-placeholder")
            let response = try HTTPURLResponse(
                url: #require(request.url),
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            let data = Data(
                """
                {
                  "copilot_plan": "individual",
                  "quota_reset_date": "2026-07-01",
                  "quota_snapshots": {
                    "chat_messages": {
                      "entitlement": 0,
                      "remaining": 0,
                      "quota_id": "chat_messages",
                      "unlimited": true
                    }
                  }
                }
                """.utf8)
            return (data, response)
        }
        let fetcher = CopilotUsageFetcher(token: "test-token-placeholder", transport: transport)

        let snapshot = try await fetcher.fetch()

        #expect(snapshot.primary == nil)
        #expect(snapshot.secondary == nil)
        #expect(snapshot.identity?.loginMethod == "Individual")
    }

    @Test
    func fetch_keeps_finite_premium_quota_and_omits_unlimited_chat_quota() async throws {
        let transport = ProviderHTTPTransportStub { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "token test-token-placeholder")
            let response = try HTTPURLResponse(
                url: #require(request.url),
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            let data = Data(
                """
                {
                  "copilot_plan": "individual",
                  "quota_reset_date": "2026-08-01T00:00:00Z",
                  "quota_snapshots": {
                    "premium_interactions": {
                      "entitlement": 200,
                      "remaining": 156.2,
                      "percent_remaining": 78.1,
                      "quota_id": "premium_interactions"
                    },
                    "chat_messages": {
                      "entitlement": 0,
                      "remaining": 0,
                      "quota_id": "chat_messages",
                      "unlimited": true
                    }
                  }
                }
                """.utf8)
            return (data, response)
        }
        let fetcher = CopilotUsageFetcher(token: "test-token-placeholder", transport: transport)
        let expectedReset = try #require(CopilotUsageFetcher.parseQuotaResetDate("2026-08-01T00:00:00Z"))

        let snapshot = try await fetcher.fetch()

        let usedPercent = try #require(snapshot.primary?.usedPercent)
        #expect(abs(usedPercent - 21.9) < 0.0001)
        #expect(snapshot.primary?.resetsAt == expectedReset)
        #expect(snapshot.secondary == nil)
    }

    @Test
    func fetch_uses_finite_monthly_chat_quota_when_direct_chat_quota_is_unlimited() async throws {
        let transport = ProviderHTTPTransportStub { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "token test-token-placeholder")
            let response = try HTTPURLResponse(
                url: #require(request.url),
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            let data = Data(
                """
                {
                  "copilot_plan": "individual",
                  "quota_snapshots": {
                    "chat_messages": {
                      "entitlement": 0,
                      "remaining": 0,
                      "quota_id": "chat_messages",
                      "unlimited": true
                    }
                  },
                  "monthly_quotas": {
                    "chat": 100
                  },
                  "limited_user_quotas": {
                    "chat": 60
                  }
                }
                """.utf8)
            return (data, response)
        }
        let fetcher = CopilotUsageFetcher(token: "test-token-placeholder", transport: transport)

        let snapshot = try await fetcher.fetch()

        #expect(snapshot.primary == nil)
        #expect(snapshot.secondary?.usedPercent == 40)
    }

    @Test
    func fetch_attaches_quota_reset_date_to_copilot_windows() async throws {
        let transport = ProviderHTTPTransportStub { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "token test-token-placeholder")
            let response = try HTTPURLResponse(
                url: #require(request.url),
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            let data = Data(
                """
                {
                  "copilot_plan": "individual",
                  "quota_reset_date": "2026-07-01",
                  "quota_snapshots": {
                    "premium_interactions": {
                      "entitlement": 500,
                      "remaining": 125,
                      "percent_remaining": 25,
                      "quota_id": "premium_interactions"
                    },
                    "chat": {
                      "entitlement": 300,
                      "remaining": 240,
                      "percent_remaining": 80,
                      "quota_id": "chat"
                    }
                  }
                }
                """.utf8)
            return (data, response)
        }
        let fetcher = CopilotUsageFetcher(token: "test-token-placeholder", transport: transport)
        let expectedReset = try #require(CopilotUsageFetcher.parseQuotaResetDate("2026-07-01"))

        let snapshot = try await fetcher.fetch()

        #expect(snapshot.primary?.usedPercent == 75)
        #expect(snapshot.primary?.resetsAt == expectedReset)
        #expect(snapshot.secondary?.usedPercent == 20)
        #expect(snapshot.secondary?.resetsAt == expectedReset)
    }

    @Test
    func makeRateWindow_drops_business_token_billing_placeholder_quota() {
        // entitlement=0/remaining=0/percent_remaining=100 must not become a "0% used"
        // rate window for Copilot Business token-based billing accounts. (#1258)
        let placeholder = CopilotUsageResponse.QuotaSnapshot(
            entitlement: 0,
            remaining: 0,
            percentRemaining: 100,
            quotaId: "premium_interactions")
        #expect(CopilotUsageFetcher.makeRateWindow(from: placeholder) == nil)
    }

    @Test
    func makeRateWindow_drops_unlimited_quota() {
        let unlimited = CopilotUsageResponse.QuotaSnapshot(
            entitlement: 0,
            remaining: 0,
            percentRemaining: 0,
            quotaId: "chat_messages",
            unlimited: true)

        #expect(CopilotUsageFetcher.makeRateWindow(from: unlimited) == nil)
    }

    @Test
    func makeRateWindow_keeps_real_quota_window() {
        let real = CopilotUsageResponse.QuotaSnapshot(
            entitlement: 500,
            remaining: 125,
            percentRemaining: 25,
            quotaId: "premium_interactions")
        let window = CopilotUsageFetcher.makeRateWindow(from: real)
        #expect(window?.usedPercent == 75)
    }

    @Test
    func makeRateWindow_carries_reset_date() {
        let resetDate = Date(timeIntervalSince1970: 1_783_468_800)
        let real = CopilotUsageResponse.QuotaSnapshot(
            entitlement: 500,
            remaining: 125,
            percentRemaining: 25,
            quotaId: "premium_interactions")

        let window = CopilotUsageFetcher.makeRateWindow(from: real, resetsAt: resetDate)

        #expect(window?.usedPercent == 75)
        #expect(window?.resetsAt == resetDate)
    }

    @Test
    func parseQuotaResetDate_supports_date_only_and_ISO_timestamps() throws {
        let dateOnly = try #require(ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z"))
        let iso = try #require(ISO8601DateFormatter().date(from: "2026-07-01T08:30:45Z"))
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractionalISO = try #require(fractionalFormatter.date(from: "2026-07-01T08:30:45.123Z"))

        #expect(CopilotUsageFetcher.parseQuotaResetDate("2026-07-01") == dateOnly)
        #expect(CopilotUsageFetcher.parseQuotaResetDate("2026-07-01T08:30:45Z") == iso)
        #expect(CopilotUsageFetcher.parseQuotaResetDate("2026-07-01T08:30:45.123Z") == fractionalISO)
        #expect(CopilotUsageFetcher.parseQuotaResetDate(" ") == nil)
    }
}
