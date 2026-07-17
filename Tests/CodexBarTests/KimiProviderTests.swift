import Foundation
import Testing
@testable import CodexBarCore

private struct KimiStubClaudeFetcher: ClaudeUsageFetching {
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

private func makeKimiFetchContext(
    sourceMode: ProviderSourceMode,
    environment: [String: String] = [:]) -> ProviderFetchContext
{
    let env = environment
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
        claudeFetcher: KimiStubClaudeFetcher(),
        browserDetection: BrowserDetection(cacheTTL: 0))
}

private func makeTemporaryKimiCodeHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexBar-KimiCode-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: home,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
    return home
}

private func writeKimiCodeCredential(
    home: URL,
    accessToken: String,
    refreshToken: String = "refresh",
    expiresAt: Any?) throws -> URL
{
    let credentials = home.appendingPathComponent("credentials", isDirectory: true)
    try FileManager.default.createDirectory(at: credentials, withIntermediateDirectories: true)
    var payload: [String: Any] = [
        "access_token": accessToken,
        "refresh_token": refreshToken,
    ]
    if let expiresAt {
        payload["expires_at"] = expiresAt
    }
    let url = credentials.appendingPathComponent("kimi-code.json")
    try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    return url
}

private actor KimiOrderedCredentialTransport: ProviderHTTPTransport {
    private var headers: [String] = []

    func authorizationHeaders() -> [String] {
        self.headers
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
        self.headers.append(authorization)
        let statusCode: Int
        let body: String
        switch authorization {
        case "Bearer api-bad":
            statusCode = 401
            body = #"{"error":"unauthorized"}"#
        case "Bearer cli-ok":
            statusCode = 200
            body = #"{"usage":{"limit":"100","used":"25","remaining":"75"},"limits":[]}"#
        default:
            throw URLError(.userAuthenticationRequired)
        }
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]))
        return (Data(body.utf8), response)
    }
}

struct KimiSettingsReaderTests {
    @Test
    func reads_token_from_environment_variable() {
        let env = ["KIMI_AUTH_TOKEN": "test.jwt.token"]
        let token = KimiSettingsReader.authToken(environment: env)
        #expect(token == "test.jwt.token")
    }

    @Test
    func reads_API_key_from_preferred_environment_variable() {
        let env = ["KIMI_CODE_API_KEY": "kimi-code-token"]
        let token = KimiSettingsReader.apiKey(environment: env)
        #expect(token == "kimi-code-token")
    }

    @Test
    func does_not_consume_generic_Kimi_K2_API_key_environment_variable() {
        let env = ["KIMI_API_KEY": "'kimi-api-token'"]
        let token = KimiSettingsReader.apiKey(environment: env)
        #expect(token == nil)
    }

    @Test
    func uses_code_specific_API_key_when_generic_Kimi_K2_key_also_exists() {
        let env = [
            "KIMI_API_KEY": "generic-kimi-token",
            "KIMI_CODE_API_KEY": "kimi-code-token",
        ]
        let token = KimiSettingsReader.apiKey(environment: env)
        #expect(token == "kimi-code-token")
    }

    @Test
    func reuses_fresh_CLI_credential_without_modifying_it() throws {
        let home = try makeTemporaryKimiCodeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let credentialURL = try writeKimiCodeCredential(
            home: home,
            accessToken: "oauth",
            expiresAt: now.addingTimeInterval(3600).timeIntervalSince1970)
        let originalData = try Data(contentsOf: credentialURL)
        let originalModificationDate = try #require(
            FileManager.default.attributesOfItem(atPath: credentialURL.path)[.modificationDate] as? Date)
        let environment = ["KIMI_CODE_HOME": home.path]

        let token = KimiSettingsReader.kimiCodeAccessToken(environment: environment, now: now)
        let headers = KimiSettingsReader.kimiCodeIdentityHeaders(environment: environment)

