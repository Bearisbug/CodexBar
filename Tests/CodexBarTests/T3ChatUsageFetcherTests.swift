import Foundation
import Testing
@testable import CodexBarCore

struct T3ChatUsageFetcherTests {
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

    private static let now = Date(timeIntervalSince1970: 1_778_000_000)
    // 2026-05-21T12:23:36Z, the usage-window reset that must not drive overage reset display.
    private static let billingNextResetMilliseconds = 1_779_366_216_920
    // 2026-06-06T16:23:29Z, the subscription period end used for overage reset display.
    private static let subscriptionPeriodEndSeconds = 1_780_763_009
    private static let subscriptionPeriodEndMilliseconds = Self.subscriptionPeriodEndSeconds * 1000

    private static let sampleResponse = [
        #"{"json":{"0":[[0],[null,0,0]]}}"#,
        #"{"json":[0,0,[[{"result":0}],["result",0,1]]]}"#,
        #"{"json":[1,0,[[{"data":0}],["data",0,2]]]}"#,
        #"{"json":[2,0,[[{"subTier":"pro","subscription":{"# +
            #""productId":"pro","productName":"pro","status":"active","# +
            #""currentPeriodStart":1778084609000,"currentPeriodEnd":1780763009000,"# +
            #""canceledAt":null,"trialEndsAt":null},"lifetimeBalance":0,"usageBand":"max","# +
            #""billingNextResetAt":1779366216920,"usageFourHourPercentage":12.5,"# +
            #""usageMonthPercentage":34.25,"usageFourHourNextResetAt":1779366216920,"# +
            #""usagePeriodPercentage":44,"usageWindowNextResetAt":1779366216920}]]]}"#,
    ].joined(separator: "\n")

    @Test
    func parses_customer_data_from_json_lines_response() throws {
        let snapshot = try T3ChatUsageParser.parseJSONLines(Self.sampleResponse, now: Self.now)

        #expect(snapshot.customerData.subTier == "pro")
        #expect(snapshot.customerData.usageBand == "max")
        #expect(snapshot.customerData.usageFourHourPercentage == 12.5)
        #expect(snapshot.customerData.usageMonthPercentage == 34.25)
        #expect(snapshot.customerData.subscription?.status == "active")
    }

