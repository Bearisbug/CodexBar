import Foundation
import Testing
@testable import CodexBarCore

struct OpenAIDashboardFetcherCreditsWaitTests {
    @Test
    func waits_after_scroll_request() {
        let now = Date()
        let shouldWait = OpenAIDashboardFetcher.shouldWaitForCreditsHistory(.init(
            now: now,
            anyDashboardSignalAt: now.addingTimeInterval(-10),
            creditsHeaderVisibleAt: nil,
            creditsHeaderPresent: false,
            creditsHeaderInViewport: false,
            didScrollToCredits: true))
        #expect(shouldWait == true)
    }

    @Test
    func waits_briefly_when_header_visible_but_table_empty() {
        let now = Date()
        let visibleAt = now.addingTimeInterval(-1.0)
        let shouldWait = OpenAIDashboardFetcher.shouldWaitForCreditsHistory(.init(
            now: now,
            anyDashboardSignalAt: now.addingTimeInterval(-10),
            creditsHeaderVisibleAt: visibleAt,
            creditsHeaderPresent: true,
            creditsHeaderInViewport: true,
            didScrollToCredits: false))
        #expect(shouldWait == true)
    }

    @Test
    func stops_waiting_after_header_has_been_visible_long_enough() {
        let now = Date()
        let visibleAt = now.addingTimeInterval(-3.0)
        let shouldWait = OpenAIDashboardFetcher.shouldWaitForCreditsHistory(.init(
            now: now,
            anyDashboardSignalAt: now.addingTimeInterval(-10),
            creditsHeaderVisibleAt: visibleAt,
            creditsHeaderPresent: true,
            creditsHeaderInViewport: true,
            didScrollToCredits: false))
        #expect(shouldWait == false)
    }

    @Test
    func waits_briefly_after_first_dashboard_signal_even_when_header_not_present_yet() {
        let now = Date()
        let startedAt = now.addingTimeInterval(-2.0)
        let shouldWait = OpenAIDashboardFetcher.shouldWaitForCreditsHistory(.init(
            now: now,
            anyDashboardSignalAt: startedAt,
            creditsHeaderVisibleAt: nil,
            creditsHeaderPresent: false,
            creditsHeaderInViewport: false,
            didScrollToCredits: false))
        #expect(shouldWait == true)
    }

    @Test
    func stops_waiting_eventually_when_header_never_appears() {
        let now = Date()
        let startedAt = now.addingTimeInterval(-7.0)
        let shouldWait = OpenAIDashboardFetcher.shouldWaitForCreditsHistory(.init(
            now: now,
            anyDashboardSignalAt: startedAt,
            creditsHeaderVisibleAt: nil,
            creditsHeaderPresent: false,
            creditsHeaderInViewport: false,
            didScrollToCredits: false))
        #expect(shouldWait == false)
    }

    @Test
    func usage_breakdown_recovery_waits_briefly_after_chart_classification_error() {
        let now = Date()
        let shouldWait = OpenAIDashboardFetcher.shouldWaitForUsageBreakdownRecovery(.init(
            now: now,
            errorFirstSeenAt: now.addingTimeInterval(-1.0)))
        #expect(shouldWait == true)
    }

    @Test
    func usage_breakdown_recovery_stops_blocking_partial_snapshots() {
        let now = Date()
        let shouldWait = OpenAIDashboardFetcher.shouldWaitForUsageBreakdownRecovery(.init(
            now: now,
            errorFirstSeenAt: now.addingTimeInterval(-5.0)))
        #expect(shouldWait == false)
    }

    @Test
    func probe_waits_briefly_after_reaching_usage_route_without_email_or_dashboard_signals() {
        let now = Date()
        let shouldWait = OpenAIDashboardFetcher.shouldWaitForProbeReadiness(.init(
            now: now,
            usageRouteSeenAt: now.addingTimeInterval(-1.0),
            dashboardSignalSeenAt: nil,
            signedInEmail: nil,
            hasDashboardSignal: false))
        #expect(shouldWait == true)
    }

    @Test
    func probe_waits_briefly_for_email_after_dashboard_signals_appear() {
        let now = Date()
        let shouldWait = OpenAIDashboardFetcher.shouldWaitForProbeReadiness(.init(
            now: now,
            usageRouteSeenAt: now.addingTimeInterval(-3.0),
            dashboardSignalSeenAt: now.addingTimeInterval(-1.0),
            signedInEmail: nil,
            hasDashboardSignal: true))
        #expect(shouldWait == true)
    }