        #expect(token == "oauth")
        #expect(headers["X-Msh-Platform"] == "kimi_code_cli")
        #expect(headers["X-Msh-Device-Id"]?.isEmpty == false)
        #expect(try Data(contentsOf: credentialURL) == originalData)
        let finalModificationDate = try #require(
            FileManager.default.attributesOfItem(atPath: credentialURL.path)[.modificationDate] as? Date)
        #expect(finalModificationDate == originalModificationDate)

        let deviceURL = home.appendingPathComponent("device_id")
        let permissions = try #require(
            FileManager.default.attributesOfItem(atPath: deviceURL.path)[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o600)
    }

    @Test
    func rejects_expired_or_missing_expiry_CLI_credentials() throws {
        let now = Date()
        for expiresAt: Any? in [now.addingTimeInterval(30).timeIntervalSince1970, nil, "not-a-time"] {
            let home = try makeTemporaryKimiCodeHome()
            defer { try? FileManager.default.removeItem(at: home) }
            _ = try writeKimiCodeCredential(
                home: home,
                accessToken: "oauth",
                expiresAt: expiresAt)
            let environment = ["KIMI_CODE_HOME": home.path]

            #expect(KimiSettingsReader.hasKimiCodeCredential(environment: environment))
            #expect(KimiSettingsReader.kimiCodeAccessToken(environment: environment, now: now) == nil)
        }
    }

    @Test
    func keeps_explicit_key_separate_and_isolates_CLI_credential_from_endpoint_overrides() throws {
        let home = try makeTemporaryKimiCodeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try writeKimiCodeCredential(
            home: home,
            accessToken: "oauth",
            expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970)

        let explicit = ProviderTokenResolver.kimiAPIResolution(environment: [
            "KIMI_CODE_API_KEY": "explicit",
            "KIMI_CODE_HOME": home.path,
        ])
        #expect(explicit?.token == "explicit")
        #expect(explicit?.source == .environment)
        #expect(KimiSettingsReader.kimiCodeAccessToken(environment: [
            "KIMI_CODE_API_KEY": "explicit",
            "KIMI_CODE_HOME": home.path,
        ]) == "oauth")

        for key in ["KIMI_CODE_BASE_URL", "KIMI_CODE_OAUTH_HOST", "KIMI_OAUTH_HOST"] {
            let environment = [
                "KIMI_CODE_HOME": home.path,
                key: "https://proxy.example.com",
            ]
            #expect(KimiSettingsReader.hasKimiCodeCredential(environment: environment) == false)
            #expect(ProviderTokenResolver.kimiAPIResolution(environment: environment) == nil)
        }
    }

    @Test
    func uses_default_code_API_base_URL_when_override_is_absent() throws {
        let url = try KimiSettingsReader.codeAPIBaseURL(environment: [:])
        #expect(url == KimiSettingsReader.defaultCodeAPIBaseURL)
    }

    @Test
    func uses_custom_code_API_base_URL_when_valid() throws {
        let env = ["KIMI_CODE_BASE_URL": "https://proxy.example.com/kimi"]
        let url = try KimiSettingsReader.codeAPIBaseURL(environment: env)
        #expect(url.absoluteString == "https://proxy.example.com/kimi")
    }

    @Test
    func rejects_invalid_code_API_base_URL() {
        let env = ["KIMI_CODE_BASE_URL": "not a url"]

        #expect(throws: KimiAPIError.invalidRequest(
            "Kimi Code API base URL must use HTTPS without user info"))
        {
            try KimiSettingsReader.codeAPIBaseURL(environment: env)
        }
    }

    @Test
    func rejects_insecure_code_API_base_URL() {
        let env = ["KIMI_CODE_BASE_URL": "http://proxy.example.com/kimi"]

        #expect(throws: KimiAPIError.invalidRequest(
            "Kimi Code API base URL must use HTTPS without user info"))
        {
            try KimiSettingsReader.codeAPIBaseURL(environment: env)
        }
    }

    @Test
    func rejects_code_API_base_URL_containing_user_info() {
        let env = ["KIMI_CODE_BASE_URL": "https://api.kimi.com@proxy.example.com/kimi"]

        #expect(throws: KimiAPIError.invalidRequest(
            "Kimi Code API base URL must use HTTPS without user info"))
        {
            try KimiSettingsReader.codeAPIBaseURL(environment: env)
        }
    }

    @Test
    func normalizes_quoted_token() {
        let env = ["KIMI_AUTH_TOKEN": "\"test.jwt.token\""]
        let token = KimiSettingsReader.authToken(environment: env)
        #expect(token == "test.jwt.token")
    }

    @Test
    func returns_nil_when_missing() {
        let env: [String: String] = [:]
        let token = KimiSettingsReader.authToken(environment: env)
        #expect(token == nil)
    }

    @Test
    func returns_nil_when_empty() {
        let env = ["KIMI_AUTH_TOKEN": ""]
        let token = KimiSettingsReader.authToken(environment: env)
        #expect(token == nil)
    }

    @Test
    func normalizes_lowercase_environment_key() {
        let env = ["kimi_auth_token": "test.jwt.token"]
        let token = KimiSettingsReader.authToken(environment: env)
        #expect(token == "test.jwt.token")
    }
}

