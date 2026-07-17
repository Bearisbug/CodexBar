import Foundation
import Testing
@testable import CodexBarCore

struct DoubaoUsageSnapshotTests {
    @Test
    func normal_usage_with_both_headers_present_and_non_empty_reports_correct_percent() {
        let snapshot = DoubaoUsageSnapshot(
            remainingRequests: 750,
            limitRequests: 1000,
            resetTime: nil,
            updatedAt: Date(),
            apiKeyValid: true)
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.usedPercent == 25)
        #expect(usage.primary?.resetDescription == "250/1000 requests")
    }

    @Test
    func boundary_normal_usage_at_near_full_reports_correct_percent() {
        let snapshot = DoubaoUsageSnapshot(
            remainingRequests: 1,
            limitRequests: 1000,
            resetTime: nil,
            updatedAt: Date(),
            apiKeyValid: true)
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.usedPercent == 99.9)
        #expect(usage.primary?.resetDescription == "999/1000 requests")
    }

    @Test
    func unreliable_headers_omit_the_request_limit_window() {
        let snapshot = DoubaoUsageSnapshot(
            remainingRequests: 0,
            limitRequests: 1000,
            resetTime: nil,
            updatedAt: Date(),
            apiKeyValid: true,
            requestLimitsReliable: false)
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary == nil)
        #expect(usage.rateLimitsUnavailable(for: .doubao))
    }

    @Test
    func explicit_rate_limit_with_zero_remaining_reports_exhausted_quota() {
        let snapshot = DoubaoUsageSnapshot(
            remainingRequests: 0,
            limitRequests: 1000,
            resetTime: nil,
            updatedAt: Date(),
            apiKeyValid: true)
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.usedPercent == 100)
        #expect(usage.primary?.resetDescription == "1000/1000 requests")
    }

    @Test
    func both_headers_missing_but_key_valid_omit_the_request_limit_window() {
        let snapshot = DoubaoUsageSnapshot(
            remainingRequests: 0,
            limitRequests: 0,
            resetTime: nil,
            updatedAt: Date(),
            apiKeyValid: true)
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary == nil)
        #expect(usage.rateLimitsUnavailable(for: .doubao))
    }

    @Test
    func invalid_key_with_no_headers_reports_No_usage_data() {
        let snapshot = DoubaoUsageSnapshot(
            remainingRequests: 0,
            limitRequests: 0,
            resetTime: nil,
            updatedAt: Date(),
            apiKeyValid: false)
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.usedPercent == 0)
        #expect(usage.primary?.resetDescription == "No usage data")
    }

    @Test
    func provider_identity_is_correctly_tagged_as_doubao() {
        let snapshot = DoubaoUsageSnapshot(
            remainingRequests: 500,
            limitRequests: 1000,
            resetTime: nil,
            updatedAt: Date(),
            apiKeyValid: true)
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.identity?.providerID == .doubao)
        #expect(usage.identity?.accountEmail == nil)
    }
}

struct DoubaoUsageFetcherTests {
    @Test
    func coding_plan_response_maps_session_weekly_and_monthly_windows() throws {
        let data = Data(
            """
            {
              "ResponseMetadata": {
                "Action": "GetCodingPlanUsage",
                "Version": "2024-01-01",
                "Service": "ark",
                "Region": "cn-beijing"
              },
              "Result": {
                "Status": "Running",
                "UpdateTimestamp": 1782226444,
                "QuotaUsage": [
                  {"Level":"session","Percent":0.116,"ResetTimestamp":1782226478},
                  {"Level":"weekly","Percent":3.182143,"ResetTimestamp":1782662400},
                  {"Level":"monthly","Percent":7.5730535,"ResetTimestamp":1782403199}
                ]
              }
            }
            """.utf8)

        let usage = try DoubaoUsageFetcher.decodeCodingPlanUsage(from: data).toUsageSnapshot(
            updatedAt: Date(timeIntervalSince1970: 0))

        #expect(usage.primary?.usedPercent == 0.116)
        #expect(usage.primary?.windowMinutes == 300)
        #expect(usage.primary?.resetsAt == Date(timeIntervalSince1970: 1_782_226_478))
        #expect(usage.primary?.resetDescription == nil)
        #expect(usage.secondary?.usedPercent == 3.182143)
        #expect(usage.secondary?.windowMinutes == 10080)
        #expect(usage.tertiary?.usedPercent == 7.5730535)
        #expect(usage.tertiary?.windowMinutes == 43200)
        #expect(usage.identity?.providerID == .doubao)
        #expect(usage.identity?.loginMethod == "Running")
    }