    @Test
    func probe_stops_waiting_once_signed_in_email_is_available() {
        let now = Date()
        let shouldWait = OpenAIDashboardFetcher.shouldWaitForProbeReadiness(.init(
            now: now,
            usageRouteSeenAt: now.addingTimeInterval(-0.2),
            dashboardSignalSeenAt: now.addingTimeInterval(-0.2),
            signedInEmail: "user@example.com",
            hasDashboardSignal: true))
        #expect(shouldWait == false)
    }

    @Test
    func probe_handoff_preserves_page_only_after_confirmed_signed_in_email() {
        let result = OpenAIDashboardFetcher.ProbeResult(
            href: "https://chatgpt.com/codex/cloud/settings/analytics#usage",
            loginRequired: false,
            workspacePicker: false,
            cloudflareInterstitial: false,
            signedInEmail: "user@example.com",
            bodyText: "Credits remaining 42")

        #expect(OpenAIDashboardFetcher.shouldPreserveLoadedPageAfterProbe(result))
    }

    @Test
    func probe_handoff_does_not_preserve_timed_out_usage_page_without_email() {
        let result = OpenAIDashboardFetcher.ProbeResult(
            href: "https://chatgpt.com/codex/cloud/settings/analytics#usage",
            loginRequired: false,
            workspacePicker: false,
            cloudflareInterstitial: false,
            signedInEmail: nil,
            bodyText: "Codex Analytics")

        #expect(!OpenAIDashboardFetcher.shouldPreserveLoadedPageAfterProbe(result))
    }

    @Test
    func probe_grace_restarts_after_route_reload_resets_readiness_timestamps() {
        let now = Date()
        let shouldWait = OpenAIDashboardFetcher.shouldWaitForProbeReadiness(.init(
            now: now,
            usageRouteSeenAt: now,
            dashboardSignalSeenAt: nil,
            signedInEmail: nil,
            hasDashboardSignal: false))
        #expect(shouldWait == true)
    }

    @Test
    func sanitized_timeout_preserves_positive_caller_deadline() {
        #expect(OpenAIDashboardFetcher.sanitizedTimeout(60) == 60)
        #expect(OpenAIDashboardFetcher.sanitizedTimeout(25) == 25)
        #expect(OpenAIDashboardFetcher.sanitizedTimeout(0.5) == 0.5)
    }

    @Test
    func sanitized_timeout_falls_back_for_invalid_values() {
        #expect(OpenAIDashboardFetcher.sanitizedTimeout(0) == 1)
        #expect(OpenAIDashboardFetcher.sanitizedTimeout(-5) == 1)
        #expect(OpenAIDashboardFetcher.sanitizedTimeout(.infinity) == 1)
        #expect(OpenAIDashboardFetcher.sanitizedTimeout(.nan) == 1)
    }

    @Test
    func deadline_starts_at_call_start_and_remaining_timeout_shrinks_from_there() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let deadline = OpenAIDashboardFetcher.deadline(startingAt: start, timeout: 15)

        #expect(deadline.timeIntervalSince(start) == 15)