struct KimiAPIFetchStrategyTests {
    @Test
    func auto_mode_accepts_CLI_credential_and_reports_expired_remediation() async throws {
        let home = try makeTemporaryKimiCodeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try writeKimiCodeCredential(
            home: home,
            accessToken: "expired",
            expiresAt: Date().addingTimeInterval(-60).timeIntervalSince1970)
        let strategy = KimiCLICredentialFetchStrategy()
        let context = makeKimiFetchContext(
            sourceMode: .auto,
            environment: ["KIMI_CODE_HOME": home.path])

        #expect(await strategy.isAvailable(context))
        await #expect(throws: KimiAPIError.expiredCodeCredential) {
            try await strategy.fetch(context)
        }
        #expect(strategy.shouldFallback(on: KimiAPIError.expiredCodeCredential, context: context))
    }

    @Test
    func explicit_API_mode_ignores_fresh_CLI_credential() async throws {
        let home = try makeTemporaryKimiCodeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try writeKimiCodeCredential(
            home: home,
            accessToken: "oauth",
            expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970)
        let strategy = KimiAPIFetchStrategy()
        let context = makeKimiFetchContext(
            sourceMode: .api,
            environment: ["KIMI_CODE_HOME": home.path])

        await #expect(throws: KimiAPIError.missingAPIKey) {
            try await strategy.fetch(context)
        }
    }

    @Test
    func rejected_CLI_credential_keeps_CLI_remediation() {
        let cliError = KimiCLICredentialFetchStrategy.normalizedCodeAPIError(KimiAPIError.invalidAPIKey)
        let keyError = KimiCLICredentialFetchStrategy.normalizedCodeAPIError(KimiAPIError.apiError("failed"))

        #expect(cliError as? KimiAPIError == .invalidCodeCredential)
        #expect(keyError as? KimiAPIError == .apiError("failed"))
    }

    @Test
    func auto_retries_fresh_CLI_credential_after_rejected_API_key() async throws {
        let home = try makeTemporaryKimiCodeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try writeKimiCodeCredential(
            home: home,
            accessToken: "cli-ok",
            expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970)
        let transport = KimiOrderedCredentialTransport()
        let pipeline = ProviderFetchPipeline { _ in
            [
                KimiAPIFetchStrategy(transport: transport),
                KimiCLICredentialFetchStrategy(transport: transport),
            ]
        }
        let context = makeKimiFetchContext(
            sourceMode: .auto,
            environment: [
                "KIMI_CODE_API_KEY": "api-bad",
                "KIMI_CODE_HOME": home.path,
            ])

        let outcome = await pipeline.fetch(context: context, provider: .kimi)
        let result = try outcome.result.get()

        #expect(result.sourceLabel == "Kimi Code CLI")
        #expect(outcome.attempts.map(\.strategyID) == ["kimi.api", "kimi.cli"])
        #expect(await transport.authorizationHeaders() == [
            "Bearer api-bad",
            "Bearer cli-ok",
        ])
    }

    @Test
    func auto_mode_falls_back_from_invalid_API_key_to_web_cookies() {
        let strategy = KimiAPIFetchStrategy()
        let context = makeKimiFetchContext(sourceMode: .auto)

        #expect(strategy.shouldFallback(on: KimiAPIError.invalidAPIKey, context: context))
    }

    @Test
    func explicit_API_mode_does_not_fall_back_from_invalid_API_key() {
        let strategy = KimiAPIFetchStrategy()
        let context = makeKimiFetchContext(sourceMode: .api)

        #expect(strategy.shouldFallback(on: KimiAPIError.invalidAPIKey, context: context) == false)
    }

    @Test
    func explicit_API_mode_reports_API_key_remediation_when_key_is_missing() async {
        let strategy = KimiAPIFetchStrategy()
        let context = makeKimiFetchContext(sourceMode: .api)

        await #expect(throws: KimiAPIError.missingAPIKey) {
            try await strategy.fetch(context)
        }
    }

    @Test
    func auto_mode_falls_back_from_API_response_decoding_failure() {
        let strategy = KimiAPIFetchStrategy()
        let context = makeKimiFetchContext(sourceMode: .auto)
        let error = DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "Unexpected Kimi payload"))

        #expect(strategy.shouldFallback(on: error, context: context))
    }

    @Test
    func explicit_API_mode_surfaces_response_decoding_failure() {
        let strategy = KimiAPIFetchStrategy()
        let context = makeKimiFetchContext(sourceMode: .api)
        let error = DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "Unexpected Kimi payload"))

        #expect(strategy.shouldFallback(on: error, context: context) == false)
    }

    @Test
    func auto_mode_does_not_start_web_fallback_after_cancellation() {
        let strategy = KimiAPIFetchStrategy()
        let context = makeKimiFetchContext(sourceMode: .auto)

        #expect(strategy.shouldFallback(on: CancellationError(), context: context) == false)
        #expect(strategy.shouldFallback(on: URLError(.cancelled), context: context) == false)
    }
}

struct KimiUsageResponseParsingTests {
    @Test
    func parses_valid_response() throws {
        let json = """
        {
          "usages": [
            {
              "scope": "FEATURE_CODING",
              "detail": {
                "limit": "2048",
                "used": "375",
                "remaining": "1673",
                "resetTime": "2026-01-09T15:23:13.373329235Z"
              },
              "limits": [
                {
                  "window": {
                    "duration": 300,
                    "timeUnit": "TIME_UNIT_MINUTE"
                  },
                  "detail": {
                    "limit": "200",
                    "used": "200",
                    "resetTime": "2026-01-06T15:05:24.374187075Z"
                  }
                }
              ]
            }
          ]
        }
        """

        let response = try JSONDecoder().decode(KimiUsageResponse.self, from: Data(json.utf8))

        #expect(response.usages.count == 1)
        let usage = response.usages[0]
        #expect(usage.scope == "FEATURE_CODING")
        #expect(usage.detail.limit == "2048")
        #expect(usage.detail.used == "375")
        #expect(usage.detail.remaining == "1673")
        #expect(usage.detail.resetTime == "2026-01-09T15:23:13.373329235Z")

        #expect(usage.limits?.count == 1)
        let rateLimit = usage.limits?.first
        #expect(rateLimit?.window.duration == 300)
        #expect(rateLimit?.window.timeUnit == "TIME_UNIT_MINUTE")
        #expect(rateLimit?.detail.limit == "200")
        #expect(rateLimit?.detail.used == "200")
    }