    @Test
    func maps_customer_data_to_base_and_overage_windows() throws {
        let usage = try T3ChatUsageParser.parseJSONLines(Self.sampleResponse, now: Self.now)
            .toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 12.5)
        #expect(usage.primary?.windowMinutes == 240)
        #expect(usage.primary?.resetDescription == "Base - max")
        #expect(usage.secondary?.usedPercent == 34.25)
        #expect(usage.secondary?.resetDescription == "Overage")
        #expect(usage.secondary?.resetsAt.map { Int($0.timeIntervalSince1970) } == Self.subscriptionPeriodEndSeconds)
        #expect(usage.identity?.providerID == .t3chat)
        #expect(usage.identity?.loginMethod == "Pro")
    }

    @Test
    func falls_back_to_usage_period_percentage_when_month_percentage_is_absent() throws {
        let response = """
        {"json":[2,0,[[{"subTier":"free","usageFourHourPercentage":5,"usagePeriodPercentage":65}]]]}
        """
        let usage = try T3ChatUsageParser.parseJSONLines(response, now: Self.now)
            .toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 5)
        #expect(usage.secondary?.usedPercent == 65)
    }

    @Test
    func overage_reset_ignores_billing_next_reset() throws {
        let response = Self.customerDataResponse(
            #"{"usageMonthPercentage":20,"billingNextResetAt":\#(Self.billingNextResetMilliseconds)}"#)
        let usage = try T3ChatUsageParser.parseJSONLines(response, now: Self.now)
            .toUsageSnapshot()

        #expect(usage.secondary?.usedPercent == 20)
        #expect(usage.secondary?.resetsAt == nil)
    }

    @Test
    func overage_reset_uses_subscription_current_period_end() throws {
        let currentPeriodEnd = Self.subscriptionPeriodEndMilliseconds
        let response = Self.customerDataResponse(
            #"{"usageMonthPercentage":20,"subscription":{"currentPeriodEnd":\#(currentPeriodEnd)}}"#)
        let usage = try T3ChatUsageParser.parseJSONLines(response, now: Self.now)
            .toUsageSnapshot()

        #expect(usage.secondary?.usedPercent == 20)
        #expect(usage.secondary?.resetsAt.map { Int($0.timeIntervalSince1970) } == Self.subscriptionPeriodEndSeconds)
    }

    @Test
    func fetch_sends_trpc_headers_and_cookie() async throws {
        let stub = ProviderHTTPTransportStub { request in
            #expect(request.url?.host == "t3.chat")
            #expect(request.url?.path == "/api/trpc/getCustomerData")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "session=abc")
            #expect(request.value(forHTTPHeaderField: "trpc-accept") == "application/jsonl")
            #expect(request.value(forHTTPHeaderField: "x-trpc-source") == "web-client")
            #expect(request.value(forHTTPHeaderField: "Sec-Fetch-Site") == "same-origin")
            #expect(request.url?.query?.contains("batch=1") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil)!
            return (Data(Self.sampleResponse.utf8), response)
        }

        let snapshot = try await T3ChatUsageFetcher.fetchCustomerData(
            cookieHeader: "session=abc",
            now: Self.now,
            transport: stub)

        #expect(snapshot.customerData.planName == "Pro")
    }

    @Test
    func full_curl_capture_forwards_browser_fingerprint_headers() async throws {
        let curl = """
        curl 'https://t3.chat/api/trpc/getCustomerData?batch=1&input=ignored' \\
          -H 'User-Agent: Mozilla/5.0 Firefox/151.0' \\
          --header "Referer: https://t3.chat/settings/customization" \\
          -H 'trpc-accept: application/jsonl' \\
          -H 'x-trpc-source: web-client' \\
          -H 'x-trpc-batch: true' \\
          -H 'X-Deployment-Id: dpl_test' \\
          -H 'x-client-context: eyJjbGllbnQiOnsidmVyc2lvbiI6IjEuMTIuNCJ9fQ==' \\
          -H 'Cookie: session=abc'
        """
        let stub = ProviderHTTPTransportStub { request in
            #expect(request.value(forHTTPHeaderField: "Cookie") == "session=abc")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "Mozilla/5.0 Firefox/151.0")
            #expect(request.value(forHTTPHeaderField: "Referer") == "https://t3.chat/settings/customization")
            #expect(request.value(forHTTPHeaderField: "X-Deployment-Id") == "dpl_test")
            #expect(request.value(forHTTPHeaderField: "x-client-context") ==
                "eyJjbGllbnQiOnsidmVyc2lvbiI6IjEuMTIuNCJ9fQ==")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil)!
            return (Data(Self.sampleResponse.utf8), response)
        }

        let fetcher = T3ChatUsageFetcher(browserDetection: BrowserDetection(cacheTTL: 0))
        _ = try await fetcher.fetch(
            cookieHeaderOverride: curl,
            now: Self.now,
            transport: stub)
    }

    @Test
    func curl_capture_forwards_ansi_quoted_and_equals_header_forms() async throws {
        let curl = """
        curl 'https://t3.chat/api/trpc/getCustomerData?batch=1&input=ignored' \\
          --header=$'User-Agent: Browser\\'s Agent' \\
          --header 'X-Deployment-Id: dpl_test' \\
          -H 'Cookie: session=abc'
        """
        let stub = ProviderHTTPTransportStub { request in
            #expect(request.value(forHTTPHeaderField: "Cookie") == "session=abc")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "Browser's Agent")
            #expect(request.value(forHTTPHeaderField: "X-Deployment-Id") == "dpl_test")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil)!
            return (Data(Self.sampleResponse.utf8), response)
        }

        let fetcher = T3ChatUsageFetcher(browserDetection: BrowserDetection(cacheTTL: 0))
        _ = try await fetcher.fetch(
            cookieHeaderOverride: curl,
            now: Self.now,
            transport: stub)
    }

    @Test
    func full_curl_capture_extracts_cookie_from_long_header_form() async throws {
        let curl = """
        curl 'https://t3.chat/api/trpc/getCustomerData?batch=1&input=ignored' \\
          --compressed \\
          --header "Referer: https://t3.chat/settings/customization" \\
          --header "Cookie: session=abc; cf_clearance=token" \\
          --header "X-Deployment-Id: dpl_test"
        """
        let stub = ProviderHTTPTransportStub { request in
            #expect(request.value(forHTTPHeaderField: "Cookie") == "session=abc; cf_clearance=token")
            #expect(request.value(forHTTPHeaderField: "Referer") == "https://t3.chat/settings/customization")
            #expect(request.value(forHTTPHeaderField: "X-Deployment-Id") == "dpl_test")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil)!
            return (Data(Self.sampleResponse.utf8), response)
        }

        let fetcher = T3ChatUsageFetcher(browserDetection: BrowserDetection(cacheTTL: 0))
        _ = try await fetcher.fetch(
            cookieHeaderOverride: curl,
            now: Self.now,
            transport: stub)
    }

    @Test
    func manual_strategy_accepts_full_curl_capture() async {
        let curl = """
        curl 'https://t3.chat/api/trpc/getCustomerData?batch=1&input=ignored' \\
          --header "Referer: https://t3.chat/settings/customization" \\
          --header "Cookie: session=abc; cf_clearance=token" \\
          --header "X-Deployment-Id: dpl_test"
        """
        let settings = ProviderSettingsSnapshot.make(
            t3chat: ProviderSettingsSnapshot.T3ChatProviderSettings(
                cookieSource: .manual,
                manualCookieHeader: curl))

        #expect(await T3ChatWebFetchStrategy().isAvailable(Self.makeContext(settings: settings)))
    }

    @Test
    func unauthorized_response_is_invalid_credentials() async throws {
        let stub = ProviderHTTPTransportStub { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil)!
            return (Data("unauthorized".utf8), response)
        }

        do {
            _ = try await T3ChatUsageFetcher.fetchCustomerData(
                cookieHeader: "session=abc",
                now: Self.now,
                transport: stub)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case T3ChatUsageError.invalidCredentials = error else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func vercel_challenge_response_asks_for_full_curl_capture() async throws {
        let stub = ProviderHTTPTransportStub { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["x-vercel-mitigated": "challenge"])!
            return (Data("checkpoint".utf8), response)
        }

        do {
            _ = try await T3ChatUsageFetcher.fetchCustomerData(
                cookieHeader: "session=abc",
                now: Self.now,
                transport: stub)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case T3ChatUsageError.vercelChallenge = error else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    private static func customerDataResponse(_ customerDataJSON: String) -> String {
        #"{"json":[2,0,[[\#(customerDataJSON)]]]}"# + "\n"
    }

    private static func makeContext(settings: ProviderSettingsSnapshot) -> ProviderFetchContext {
        ProviderFetchContext(
            runtime: .app,
            sourceMode: .auto,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: [:],
            settings: settings,
            fetcher: UsageFetcher(environment: [:]),
            claudeFetcher: StubClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0))
    }
}