        let remaining = OpenAIDashboardFetcher.remainingTimeout(
            until: deadline,
            now: start.addingTimeInterval(14.5))
        #expect(remaining == 0.5)
    }

    @Test
    func remaining_timeout_does_not_go_negative() {
        let deadline = Date(timeIntervalSinceReferenceDate: 2000)
        let remaining = OpenAIDashboardFetcher.remainingTimeout(
            until: deadline,
            now: deadline.addingTimeInterval(3))
        #expect(remaining == 0)
    }

    @Test
    func usage_route_matcher_accepts_legacy_settings_route() {
        #expect(OpenAIDashboardFetcher.isUsageRoute("https://chatgpt.com/codex/settings/usage"))
    }

    @Test
    func usage_route_matcher_accepts_cloud_settings_route() {
        #expect(OpenAIDashboardFetcher.isUsageRoute("https://chatgpt.com/codex/cloud/settings/usage"))
    }

    @Test
    func usage_route_matcher_accepts_analytics_route() {
        #expect(OpenAIDashboardFetcher.isUsageRoute("https://chatgpt.com/codex/cloud/settings/analytics"))
    }

    @Test
    func usage_route_matcher_accepts_analytics_usage_hash_route() {
        #expect(OpenAIDashboardFetcher.isUsageRoute("https://chatgpt.com/codex/cloud/settings/analytics#usage"))
    }

    @Test
    func usage_route_matcher_accepts_trailing_slash_variants() {
        #expect(OpenAIDashboardFetcher.isUsageRoute("https://chatgpt.com/codex/settings/usage/"))
        #expect(OpenAIDashboardFetcher.isUsageRoute("https://chatgpt.com/codex/cloud/settings/usage/"))
        #expect(OpenAIDashboardFetcher.isUsageRoute("https://chatgpt.com/codex/cloud/settings/analytics/"))
    }

    @Test
    func usage_route_matcher_rejects_unrelated_routes() {
        #expect(!OpenAIDashboardFetcher.isUsageRoute("https://chatgpt.com/"))
        #expect(!OpenAIDashboardFetcher.isUsageRoute("https://chatgpt.com/codex"))
        #expect(!OpenAIDashboardFetcher.isUsageRoute(nil))
    }

    @Test(arguments: [
        ("https://chatgpt.com/#usage", true, false, false, false),
        ("https://chatgpt.com/", false, false, true, false),
        ("https://chatgpt.com/", false, false, false, true)
    ])
    func usage_route_reload_skips_blocking_states(
        href: String,
        loginRequired: Bool,
        workspacePicker: Bool,
        cloudflareInterstitial: Bool,
        expected: Bool)
    {
        #expect(OpenAIDashboardFetcher.shouldReloadUsageRoute(
            href: href,
            loginRequired: loginRequired,
            workspacePicker: workspacePicker,
            cloudflareInterstitial: cloudflareInterstitial) == expected)
    }

    @Test
    func dashboard_requests_prefer_English_localization() throws {
        let url = try #require(URL(string: "https://chatgpt.com/codex/cloud/settings/analytics#usage"))
        let request = OpenAIDashboardFetcher.usageURLRequest(url: url)
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en-US,en;q=0.9")
    }

    @Test
    func usage_api_request_carries_cookies_and_English_localization() {
        let request = OpenAIDashboardFetcher.dashboardUsageAPIRequest(cookieHeader: "a=b")
        #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "a=b")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en-US,en;q=0.9")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test
    func identity_api_request_carries_cookies_and_English_localization() throws {
        let url = try #require(URL(string: "https://chatgpt.com/backend-api/me"))
        let request = OpenAIDashboardFetcher.dashboardIdentityAPIRequest(url: url, cookieHeader: "a=b")

        #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/me")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "a=b")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en-US,en;q=0.9")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test
    func dashboard_api_requests_accept_shared_deadline_timeout_clamps() throws {
        let url = try #require(URL(string: "https://chatgpt.com/backend-api/me"))
        let usageRequest = OpenAIDashboardFetcher.dashboardUsageAPIRequest(
            cookieHeader: "a=b",
            timeout: 1.25)
        let identityRequest = OpenAIDashboardFetcher.dashboardIdentityAPIRequest(
            url: url,
            cookieHeader: "a=b",
            timeout: 0.75)

        #expect(usageRequest.timeoutInterval == 1.25)
        #expect(identityRequest.timeoutInterval == 0.75)
    }

    @Test
    func usage_api_data_maps_language_independent_rate_limits_and_credits() throws {
        let json = """
        {
          "plan_type": "pro",
          "rate_limit": {
            "primary_window": {
              "used_percent": 12,
              "reset_at": 1700003600,
              "limit_window_seconds": 18000
            },
            "secondary_window": {
              "used_percent": 34,
              "reset_at": 1700604800,
              "limit_window_seconds": 604800
            }
          },
          "credits": {
            "has_credits": true,
            "unlimited": false,
            "balance": 42.5
          }
        }
        """
        let response = try CodexOAuthUsageFetcher._decodeUsageResponseForTesting(Data(json.utf8))
        let data = OpenAIDashboardFetcher.dashboardAPIData(from: response)

        #expect(data.primaryLimit?.usedPercent == 12)
        #expect(data.primaryLimit?.windowMinutes == 300)
        #expect(data.secondaryLimit?.usedPercent == 34)
        #expect(data.secondaryLimit?.windowMinutes == 10080)
        #expect(data.creditsRemaining == 42.5)
        #expect(data.accountPlan == "pro")
        #expect(data.hasUsageData)
    }

    @Test
    func find_first_email_searches_nested_api_payloads() {
        let json = """
        {
          "accounts": [
            { "profile": { "name": "Test" } },
            { "profile": { "email": "nested@example.com" } }
          ]
        }
        """

        #expect(OpenAIDashboardFetcher.findFirstEmail(inJSONData: Data(json.utf8)) == "nested@example.com")
    }
}