    @Test
    func parses_response_without_rate_limits() throws {
        let json = """
        {
          "usages": [
            {
              "scope": "FEATURE_CODING",
              "detail": {
                "limit": "2048",
                "used": "375",
                "remaining": "1673",
                "resetTime": "2026-01-09T15:23:13.373329235Z"
              },
              "limits": []
            }
          ]
        }
        """

        let response = try JSONDecoder().decode(KimiUsageResponse.self, from: Data(json.utf8))
        #expect(response.usages.first?.limits?.isEmpty == true)
    }

    @Test
    func parses_response_with_null_limits() throws {
        let json = """
        {
          "usages": [
            {
              "scope": "FEATURE_CODING",
              "detail": {
                "limit": "2048",
                "used": "375",
                "remaining": "1673",
                "resetTime": "2026-01-09T15:23:13.373329235Z"
              },
              "limits": null
            }
          ]
        }
        """

        let response = try JSONDecoder().decode(KimiUsageResponse.self, from: Data(json.utf8))
        #expect(response.usages.first?.limits == nil)
    }

    @Test
    func parses_code_API_usage_response() throws {
        let json = """
        {
          "usage": {
            "limit": "2048",
            "used": "375",
            "remaining": "1673",
            "resetTime": "2026-01-09T15:23:13.373329235Z"
          },
          "limits": [
            {
              "window": {
                "duration": 300,
                "timeUnit": "TIME_UNIT_MINUTE"
              },
              "detail": {
                "limit": "200",
                "used": "19",
                "remaining": "181",
                "resetTime": "2026-01-06T15:05:24.374187075Z"
              }
            }
          ]
        }
        """

        let snapshot = try KimiUsageFetcher._parseCodeAPIUsageForTesting(Data(json.utf8))
        #expect(snapshot.weekly.limit == "2048")
        #expect(snapshot.weekly.used == "375")
        #expect(snapshot.rateLimit?.limit == "200")
        #expect(snapshot.rateLimit?.used == "19")

        let usage = snapshot.toUsageSnapshot()
        #expect(abs((usage.primary?.usedPercent ?? -1) - 18.3105) < 0.001)
        #expect(usage.primary?.resetDescription == "375/2048 requests")
        #expect(abs((usage.secondary?.usedPercent ?? -1) - 9.5) < 0.001)
        #expect(usage.secondary?.windowMinutes == 300)
        #expect(usage.secondary?.resetDescription == "Rate: 19/200 per 5 hours")
    }