    @Test
    func coding_plan_response_ignores_missing_reset_sentinels() throws {
        let fallbackUpdatedAt = Date(timeIntervalSince1970: 42)
        let data = Data(
            """
            {
              "Result": {
                "Status": "Running",
                "UpdateTimestamp": 0,
                "QuotaUsage": [
                  {"Level":"session","Percent":12.5,"ResetTimestamp":0},
                  {"Level":"weekly","Percent":24,"ResetTimestamp":-1}
                ]
              }
            }
            """.utf8)

        let usage = try DoubaoUsageFetcher.decodeCodingPlanUsage(from: data).toUsageSnapshot(
            updatedAt: fallbackUpdatedAt)

        #expect(usage.updatedAt == fallbackUpdatedAt)
        #expect(usage.primary?.usedPercent == 12.5)
        #expect(usage.primary?.resetsAt == nil)
        #expect(usage.primary?.resetDescription == nil)
        #expect(usage.secondary?.usedPercent == 24)
        #expect(usage.secondary?.resetsAt == nil)
        #expect(usage.secondary?.resetDescription == nil)
    }

    @Test
    func coding_plan_fetch_signs_volcengine_request() async throws {
        let transport = DoubaoScriptedTransport(results: [
            .rawResponse(
                statusCode: 200,
                body: """
                {
                  "Result": {
                    "Status": "Running",
                    "UpdateTimestamp": 1782226444,
                    "QuotaUsage": [
                      {"Level":"session","Percent":12.5,"ResetTimestamp":1782226478}
                    ]
                  }
                }
                """),
        ])
        let credentials = DoubaoCodingPlanCredentials(
            accessKeyID: "AKLTTEST",
            secretAccessKey: "secret",
            region: "cn-beijing")
        let date = Date(timeIntervalSince1970: 1_781_654_400)

        let snapshot = try await DoubaoUsageFetcher.fetchCodingPlanUsage(
            credentials: credentials,
            session: transport,
            date: date)
        let request = await transport.lastCapturedRequest()

        #expect(snapshot.toUsageSnapshot().primary?.usedPercent == 12.5)
        #expect(request?.method == "POST")
        #expect(request?.url == "https://open.volcengineapi.com/?Action=GetCodingPlanUsage&Version=2024-01-01")
        #expect(request?.host == "open.volcengineapi.com")
        #expect(request?.date == "20260617T000000Z")
        #expect(request?.contentSHA256 ==
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(request?.authorization?.contains(
            "HMAC-SHA256 Credential=AKLTTEST/20260617/cn-beijing/ark/request") == true)
        #expect(request?.authorization?.contains(
            "SignedHeaders=content-type;host;x-content-sha256;x-date") == true)
    }

    @Test
    func coding_plan_fetch_surfaces_volcengine_access_denied_error() async {
        let transport = DoubaoScriptedTransport(results: [
            .rawResponse(
                statusCode: 403,
                body: """
                {
                  "ResponseMetadata": {
                    "Action": "GetCodingPlanUsage",
                    "Error": {
                      "CodeN": 100013,
                      "Code": "AccessDenied",
                      "Message": "User is not authorized to perform: ark:GetCodingPlanUsage"
                    }
                  }
                }
                """),
        ])
        let credentials = DoubaoCodingPlanCredentials(
            accessKeyID: "AKLTTEST",
            secretAccessKey: "secret",
            region: "cn-beijing")

        do {
            _ = try await DoubaoUsageFetcher.fetchCodingPlanUsage(
                credentials: credentials,
                session: transport,
                date: Date(timeIntervalSince1970: 1_781_654_400))
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case let DoubaoUsageError.apiError(code, message) = error else { return false }
                return code == 403
                    && message.contains("AccessDenied")
                    && message.contains("ark:GetCodingPlanUsage")
                    && !message.contains("bytes")
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func repeated_successful_zero_remaining_responses_omit_unknown_request_limit() async throws {
        let transport = DoubaoScriptedTransport(results: [
            .response(statusCode: 200, limit: 1000, remaining: 0),
            .response(statusCode: 200, limit: 1000, remaining: 0),
        ])

        let snapshot = try await DoubaoUsageFetcher.fetchUsage(apiKey: "test-key", session: transport)
        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary == nil)
        #expect(usage.rateLimitsUnavailable(for: .doubao))
        #expect(await transport.requestCount() == 2)
    }

    @Test
    func successful_final_request_followed_by_rate_limit_reports_exhausted_quota() async throws {
        let transport = DoubaoScriptedTransport(results: [
            .response(statusCode: 200, limit: 1000, remaining: 0),
            .response(statusCode: 429, limit: 1000, remaining: 0),
        ])

        let snapshot = try await DoubaoUsageFetcher.fetchUsage(apiKey: "test-key", session: transport)
        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 100)
        #expect(usage.primary?.resetDescription == "1000/1000 requests")
        #expect(await transport.requestCount() == 2)
    }

    @Test
    func headerless_rate_limit_confirmation_preserves_exhausted_quota() async throws {
        let transport = DoubaoScriptedTransport(results: [
            .response(statusCode: 200, limit: 1000, remaining: 0),
            .response(statusCode: 429, limit: nil, remaining: nil),
        ])

        let snapshot = try await DoubaoUsageFetcher.fetchUsage(apiKey: "test-key", session: transport)
        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 100)
        #expect(usage.primary?.resetDescription == "1000/1000 requests")
        #expect(await transport.requestCount() == 2)
    }

    @Test
    func rate_limit_with_request_limit_header_reports_exhausted_quota() async throws {
        let transport = DoubaoScriptedTransport(results: [
            .response(statusCode: 429, limit: 1000, remaining: nil),
        ])

        let snapshot = try await DoubaoUsageFetcher.fetchUsage(apiKey: "test-key", session: transport)
        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 100)
        #expect(usage.primary?.resetDescription == "1000/1000 requests")
        #expect(await transport.requestCount() == 1)
    }

    @Test
    func bare_rate_limit_omits_unknown_request_limit() async throws {
        let transport = DoubaoScriptedTransport(results: [
            .response(statusCode: 429, limit: nil, remaining: nil),
        ])

        let snapshot = try await DoubaoUsageFetcher.fetchUsage(apiKey: "test-key", session: transport)
        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary == nil)
        #expect(usage.rateLimitsUnavailable(for: .doubao))
        #expect(await transport.requestCount() == 1)
    }

    @Test
    func failed_zero_remaining_confirmation_preserves_exhausted_quota() async throws {
        let transport = DoubaoScriptedTransport(results: [
            .response(statusCode: 200, limit: 1000, remaining: 0),
            .failure(URLError(.timedOut)),
        ])

        let snapshot = try await DoubaoUsageFetcher.fetchUsage(apiKey: "test-key", session: transport)
        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 100)
        #expect(usage.primary?.resetDescription == "1000/1000 requests")
        #expect(await transport.requestCount() == 2)
    }

    @Test
    func task_cancellation_during_confirmation_propagates() async {
        let transport = DoubaoScriptedTransport(results: [
            .response(statusCode: 200, limit: 1000, remaining: 0),
            .cancellation,
        ])

        await #expect(throws: CancellationError.self) {
            _ = try await DoubaoUsageFetcher.fetchUsage(apiKey: "test-key", session: transport)
        }
        #expect(await transport.requestCount() == 2)
    }

    @Test
    func url_cancellation_during_confirmation_propagates() async {
        let transport = DoubaoScriptedTransport(results: [
            .response(statusCode: 200, limit: 1000, remaining: 0),
            .failure(URLError(.cancelled)),
        ])

        do {
            _ = try await DoubaoUsageFetcher.fetchUsage(apiKey: "test-key", session: transport)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                (error as? URLError)?.code == .cancelled
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
        #expect(await transport.requestCount() == 2)
    }
}

