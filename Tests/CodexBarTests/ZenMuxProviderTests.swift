import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct ZenMuxProviderTests {
    @Test
    func subscription_and_balance_map_to_quota_windows_and_USD_PAYG() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer management-key")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(url.scheme == "https")
            #expect(url.host == "zenmux.ai")
            #expect(url.port == nil)
            #expect(url.user == nil)
            #expect(url.password == nil)
            #expect(url.query == nil)
            #expect(url.fragment == nil)
            switch url.path {
            case "/api/v1/management/subscription/detail":
                #expect(url.absoluteString == "https://zenmux.ai/api/v1/management/subscription/detail")
                return Self.response(url: url, body: Self.subscriptionFixture)
            case "/api/v1/management/payg/balance":
                #expect(url.absoluteString == "https://zenmux.ai/api/v1/management/payg/balance")
                return Self.response(
                    url: url,
                    body: Self.balanceFixture)
            default:
                throw URLError(.badURL)
            }
        }

        let result = try await ZenMuxUsageFetcher.fetchUsage(
            "management-key",
            includePaygBalance: true,
            transport: transport,
            now: now)
        let usage = result.usage.toUsageSnapshot(paygBalanceUSD: result.paygBalanceUSD)

        #expect(abs((usage.primary?.usedPercent ?? 0) - 7.15) < 0.0001)
        #expect(usage.primary?.windowMinutes == 300)
        #expect(usage.primary?.resetDescription == "57.20 / 800 flows")
        #expect(abs((usage.secondary?.usedPercent ?? 0) - 6.73) < 0.0001)
        #expect(usage.secondary?.windowMinutes == 10080)
        #expect(usage.secondary?.resetDescription == "416.11 / 6182 flows")
        #expect(usage.loginMethod(for: .zenmux) == "Ultra plan")
        #expect(usage.subscriptionRenewsAt == nil)
        #expect(usage.subscriptionExpiresAt == Self.date("2026-04-12T08:26:56.000Z"))
        #expect(usage.providerCost?.used == 482.74)
        #expect(usage.providerCost?.currencyCode == "USD")
        #expect(usage.providerCost?.period == "ZenMux PAYG balance")
        #expect(result.paygBalanceUSD == 482.74)
    }

    @Test
    func unhealthy_account_status_is_included_in_identity() async throws {
        let body = Self.subscriptionFixture.replacingOccurrences(
            of: #""account_status": "healthy""#,
            with: #""account_status": "monitored""#)
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            return Self.response(url: url, body: body)
        }

        let result = try await ZenMuxUsageFetcher.fetchUsage(
            "management-key",
            includePaygBalance: false,
            transport: transport)

        #expect(result.usage.toUsageSnapshot().loginMethod(for: .zenmux) == "Ultra plan · Monitored")
        #expect(result.paygBalanceUSD == nil)
    }

    @Test
    func balance_failure_does_not_discard_subscription_usage() async throws {
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            if url.path.hasSuffix("/subscription/detail") {
                return Self.response(url: url, body: Self.subscriptionFixture)
            }
            return Self.response(url: url, body: #"{"error":"unavailable"}"#, statusCode: 500)
        }

        let result = try await ZenMuxUsageFetcher.fetchUsage(
            "management-key",
            includePaygBalance: true,
            transport: transport)

        #expect(abs((result.usage.toUsageSnapshot().primary?.usedPercent ?? 0) - 7.15) < 0.0001)
        #expect(result.paygBalanceUSD == nil)
    }

    @Test
    func balance_auth_failure_is_not_hidden() async {
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            if url.path.hasSuffix("/subscription/detail") {
                return Self.response(url: url, body: Self.subscriptionFixture)
            }
            return Self.response(url: url, body: #"{"error":"unauthorized"}"#, statusCode: 401)
        }

        do {
            _ = try await ZenMuxUsageFetcher.fetchUsage(
                "management-key",
                includePaygBalance: true,
                transport: transport)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                error as? ZenMuxUsageError == .authenticationRejected
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func balance_cancellation_is_preserved() async {
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            if url.path.hasSuffix("/subscription/detail") {
                return Self.response(url: url, body: Self.subscriptionFixture)
            }
            throw URLError(.cancelled)
        }

        do {
            _ = try await ZenMuxUsageFetcher.fetchUsage(
                "management-key",
                includePaygBalance: true,
                transport: transport)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                error is CancellationError
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func missing_and_invalid_credentials_fail_clearly() async {
        do {
            _ = try await ZenMuxUsageFetcher.fetchUsage(
                "  ",
                includePaygBalance: false)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                error as? ZenMuxUsageError == .notConfigured
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }

        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            return Self.response(url: url, body: #"{"error":"unauthorized"}"#, statusCode: 403)
        }
        do {
            _ = try await ZenMuxUsageFetcher.fetchUsage(
                "wrong-key",
                includePaygBalance: false,
                transport: transport)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                error as? ZenMuxUsageError == .authenticationRejected
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func malformed_subscription_payload_fails_parsing() async {
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            return Self.response(url: url, body: #"{"success":true,"data":{"plan":{}}}"#)
        }

        do {
            _ = try await ZenMuxUsageFetcher.fetchUsage(
                "management-key",
                includePaygBalance: false,
                transport: transport)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case .parseFailed = error as? ZenMuxUsageError else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func non_USD_PAYG_balance_is_ignored_without_discarding_quota_usage() async throws {
        let nonUSDBalance = Self.balanceFixture.replacingOccurrences(
            of: #""currency": "usd""#,
            with: #""currency": "eur""#)
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            return Self.response(
                url: url,
                body: url.path.hasSuffix("/payg/balance") ? nonUSDBalance : Self.subscriptionFixture)
        }

        let result = try await ZenMuxUsageFetcher.fetchUsage(
            "management-key",
            includePaygBalance: true,
            transport: transport)

        #expect(result.paygBalanceUSD == nil)
        #expect(abs((result.usage.toUsageSnapshot().primary?.usedPercent ?? 0) - 7.15) < 0.0001)
    }

    @Test
    func negative_overdue_PAYG_balance_remains_visible() async throws {
        let overdueBalance = Self.balanceFixture.replacingOccurrences(
            of: #""total_credits": 482.74"#,
            with: #""total_credits": -12.34"#)
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            return Self.response(
                url: url,
                body: url.path.hasSuffix("/payg/balance") ? overdueBalance : Self.subscriptionFixture)
        }

        let result = try await ZenMuxUsageFetcher.fetchUsage(
            "management-key",
            includePaygBalance: true,
            transport: transport)
        let snapshot = result.usage.toUsageSnapshot(paygBalanceUSD: result.paygBalanceUSD)

        #expect(result.paygBalanceUSD == -12.34)
        #expect(snapshot.providerCost?.used == -12.34)
    }

    @Test
    func settings_reader_trims_quotes() {
        #expect(ZenMuxSettingsReader.managementAPIKey(environment: [
            ZenMuxSettingsReader.managementAPIKeyEnvironmentKey: "  'management-key'  ",
        ]) == "management-key")
        #expect(ZenMuxSettingsReader.managementAPIKey(environment: [:]) == nil)
    }

    @Test @MainActor
    func descriptor_and_app_registry_include_ZenMux() throws {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .zenmux)
        #expect(descriptor.metadata.displayName == "ZenMux")
        #expect(descriptor.metadata.defaultEnabled == false)
        #expect(!descriptor.metadata.supportsCredits)
        #expect(descriptor.fetchPlan.sourceModes == [.auto, .api])

        let implementation = try #require(ProviderImplementationRegistry.implementation(for: .zenmux))
        #expect(implementation is ZenMuxProviderImplementation)
    }

    @Test @MainActor
    func menu_card_uses_compact_flow_expiry_and_USD_PAYG_labels() async throws {
        let now = try #require(Self.date("2026-03-24T07:35:09.000Z"))
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            return Self.response(
                url: url,
                body: url.path.hasSuffix("/payg/balance") ? Self.balanceFixture : Self.subscriptionFixture)
        }
        let result = try await ZenMuxUsageFetcher.fetchUsage(
            "management-key",
            includePaygBalance: true,
            transport: transport,
            now: now)
        let snapshot = result.usage.toUsageSnapshot(paygBalanceUSD: result.paygBalanceUSD)
        let model = UsageMenuCardView.Model.make(.init(
            provider: .zenmux,
            metadata: ZenMuxProviderDescriptor.descriptor.metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: true,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        let primary = try #require(model.metrics.first { $0.id == "primary" })
        let secondary = try #require(model.metrics.first { $0.id == "secondary" })
        #expect(primary.detailLeftText == "57.20 / 800 flows")
        #expect(primary.detailRightText == nil)
        #expect(primary.resetText == "Resets in 1h")
        #expect(secondary.detailLeftText == "416.11 / 6182 flows")
        #expect(secondary.detailRightText == nil)
        // The expiry note is intentionally locale-formatted; compute the expected
        // string the same way so the test passes on non-English machines.
        let expiryFormatter = DateFormatter()
        expiryFormatter.locale = Locale.current
        expiryFormatter.timeZone = .current
        expiryFormatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        let expectedExpiry = try expiryFormatter.string(from: #require(Self.date("2026-04-12T08:26:56.000Z")))
        #expect(model.usageNotes == ["Plan expires: \(expectedExpiry)"])
        #expect(model.creditsText == nil)
        #expect(model.providerCost?.title == "Pay-as-you-go")
        #expect(model.providerCost?.spendLine == "Balance: $482.74")
    }

    private static let subscriptionFixture = #"""
    {
      "success": true,
      "data": {
        "plan": {
          "tier": "ultra",
          "amount_usd": 200,
          "interval": "month",
          "expires_at": "2026-04-12T08:26:56.000Z"
        },
        "currency": "usd",
        "base_usd_per_flow": 0.03283,
        "effective_usd_per_flow": 0.03283,
        "account_status": "healthy",
        "quota_5_hour": {
          "usage_percentage": 0.0715,
          "resets_at": "2026-03-24T08:35:09.000Z",
          "max_flows": 800,
          "used_flows": 57.2,
          "remaining_flows": 742.8,
          "used_value_usd": 1.88,
          "max_value_usd": 26.27
        },
        "quota_7_day": {
          "usage_percentage": 0.0673,
          "resets_at": "2026-03-26T02:15:05.000Z",
          "max_flows": 6182,
          "used_flows": 416.11,
          "remaining_flows": 5765.89,
          "used_value_usd": 13.66,
          "max_value_usd": 202.99
        },
        "quota_monthly": {
          "max_flows": 34560,
          "max_value_usd": 1134.33
        }
      }
    }
    """#

    private static let balanceFixture = #"""
    {
      "success": true,
      "data": {
        "currency": "usd",
        "total_credits": 482.74,
        "top_up_credits": 35,
        "bonus_credits": 447.74
      }
    }
    """#

    private static func response(
        url: URL,
        body: String,
        statusCode: Int = 200) -> (Data, URLResponse)
    {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        return (Data(body.utf8), response)
    }

    private static func date(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
    }
}