    @Test
    func sends_CLI_identity_headers_on_the_existing_usage_request() async throws {
        let baseURL = try #require(URL(string: "https://api.kimi.com"))
        let identityHeaders = [
            "User-Agent": "CodexBar/test",
            "X-Msh-Platform": "kimi_code_cli",
            "X-Msh-Device-Id": "test-device-id",
        ]
        let transport = ProviderHTTPTransportHandler { request in
            #expect(request.url?.path == "/coding/v1/usages")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-token")
            for (name, value) in identityHeaders {
                #expect(request.value(forHTTPHeaderField: name) == value)
            }
            let response = try #require(HTTPURLResponse(
                url: request.url ?? baseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]))
            let data = Data("""
            {
              "usage": {"limit": "100", "used": "25", "remaining": "75"},
              "limits": []
            }
            """.utf8)
            return (data, response)
        }

        let snapshot = try await KimiUsageFetcher.fetchCodeAPIUsage(
            apiKey: "oauth-token",
            baseURL: baseURL,
            identityHeaders: identityHeaders,
            transport: transport)

        #expect(snapshot.toUsageSnapshot().primary?.usedPercent == 25)
    }

    @Test
    func converts_weekly_only_usage_into_primary_quota_lane() {
        let snapshot = KimiUsageSnapshot(
            weekly: KimiUsageDetail(
                limit: "2048",
                used: "512",
                remaining: "1536",
                resetTime: "2026-01-09T15:23:13Z"),
            rateLimit: nil,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000))

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 25)
        #expect(usage.primary?.resetDescription == "512/2048 requests")
        #expect(usage.secondary == nil)
    }

    @Test
    func parses_official_numeric_values_and_reset_key_variants() throws {
        let json = """
        {
          "usage": {
            "limit": 1000,
            "used": 40,
            "remaining": 960,
            "resetAt": "2026-01-09T15:23:13Z"
          },
          "limits": [
            {
              "window": {
                "duration": 300,
                "timeUnit": "TIME_UNIT_MINUTE"
              },
              "detail": {
                "limit": 100,
                "remaining": 99,
                "reset_at": "2026-01-06T13:33:02Z"
              }
            }
          ]
        }
        """

        let snapshot = try KimiUsageFetcher._parseCodeAPIUsageForTesting(Data(json.utf8))

        #expect(snapshot.weekly.limit == "1000")
        #expect(snapshot.weekly.used == "40")
        #expect(snapshot.weekly.remaining == "960")
        #expect(snapshot.weekly.resetTime == "2026-01-09T15:23:13Z")
        #expect(snapshot.rateLimit?.limit == "100")
        #expect(snapshot.rateLimit?.used == nil)
        #expect(snapshot.rateLimit?.remaining == "99")
        #expect(snapshot.rateLimit?.resetTime == "2026-01-06T13:33:02Z")
    }

    @Test
    func parses_subscription_stat_response() throws {
        let json = """
        {
          "ratelimitCode5h": {
            "ratio": 0.4689,
            "enabled": true,
            "resetTime": "2026-07-02T11:56:36.876796734Z"
          },
          "ratelimitCode7d": {
            "ratio": 0.0946,
            "enabled": true,
            "resetTime": "2026-07-09T06:56:36.876796734Z"
          },
          "subscriptionBalance": {
            "id": "19eee1de-9092-8315-8000-0000e4e34d79",
            "feature": "FEATURE_OMNI",
            "type": "SUBSCRIPTION",
            "unit": "UNIT_CREDIT",
            "amountUsedRatio": 1,
            "kimiCodeUsedRatio": 0.2854,
            "expireTime": "2026-07-23T00:00:00Z"
          },
          "giftBalances": [
            {
              "id": "19efdb95-e082-804c-9ecd-978b7ab37d36",
              "feature": "FEATURE_OMNI",
              "type": "GIFT",
              "unit": "UNIT_CREDIT",
              "amountUsedRatio": 1,
              "kimiCodeUsedRatio": 1,
              "expireTime": "2026-07-31T15:59:59Z"
            }
          ]
        }
        """

        let response = try JSONDecoder().decode(KimiSubscriptionStatsResponse.self, from: Data(json.utf8))

        #expect(response.subscriptionBalance?.feature == "FEATURE_OMNI")
        #expect(response.subscriptionBalance?.type == "SUBSCRIPTION")
        #expect(response.subscriptionBalance?.amountUsedRatio == 1)
        #expect(response.subscriptionBalance?.expireTime == "2026-07-23T00:00:00Z")
        #expect(response.ratelimitCode7d?.ratio == 0.0946)
        #expect(response.ratelimitCode7d?.enabled == true)
        #expect(response.ratelimitCode7d?.resetTime == "2026-07-09T06:56:36.876796734Z")
    }

    @Test
    func subscription_grace_is_a_total_budget_for_existing_usage_windows() async throws {
        let usageJSON = """
        {
          "usages": [
            {
              "scope": "FEATURE_CODING",
              "detail": { "limit": "100", "used": "25", "remaining": "75" },
              "limits": [
                {
                  "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                  "detail": { "limit": "20", "used": "5", "remaining": "15" }
                }
              ]
            }
          ]
        }
        """
        let transport = ProviderHTTPTransportHandler { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil))
            if url.path.hasSuffix("/GetUsages") {
                return await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                        continuation.resume(returning: (Data(usageJSON.utf8), response))
                    }
                }
            }

            return await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    continuation.resume(returning: (Data("{}".utf8), response))
                }
            }
        }

        let startedAt = ContinuousClock.now
        let snapshot = try await KimiUsageFetcher._fetchUsageForTesting(
            authToken: "test-token",
            transport: transport,
            subscriptionGrace: .milliseconds(20))
        let elapsed = startedAt.duration(to: .now)
        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 25)
        #expect(usage.secondary?.usedPercent == 25)
        #expect(usage.extraRateWindows == nil)
        #expect(elapsed < .milliseconds(250), "Subscription enrichment outlived its total budget: \(elapsed)")

        // Drain the deliberately cancellation-ignoring test request before the test exits.
        try await Task.sleep(for: .milliseconds(550))
    }

    @Test
    func subscription_stat_enriches_usage_when_it_finishes_within_the_total_budget() async throws {
        let usageJSON = """
        {
          "usages": [
            {
              "scope": "FEATURE_CODING",
              "detail": { "limit": "100", "used": "25", "remaining": "75" },
              "limits": []
            }
          ]
        }
        """
        let subscriptionJSON = """
        {
          "subscriptionBalance": {
            "feature": "FEATURE_OMNI",
            "type": "SUBSCRIPTION",
            "amountUsedRatio": 0.42,
            "expireTime": "2026-07-23T00:00:00Z"
          },
          "ratelimitCode7d": {
            "ratio": 0.17,
            "enabled": true,
            "resetTime": "2026-07-13T15:28:00Z"
          }
        }
        """
        let transport = ProviderHTTPTransportHandler { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil))
            if url.path.hasSuffix("/GetUsages") {
                return (Data(usageJSON.utf8), response)
            }
            #expect(url.path.hasSuffix("/GetSubscriptionStats"))
            return (Data(subscriptionJSON.utf8), response)
        }

        let snapshot = try await KimiUsageFetcher._fetchUsageForTesting(
            authToken: "test-token",
            transport: transport,
            subscriptionGrace: .seconds(1))
        let windows = try #require(snapshot.toUsageSnapshot().extraRateWindows)
        let monthly = try #require(windows.first { $0.id == "kimi-monthly" })
        let weeklyCode = try #require(windows.first { $0.id == "kimi-code-7d" })

        #expect(monthly.id == "kimi-monthly")
        #expect(monthly.window.usedPercent == 42)
        #expect(weeklyCode.title == "Code 7-day")
        #expect(weeklyCode.window.usedPercent == 17)
        #expect(weeklyCode.window.windowMinutes == 7 * 24 * 60)
    }

    @Test
    func builds_default_code_API_usage_endpoint() throws {
        let baseURL = try #require(URL(string: "https://api.kimi.com"))
        let endpoint = KimiUsageFetcher._codeAPIUsageEndpointForTesting(baseURL: baseURL)

        #expect(endpoint.absoluteString == "https://api.kimi.com/coding/v1/usages")
    }

    @Test
    func appends_code_API_path_to_custom_proxy_root() throws {
        let baseURL = try #require(URL(string: "https://proxy.example.com/kimi"))
        let endpoint = KimiUsageFetcher._codeAPIUsageEndpointForTesting(baseURL: baseURL)

        #expect(endpoint.absoluteString == "https://proxy.example.com/kimi/coding/v1/usages")
    }

    @Test
    func does_not_duplicate_code_API_path_when_base_URL_already_includes_it() throws {
        let baseURL = try #require(URL(string: "https://api.kimi.com/coding/v1"))
        let endpoint = KimiUsageFetcher._codeAPIUsageEndpointForTesting(baseURL: baseURL)

        #expect(endpoint.absoluteString == "https://api.kimi.com/coding/v1/usages")
    }

    @Test
    func does_not_duplicate_code_API_path_with_trailing_slash() throws {
        let baseURL = try #require(URL(string: "https://proxy.example.com/kimi/coding/v1/"))
        let endpoint = KimiUsageFetcher._codeAPIUsageEndpointForTesting(baseURL: baseURL)

        #expect(endpoint.absoluteString == "https://proxy.example.com/kimi/coding/v1/usages")
    }

    @Test
    func does_not_duplicate_coding_path_prefix() throws {
        let baseURL = try #require(URL(string: "https://proxy.example.com/kimi/coding/"))
        let endpoint = KimiUsageFetcher._codeAPIUsageEndpointForTesting(baseURL: baseURL)

        #expect(endpoint.absoluteString == "https://proxy.example.com/kimi/coding/v1/usages")
    }

    @Test
    func rejects_insecure_code_API_base_URL_before_sending_bearer_token() async throws {
        let baseURL = try #require(URL(string: "http://proxy.example.com/kimi"))

        await #expect(throws: KimiAPIError.invalidRequest(
            "Kimi Code API base URL must use HTTPS without user info"))
        {
            _ = try await KimiUsageFetcher.fetchCodeAPIUsage(apiKey: "secret-token", baseURL: baseURL)
        }
    }

    @Test
    func maps_code_API_authentication_and_permission_errors_separately() {
        #expect(KimiUsageFetcher._codeAPIErrorForTesting(statusCode: 401) == .invalidAPIKey)
        #expect(
            KimiUsageFetcher._codeAPIErrorForTesting(statusCode: 403)
                == .apiError("HTTP 403 (permission or quota denied)"))
    }

    @Test
    func throws_on_invalid_json() {
        let invalidJson = "{ invalid json }"

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(KimiUsageResponse.self, from: Data(invalidJson.utf8))
        }
    }

    @Test
    func throws_on_missing_feature_coding_scope() throws {
        let json = """
        {
          "usages": [
            {
              "scope": "OTHER_SCOPE",
              "detail": {
                "limit": "100",
                "used": "50",
                "remaining": "50",
                "resetTime": "2026-01-09T15:23:13.373329235Z"
              }
            }
          ]
        }
        """

        let response = try JSONDecoder().decode(KimiUsageResponse.self, from: Data(json.utf8))
        let codingUsage = response.usages.first { $0.scope == "FEATURE_CODING" }
        #expect(codingUsage == nil)
    }
}