private actor DoubaoScriptedTransport: ProviderHTTPTransport {
    enum Result {
        case response(statusCode: Int, limit: Int?, remaining: Int?)
        case rawResponse(statusCode: Int, body: String)
        case failure(URLError)
        case cancellation
    }

    struct CapturedRequest {
        let url: String?
        let method: String?
        let host: String?
        let date: String?
        let contentSHA256: String?
        let authorization: String?
    }

    private var results: [Result]
    private var requests = 0
    private var capturedRequest: CapturedRequest?

    init(results: [Result]) {
        self.results = results
    }

    func requestCount() -> Int {
        self.requests
    }

    func lastCapturedRequest() -> CapturedRequest? {
        self.capturedRequest
    }

    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        self.requests += 1
        self.capturedRequest = CapturedRequest(
            url: request.url?.absoluteString,
            method: request.httpMethod,
            host: request.value(forHTTPHeaderField: "Host"),
            date: request.value(forHTTPHeaderField: "X-Date"),
            contentSHA256: request.value(forHTTPHeaderField: "X-Content-Sha256"),
            authorization: request.value(forHTTPHeaderField: "Authorization"))
        let result = self.results.removeFirst()
        switch result {
        case let .response(statusCode, limit, remaining):
            var headers: [String: String] = [:]
            if let limit {
                headers["x-ratelimit-limit-requests"] = String(limit)
            }
            if let remaining {
                headers["x-ratelimit-remaining-requests"] = String(remaining)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers)!
            return (Data(#"{"usage":{"total_tokens":1}}"#.utf8), response)
        case let .rawResponse(statusCode, body):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: [:])!
            return (Data(body.utf8), response)
        case let .failure(error):
            throw error
        case .cancellation:
            throw CancellationError()
        }
    }
}