struct KimiUsageSnapshotConversionTests {
    @Test
    func converts_to_usage_snapshot_with_both_windows() {
        let now = Date()
        let weeklyDetail = KimiUsageDetail(
            limit: "2048",
            used: "375",
            remaining: "1673",
            resetTime: "2026-01-09T15:23:13.373329235Z")
        let rateLimitDetail = KimiUsageDetail(
            limit: "200",
            used: "200",
            remaining: "0",
            resetTime: "2026-01-06T15:05:24.374187075Z")

        let snapshot = KimiUsageSnapshot(
            weekly: weeklyDetail,
            rateLimit: rateLimitDetail,
            updatedAt: now)

        let usageSnapshot = snapshot.toUsageSnapshot()

        #expect(usageSnapshot.primary != nil)
        let weeklyExpected = 375.0 / 2048.0 * 100.0
        #expect(abs((usageSnapshot.primary?.usedPercent ?? 0.0) - weeklyExpected) < 0.01)
        #expect(usageSnapshot.primary?.resetDescription == "375/2048 requests")
        #expect(usageSnapshot.primary?.windowMinutes == nil)

        #expect(usageSnapshot.secondary != nil)
        let rateExpected = 200.0 / 200.0 * 100.0
        #expect(abs((usageSnapshot.secondary?.usedPercent ?? 0.0) - rateExpected) < 0.01)
        #expect(usageSnapshot.secondary?.windowMinutes == 300) // 5 hours
        #expect(usageSnapshot.secondary?.resetDescription == "Rate: 200/200 per 5 hours")

        #expect(usageSnapshot.tertiary == nil)
        #expect(usageSnapshot.updatedAt == now)
    }

    @Test
    func converts_subscription_balance_to_monthly_extra_window() throws {
        let now = Date()
        let weeklyDetail = KimiUsageDetail(
            limit: "2048",
            used: "375",
            remaining: "1673",
            resetTime: "2026-01-09T15:23:13.373329235Z")
        let subscriptionBalance = KimiSubscriptionBalance(
            feature: "FEATURE_OMNI",
            type: "SUBSCRIPTION",
            amountUsedRatio: 1,
            expireTime: "2026-07-23T00:00:00Z")

        let snapshot = KimiUsageSnapshot(
            weekly: weeklyDetail,
            rateLimit: nil,
            subscriptionBalance: subscriptionBalance,
            updatedAt: now)
        let usageSnapshot = snapshot.toUsageSnapshot()

        let monthly = try #require(usageSnapshot.extraRateWindows?.first)
        #expect(monthly.id == "kimi-monthly")
        #expect(monthly.title == "Monthly")
        #expect(monthly.window.usedPercent == 100)
        #expect(monthly.window.resetsAt == Self.date("2026-07-23T00:00:00Z"))
    }

    @Test
    func reflects_partial_subscription_usage_in_monthly_window() throws {
        let now = Date()
        let weeklyDetail = KimiUsageDetail(
            limit: "2048",
            used: "375",
            remaining: "1673",
            resetTime: "2026-01-09T15:23:13.373329235Z")
        // A live, partially-used balance (not the fully-exhausted 1.0 fixture): amountUsedRatio is a
        // real consumption ratio, so the Monthly window must track it rather than pin to 100%.
        let subscriptionBalance = KimiSubscriptionBalance(
            feature: "FEATURE_OMNI",
            type: "SUBSCRIPTION",
            amountUsedRatio: 0.7716,
            expireTime: "2026-07-23T00:00:00Z")

        let snapshot = KimiUsageSnapshot(
            weekly: weeklyDetail,
            rateLimit: nil,
            subscriptionBalance: subscriptionBalance,
            updatedAt: now)
        let usageSnapshot = snapshot.toUsageSnapshot()

        let monthly = try #require(usageSnapshot.extraRateWindows?.first)
        #expect(monthly.id == "kimi-monthly")
        #expect(abs(monthly.window.usedPercent - 77.16) < 0.0001)
    }

    @Test
    func converts_subscription_code_weekly_limit_to_extra_window() throws {
        let now = Date()
        let weeklyDetail = KimiUsageDetail(
            limit: "2048",
            used: "375",
            remaining: "1673",
            resetTime: "2026-01-09T15:23:13.373329235Z")
        let subscriptionCodeWeeklyLimit = KimiSubscriptionRateLimit(
            ratio: 0.0946,
            enabled: true,
            resetTime: "2026-07-13T15:28:00Z")

        let snapshot = KimiUsageSnapshot(
            weekly: weeklyDetail,
            rateLimit: nil,
            subscriptionBalance: nil,
            subscriptionCodeWeeklyLimit: subscriptionCodeWeeklyLimit,
            updatedAt: now)
        let usageSnapshot = snapshot.toUsageSnapshot()

        let weeklyCode = try #require(usageSnapshot.extraRateWindows?.first)
        #expect(weeklyCode.id == "kimi-code-7d")
        #expect(weeklyCode.title == "Code 7-day")
        #expect(abs(weeklyCode.window.usedPercent - 9.46) < 0.0001)
        #expect(weeklyCode.window.windowMinutes == 7 * 24 * 60)
        #expect(weeklyCode.window.resetsAt == Self.date("2026-07-13T15:28:00Z"))
    }

    @Test
    func omits_disabled_and_nonfinite_subscription_quota_ratios() {
        let weeklyDetail = KimiUsageDetail(
            limit: "2048",
            used: "375",
            remaining: "1673",
            resetTime: "2026-01-09T15:23:13.373329235Z")
        let invalidLimits = [
            KimiSubscriptionRateLimit(ratio: 0.25, enabled: false, resetTime: nil),
            KimiSubscriptionRateLimit(ratio: .nan, enabled: true, resetTime: nil),
            KimiSubscriptionRateLimit(ratio: .infinity, enabled: true, resetTime: nil),
        ]

        for limit in invalidLimits {
            let snapshot = KimiUsageSnapshot(
                weekly: weeklyDetail,
                rateLimit: nil,
                subscriptionBalance: KimiSubscriptionBalance(
                    feature: "FEATURE_OMNI",
                    type: "SUBSCRIPTION",
                    amountUsedRatio: .nan,
                    expireTime: nil),
                subscriptionCodeWeeklyLimit: limit,
                updatedAt: Date())

            #expect(snapshot.toUsageSnapshot().extraRateWindows == nil)
        }
    }

    @Test
    func converts_to_usage_snapshot_without_rate_limit() {
        let now = Date()
        let weeklyDetail = KimiUsageDetail(
            limit: "2048",
            used: "375",
            remaining: "1673",
            resetTime: "2026-01-09T15:23:13.373329235Z")

        let snapshot = KimiUsageSnapshot(
            weekly: weeklyDetail,
            rateLimit: nil,
            updatedAt: now)

        let usageSnapshot = snapshot.toUsageSnapshot()

        #expect(usageSnapshot.primary != nil)
        let weeklyExpected = 375.0 / 2048.0 * 100.0
        #expect(abs((usageSnapshot.primary?.usedPercent ?? 0.0) - weeklyExpected) < 0.01)
        #expect(usageSnapshot.secondary == nil)
        #expect(usageSnapshot.tertiary == nil)
    }

    @Test
    func converts_invalid_rate_limit_as_unavailable() {
        let now = Date()
        let weeklyDetail = KimiUsageDetail(
            limit: "2048",
            used: "375",
            remaining: "1673",
            resetTime: "2026-01-09T15:23:13.373329235Z")
        let invalidRateLimit = KimiUsageDetail(
            limit: "0",
            used: "0",
            remaining: "0",
            resetTime: "2026-01-06T15:05:24.374187075Z")

        let snapshot = KimiUsageSnapshot(
            weekly: weeklyDetail,
            rateLimit: invalidRateLimit,
            updatedAt: now)

        let usageSnapshot = snapshot.toUsageSnapshot()

        #expect(usageSnapshot.primary?.resetDescription == "375/2048 requests")
        #expect(usageSnapshot.secondary == nil)
    }

    @Test
    func handles_zero_values_correctly() {
        let now = Date()
        let weeklyDetail = KimiUsageDetail(
            limit: "2048",
            used: "0",
            remaining: "2048",
            resetTime: "2026-01-09T15:23:13.373329235Z")

        let snapshot = KimiUsageSnapshot(
            weekly: weeklyDetail,
            rateLimit: nil,
            updatedAt: now)

        let usageSnapshot = snapshot.toUsageSnapshot()
        #expect(usageSnapshot.primary?.usedPercent == 0.0)
        #expect(usageSnapshot.secondary == nil)
    }

    @Test
    func handles_hundred_percent_correctly() {
        let now = Date()
        let weeklyDetail = KimiUsageDetail(
            limit: "2048",
            used: "2048",
            remaining: "0",
            resetTime: "2026-01-09T15:23:13.373329235Z")

        let snapshot = KimiUsageSnapshot(
            weekly: weeklyDetail,
            rateLimit: nil,
            updatedAt: now)

        let usageSnapshot = snapshot.toUsageSnapshot()
        #expect(usageSnapshot.primary?.usedPercent == 100.0)
        #expect(usageSnapshot.secondary == nil)
    }

    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

struct KimiTokenResolverTests {
    @Test
    func resolves_token_from_environment() {
        KeychainAccessGate.withTaskOverrideForTesting(true) {
            let env = ["KIMI_AUTH_TOKEN": "test.jwt.token"]
            let token = ProviderTokenResolver.kimiAuthToken(environment: env)
            #expect(token == "test.jwt.token")
        }
    }

    @Test
    func resolves_token_from_keychain_first() {
        // This test would require mocking the keychain.
        KeychainAccessGate.withTaskOverrideForTesting(true) {
            let env = ["KIMI_AUTH_TOKEN": "test.env.token"]
            let token = ProviderTokenResolver.kimiAuthToken(environment: env)
            #expect(token == "test.env.token")
        }
    }

    @Test
    func resolution_includes_source() {
        KeychainAccessGate.withTaskOverrideForTesting(true) {
            let env = ["KIMI_AUTH_TOKEN": "test.jwt.token"]
            let resolution = ProviderTokenResolver.kimiAuthResolution(environment: env)

            #expect(resolution?.token == "test.jwt.token")
            #expect(resolution?.source == .environment)
        }
    }
}

struct KimiAPIErrorTests {
    @Test
    func error_descriptions_are_helpful() {
        #expect(KimiAPIError.missingToken.errorDescription?.contains("missing") == true)
        #expect(KimiAPIError.invalidToken.errorDescription?.contains("invalid") == true)
        #expect(KimiAPIError.missingAPIKey.errorDescription?.contains("Settings > Providers > Kimi") == true)
        #expect(KimiAPIError.missingAPIKey.errorDescription?.contains("KIMI_CODE_API_KEY") == true)
        #expect(KimiAPIError.expiredCodeCredential.errorDescription?.contains("does not refresh") == true)
        #expect(KimiAPIError.invalidCodeCredential.errorDescription?.contains("Sign in again") == true)
        #expect(KimiAPIError.invalidAPIKey.errorDescription?.contains("API key") == true)
        #expect(KimiAPIError.invalidRequest("Bad request").errorDescription?.contains("Bad request") == true)
        #expect(KimiAPIError.networkError("Timeout").errorDescription?.contains("Timeout") == true)
        #expect(KimiAPIError.apiError("HTTP 500").errorDescription?.contains("HTTP 500") == true)
        #expect(KimiAPIError.parseFailed("Invalid JSON").errorDescription?.contains("Invalid JSON") == true)
    }
}
