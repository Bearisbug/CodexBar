import Foundation
import Testing
@testable import CodexBarCore

struct AlibabaCodingPlanSettingsReaderTests {
    @Test
    func api_token_reads_from_environment() {
        let token = AlibabaCodingPlanSettingsReader.apiToken(environment: ["ALIBABA_CODING_PLAN_API_KEY": "abc123"])
        #expect(token == "abc123")
    }

    @Test
    func api_token_reads_qwen_alias_from_environment() {
        let token = AlibabaCodingPlanSettingsReader.apiToken(environment: ["ALIBABA_QWEN_API_KEY": "qwen123"])
        #expect(token == "qwen123")
    }

    @Test
    func api_token_reads_dashscope_alias_from_environment() {
        let token = AlibabaCodingPlanSettingsReader.apiToken(environment: ["DASHSCOPE_API_KEY": "dashscope123"])
        #expect(token == "dashscope123")
    }

    @Test
    func api_token_prefers_coding_plan_key_over_aliases() {
        let token = AlibabaCodingPlanSettingsReader.apiToken(environment: [
            "ALIBABA_CODING_PLAN_API_KEY": "coding-plan",
            "ALIBABA_QWEN_API_KEY": "qwen",
            "DASHSCOPE_API_KEY": "dashscope",
        ])
        #expect(token == "coding-plan")
    }

    @Test
    func api_token_strips_quotes() {
        let token = AlibabaCodingPlanSettingsReader
            .apiToken(environment: ["ALIBABA_CODING_PLAN_API_KEY": "\"token-xyz\""])
        #expect(token == "token-xyz")
    }

    @Test
    func quota_URL_infers_scheme() {
        let url = AlibabaCodingPlanSettingsReader
            .quotaURL(environment: [AlibabaCodingPlanSettingsReader
                    .quotaURLKey: "modelstudio.console.alibabacloud.com/data/api.json"])
        #expect(url?.absoluteString == "https://modelstudio.console.alibabacloud.com/data/api.json")
    }

    @Test
    func endpoint_overrides_allow_custom_https_hosts_by_default() {
        let env = [
            AlibabaCodingPlanSettingsReader.hostKey: "https://attacker.example",
            AlibabaCodingPlanSettingsReader.quotaURLKey: "https://attacker.example/data/api.json",
        ]

        #expect(AlibabaCodingPlanSettingsReader.hostOverride(environment: env) == "attacker.example")
        #expect(AlibabaCodingPlanSettingsReader.quotaURL(environment: env)?.host == "attacker.example")
        #expect(AlibabaCodingPlanSettingsReader.rejectedEndpointOverrideKey(environment: env) == nil)
    }

    @Test
    func host_endpoint_overrides_preserve_explicit_port() {
        let env = [AlibabaCodingPlanSettingsReader.hostKey: "proxy.example.test:8443"]

        #expect(AlibabaCodingPlanSettingsReader.hostOverride(environment: env) == "proxy.example.test:8443")
        #expect(
            AlibabaCodingPlanUsageFetcher.resolveQuotaURL(region: .international, environment: env).absoluteString ==
                "https://proxy.example.test:8443/data/api.json?action=zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2&product=broadscope-bailian&api=queryCodingPlanInstanceInfoV2&currentRegionId=ap-southeast-1")
        #expect(
            AlibabaCodingPlanUsageFetcher.resolveConsoleDashboardURL(region: .international, environment: env)
                .absoluteString
                .hasPrefix("https://proxy.example.test:8443/") == true)
    }

    @Test
    func endpoint_overrides_reject_encoded_host_delimiters_before_suffix_matching() {
        let encodedSlash = "https://attacker.example%2f.modelstudio.console.alibabacloud.com"
        let doubleEncodedSlash = "https://attacker.example%252f.modelstudio.console.alibabacloud.com"
        let env = [
            AlibabaCodingPlanSettingsReader.hostKey: encodedSlash,
            AlibabaCodingPlanSettingsReader.quotaURLKey: "\(encodedSlash)/data/api.json",
        ]

        #expect(AlibabaCodingPlanSettingsReader.hostOverride(environment: env) == nil)
        #expect(AlibabaCodingPlanSettingsReader.quotaURL(environment: env) == nil)
        #expect(AlibabaCodingPlanSettingsReader.hostOverride(environment: [
            AlibabaCodingPlanSettingsReader.hostKey: doubleEncodedSlash,
        ]) == nil)
    }

    @Test
    func endpoint_overrides_reject_whitespace_and_control_characters_in_hosts() {
        for host in ["https://bad host", "https://bad%20host", "https://bad%09host"] {
            #expect(AlibabaCodingPlanSettingsReader.hostOverride(environment: [
                AlibabaCodingPlanSettingsReader.hostKey: host,
            ]) == nil)
            #expect(AlibabaCodingPlanSettingsReader.quotaURL(environment: [
                AlibabaCodingPlanSettingsReader.quotaURLKey: "\(host)/data/api.json",
            ]) == nil)
        }
    }

    @Test
    func endpoint_overrides_require_https_and_no_userinfo() {
        #expect(AlibabaCodingPlanSettingsReader.hostOverride(environment: [
            AlibabaCodingPlanSettingsReader.hostKey: "http://modelstudio.console.alibabacloud.com",
        ]) == nil)
        #expect(AlibabaCodingPlanSettingsReader.quotaURL(environment: [
            AlibabaCodingPlanSettingsReader.quotaURLKey:
                "https://user:pass@modelstudio.console.alibabacloud.com/data/api.json",
        ]) == nil)
    }

    @Test
    func strict_provider_endpoint_mode_rejects_custom_hosts() {
        let env = [
            AlibabaCodingPlanSettingsReader.requireProviderEndpointOverridesKey: "true",
            AlibabaCodingPlanSettingsReader.hostKey: "proxy.example.test",
            AlibabaCodingPlanSettingsReader.quotaURLKey: "https://proxy.example.test/data/api.json",
        ]

        #expect(AlibabaCodingPlanSettingsReader.hostOverride(environment: env) == nil)
        #expect(AlibabaCodingPlanSettingsReader.quotaURL(environment: env) == nil)
        #expect(AlibabaCodingPlanSettingsReader
            .rejectedEndpointOverrideKey(environment: env) == AlibabaCodingPlanSettingsReader.hostKey)
    }

    @Test
    func strict_provider_endpoint_mode_rejects_customer_controlled_Alibaba_Cloud_hosts() {
        let env = [
            AlibabaCodingPlanSettingsReader.requireProviderEndpointOverridesKey: "true",
            AlibabaCodingPlanSettingsReader.hostKey: "tenant.cn-beijing.fc.aliyuncs.com",
        ]

        #expect(AlibabaCodingPlanSettingsReader.hostOverride(environment: env) == nil)
        #expect(AlibabaCodingPlanSettingsReader
            .rejectedEndpointOverrideKey(environment: env) == AlibabaCodingPlanSettingsReader.hostKey)
    }

    @Test
    func strict_provider_endpoint_mode_accepts_known_Coding_Plan_hosts() {
        let env = [
            AlibabaCodingPlanSettingsReader.requireProviderEndpointOverridesKey: "true",
            AlibabaCodingPlanSettingsReader.hostKey: "bailian-beijing-cs.aliyuncs.com",
        ]

        #expect(
            AlibabaCodingPlanSettingsReader.hostOverride(environment: env) ==
                "bailian-beijing-cs.aliyuncs.com")
        #expect(AlibabaCodingPlanSettingsReader.rejectedEndpointOverrideKey(environment: env) == nil)
    }

    @Test
    func custom_https_compatibility_mode_still_rejects_http_and_userinfo() {
        #expect(AlibabaCodingPlanSettingsReader.hostOverride(environment: [
            AlibabaCodingPlanSettingsReader.hostKey: "http://proxy.example.test",
        ]) == nil)
        #expect(AlibabaCodingPlanSettingsReader.rejectedEndpointOverrideKey(environment: [
            AlibabaCodingPlanSettingsReader.quotaURLKey: "https://user:pass@proxy.example.test/data/api.json",
        ]) == AlibabaCodingPlanSettingsReader.quotaURLKey)
    }

    @Test
    func missing_cookie_error_includes_access_hint_when_present() {
        let error = AlibabaCodingPlanSettingsError
            .missingCookie(details: "Safari cookie file exists but is not readable.")
        #expect(error.errorDescription?.contains("Safari cookie file exists but is not readable.") == true)
    }
}

struct AlibabaCodingPlanUsageSnapshotTests {
    @Test
    func maps_usage_snapshot_windows() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reset5h = Date(timeIntervalSince1970: 1_700_000_300)
        let resetWeek = Date(timeIntervalSince1970: 1_700_010_000)
        let resetMonth = Date(timeIntervalSince1970: 1_700_100_000)
        let snapshot = AlibabaCodingPlanUsageSnapshot(
            planName: "Pro",
            fiveHourUsedQuota: 20,
            fiveHourTotalQuota: 100,
            fiveHourNextRefreshTime: reset5h,
            weeklyUsedQuota: 120,
            weeklyTotalQuota: 400,
            weeklyNextRefreshTime: resetWeek,
            monthlyUsedQuota: 500,
            monthlyTotalQuota: 2000,
            monthlyNextRefreshTime: resetMonth,
            updatedAt: now)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 20)
        #expect(usage.primary?.windowMinutes == 300)
        #expect(usage.secondary?.usedPercent == 30)
        #expect(usage.secondary?.windowMinutes == 10080)
        #expect(usage.tertiary?.usedPercent == 25)
        #expect(usage.tertiary?.windowMinutes == 43200)
        #expect(usage.loginMethod(for: .alibaba) == "Pro")
    }

    @Test
    func shifts_primary_reset_forward_when_backend_reset_is_not_future() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let stalePrimaryReset = Date(timeIntervalSince1970: 1_699_999_900)
        let snapshot = AlibabaCodingPlanUsageSnapshot(
            planName: "Lite",
            fiveHourUsedQuota: 70,
            fiveHourTotalQuota: 1200,
            fiveHourNextRefreshTime: stalePrimaryReset,
            weeklyUsedQuota: 80,
            weeklyTotalQuota: 9000,
            weeklyNextRefreshTime: Date(timeIntervalSince1970: 1_700_010_000),
            monthlyUsedQuota: 80,
            monthlyTotalQuota: 18000,
            monthlyNextRefreshTime: Date(timeIntervalSince1970: 1_700_100_000),
            updatedAt: now)

        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.resetsAt == stalePrimaryReset.addingTimeInterval(TimeInterval(5 * 60 * 60)))
    }
}

struct AlibabaCodingPlanUsageParsingTests {
    @Test
    func parses_quota_payload() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        {
          "data": {
            "codingPlanInstanceInfos": [
              { "planName": "Alibaba Coding Plan Pro" }
            ],
            "codingPlanQuotaInfo": {
              "per5HourUsedQuota": 52,
              "per5HourTotalQuota": 1000,
              "per5HourQuotaNextRefreshTime": 1700000300000,
              "perWeekUsedQuota": 800,
              "perWeekTotalQuota": 5000,
              "perWeekQuotaNextRefreshTime": 1700100000000,
              "perBillMonthUsedQuota": 1200,
              "perBillMonthTotalQuota": 20000,
              "perBillMonthQuotaNextRefreshTime": 1701000000000
            }
          },
          "status_code": 0
        }
        """

        let snapshot = try AlibabaCodingPlanUsageFetcher.parseUsageSnapshot(from: Data(json.utf8), now: now)

        #expect(snapshot.planName == "Alibaba Coding Plan Pro")
        #expect(snapshot.fiveHourUsedQuota == 52)
        #expect(snapshot.fiveHourTotalQuota == 1000)
        #expect(snapshot.weeklyTotalQuota == 5000)
        #expect(snapshot.monthlyTotalQuota == 20000)
        #expect(snapshot.fiveHourNextRefreshTime == Date(timeIntervalSince1970: 1_700_000_300))
    }

    @Test
    func multi_instance_quota_payload_uses_selected_active_instance_plan_name() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        {
          "data": {
            "codingPlanInstanceInfos": [
              {
                "planName": "Expired Starter",
                "status": "EXPIRED",
                "endTime": "2025-04-01 17:00",
                "codingPlanQuotaInfo": {
                  "per5HourUsedQuota": 7,
                  "per5HourTotalQuota": 100,
                  "per5HourQuotaNextRefreshTime": 1700000100000
                }
              },
              {
                "planName": "Active Pro",
                "status": "VALID",
                "codingPlanQuotaInfo": {
                  "per5HourUsedQuota": 52,
                  "per5HourTotalQuota": 1000,
                  "per5HourQuotaNextRefreshTime": 1700000300000
                }
              }
            ]
          },
          "status_code": 0
        }
        """

        let snapshot = try AlibabaCodingPlanUsageFetcher.parseUsageSnapshot(from: Data(json.utf8), now: now)

        #expect(snapshot.planName == "Active Pro")
        #expect(snapshot.fiveHourUsedQuota == 52)
        #expect(snapshot.fiveHourTotalQuota == 1000)
        #expect(snapshot.fiveHourNextRefreshTime == Date(timeIntervalSince1970: 1_700_000_300))
    }

    @Test
    func missing_quota_data_without_positive_active_signal_fails() {
        let json = """
        {
          "data": {
            "codingPlanInstanceInfos": [
              { "planName": "Alibaba Coding Plan Pro" }
            ]
          },
          "status_code": 0
        }
        """

        #expect(throws: AlibabaCodingPlanUsageError.self) {
            try AlibabaCodingPlanUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))
        }
    }

    @Test
    func plan_usage_without_positive_active_proof_fails() {
        let json = """
        {
          "data": {
            "codingPlanInstanceInfos": [
              {
                "planName": "Alibaba Coding Plan Pro",
                "planUsage": "18%"
              }
            ]
          },
          "status_code": 0
        }
        """

        #expect(throws: AlibabaCodingPlanUsageError.self) {
            try AlibabaCodingPlanUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))
        }
    }

    @Test
    func parses_wrapped_JSON_string_payload() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let inner = """
        {
          "data": {
            "codingPlanInstanceInfos": [
              {
                "planName": "Coding Plan Lite",
                "status": "VALID",
                "codingPlanQuotaInfo": {
                  "per5HourUsedQuota": 0,
                  "per5HourTotalQuota": 1000,
                  "per5HourQuotaNextRefreshTime": 1700000300000
                }
              }
            ]
          },
          "statusCode": 200
        }
        """
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "  ", with: "")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let wrapped = """
        {
          "successResponse": {
            "body": "\(inner)"
          }
        }
        """

        let snapshot = try AlibabaCodingPlanUsageFetcher.parseUsageSnapshot(from: Data(wrapped.utf8), now: now)

        #expect(snapshot.planName == "Coding Plan Lite")
        #expect(snapshot.fiveHourTotalQuota == 1000)
        #expect(snapshot.fiveHourUsedQuota == 0)
    }

    @Test
    func plan_usage_fallback_stays_visible_but_non_quantitative() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        {
          "data": {
            "codingPlanInstanceInfos": [
              {
                "planName": "Coding Plan Lite",
                "status": "VALID",
                "planUsage": "0%",
                "endTime": "2026-04-01 17:00"
              }
            ]
          },
          "status_code": 0
        }
        """

        let snapshot = try AlibabaCodingPlanUsageFetcher.parseUsageSnapshot(from: Data(json.utf8), now: now)

        #expect(snapshot.planName == "Coding Plan Lite")
        #expect(snapshot.fiveHourUsedQuota == nil)
        #expect(snapshot.fiveHourTotalQuota == nil)
        #expect(snapshot.fiveHourNextRefreshTime == nil)

        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary == nil)
        #expect(usage.loginMethod(for: .alibaba) == "Coding Plan Lite")
    }

    @Test
    func falls_back_to_active_plan_when_quota_and_usage_missing() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        {
          "data": {
            "codingPlanInstanceInfos": [
              {
                "planName": "Coding Plan Lite",
                "status": "VALID",
                "endTime": "2026-04-01 17:00"
              }
            ]
          },
          "status_code": 0
        }
        """

        let snapshot = try AlibabaCodingPlanUsageFetcher.parseUsageSnapshot(from: Data(json.utf8), now: now)

        #expect(snapshot.planName == "Coding Plan Lite")
        #expect(snapshot.fiveHourUsedQuota == nil)
        #expect(snapshot.fiveHourTotalQuota == nil)

        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary == nil)
        #expect(usage.loginMethod(for: .alibaba) == "Coding Plan Lite")
    }

    @Test
    func future_end_time_counts_as_positive_active_signal() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        {
          "data": {
            "codingPlanInstanceInfos": [
              {
                "planName": "Coding Plan Lite",
                "endTime": "2030-04-01 17:00"
              }
            ]
          },
          "status_code": 0
        }
        """

        let snapshot = try AlibabaCodingPlanUsageFetcher.parseUsageSnapshot(from: Data(json.utf8), now: now)

        #expect(snapshot.planName == "Coding Plan Lite")
        #expect(snapshot.fiveHourUsedQuota == nil)
        #expect(snapshot.weeklyTotalQuota == nil)

        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary == nil)
        #expect(usage.loginMethod(for: .alibaba) == "Coding Plan Lite")
    }

    @Test
    func multi_instance_fallback_uses_selected_active_instance_plan_name() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        {
          "data": {
            "codingPlanInstanceInfos": [
              {
                "planName": "Expired Starter",
                "status": "EXPIRED",
                "endTime": "2025-04-01 17:00"
              },
              {
                "planName": "Active Pro",
                "status": "VALID",
                "planUsage": "42%"
              }
            ]
          },
          "status_code": 0
        }
        """

        let snapshot = try AlibabaCodingPlanUsageFetcher.parseUsageSnapshot(from: Data(json.utf8), now: now)

        #expect(snapshot.planName == "Active Pro")
        #expect(snapshot.fiveHourUsedQuota == nil)
        #expect(snapshot.fiveHourTotalQuota == nil)

        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary == nil)
        #expect(usage.loginMethod(for: .alibaba) == "Active Pro")
    }

    @Test
    func active_instance_without_quota_does_not_borrow_quota_from_another_instance() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        {
          "data": {
            "codingPlanInstanceInfos": [
              {
                "planName": "Expired Starter",
                "status": "EXPIRED",
                "endTime": "2025-04-01 17:00",
                "codingPlanQuotaInfo": {
                  "per5HourUsedQuota": 7,
                  "per5HourTotalQuota": 100,
                  "per5HourQuotaNextRefreshTime": 1700000100000
                }
              },
              {
                "planName": "Active Pro",
                "status": "VALID"
              }
            ]
          },
          "status_code": 0
        }
        """

        let snapshot = try AlibabaCodingPlanUsageFetcher.parseUsageSnapshot(from: Data(json.utf8), now: now)

        #expect(snapshot.planName == "Active Pro")
        #expect(snapshot.fiveHourUsedQuota == nil)
        #expect(snapshot.fiveHourTotalQuota == nil)
        #expect(snapshot.fiveHourNextRefreshTime == nil)
    }

    @Test
    func payload_level_active_proof_does_not_label_first_instance_when_no_instance_is_active() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        {
          "data": {
            "status": "VALID",
            "codingPlanInstanceInfos": [
              {
                "planName": "Expired Starter",
                "status": "EXPIRED",
                "endTime": "2025-04-01 17:00"
              },
              {
                "planName": "No Proof Pro"
              }
            ]
          },
          "status_code": 0
        }
        """

        #expect(throws: AlibabaCodingPlanUsageError.self) {
            try AlibabaCodingPlanUsageFetcher.parseUsageSnapshot(from: Data(json.utf8), now: now)
        }
    }

    @Test
    func does_not_fallback_for_inactive_plan_without_quota() {
        let json = """
        {
          "data": {
            "codingPlanInstanceInfos": [
              {
                "planName": "Coding Plan Lite",
                "status": "EXPIRED"
              }
            ]
          },
          "status_code": 0
        }
        """

        #expect(throws: AlibabaCodingPlanUsageError.self) {
            try AlibabaCodingPlanUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))
        }
    }

    @Test
    func console_need_login_payload_maps_to_login_required() {
        let json = """
        {
          "code": "ConsoleNeedLogin",
          "message": "You need to log in.",
          "requestId": "abc",
          "successResponse": false
        }
        """

        #expect(throws: AlibabaCodingPlanUsageError.loginRequired) {
            try AlibabaCodingPlanUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))
        }
    }

    @Test
    func console_need_login_payload_maps_to_unavailable_API_key_mode() {
        let json = """
        {
          "code": "ConsoleNeedLogin",
          "message": "You need to log in.",
          "requestId": "abc",
          "successResponse": false
        }
        """

        #expect(throws: AlibabaCodingPlanUsageError.apiKeyUnavailableInRegion) {
            try AlibabaCodingPlanUsageFetcher.parseUsageSnapshot(
                from: Data(json.utf8),
                authMode: .apiKey)
        }
    }
}

@Suite(.serialized)
struct AlibabaCodingPlanFallbackTests {
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
        sourceMode: ProviderSourceMode,
        settings: ProviderSettingsSnapshot? = nil,
        env: [String: String] = [:]) -> ProviderFetchContext
    {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        return ProviderFetchContext(
            runtime: .cli,
            sourceMode: sourceMode,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: settings,
            fetcher: UsageFetcher(environment: env),
            claudeFetcher: StubClaudeFetcher(),
            browserDetection: browserDetection)
    }

    @Test
    func falls_back_on_TLS_failure_in_auto_mode() {
        let strategy = AlibabaCodingPlanWebFetchStrategy()
        let context = self.makeContext(sourceMode: .auto)
        #expect(strategy.shouldFallback(on: URLError(.secureConnectionFailed), context: context))
    }

    @Test
    func does_not_fallback_on_TLS_failure_when_source_forced_to_web() {
        let strategy = AlibabaCodingPlanWebFetchStrategy()
        let context = self.makeContext(sourceMode: .web)
        #expect(strategy.shouldFallback(on: URLError(.secureConnectionFailed), context: context) == false)
    }

    @Test
    func auto_mode_does_not_borrow_manual_cookie_authority_when_browser_import_fails() throws {
        let strategy = AlibabaCodingPlanWebFetchStrategy()
        let settings = ProviderSettingsSnapshot.make(
            alibaba: ProviderSettingsSnapshot.AlibabaCodingPlanProviderSettings(
                cookieSource: .auto,
                manualCookieHeader: "session=manual-cookie",
                apiRegion: .international))
        let context = self.makeContext(sourceMode: .auto, settings: settings)

        CookieHeaderCache.clear(provider: .alibaba)
        try AlibabaCodingPlanCookieImporter.withImportSessionOverrideForTesting { _, _ in
            throw AlibabaCodingPlanSettingsError.missingCookie()
        } operation: {
            do {
                _ = try AlibabaCodingPlanWebFetchStrategy.resolveCookieHeader(context: context, allowCached: false)
                Issue.record("Expected auto mode to fail instead of borrowing the manual cookie header")
            } catch let error as AlibabaCodingPlanSettingsError {
                guard case .missingCookie = error else {
                    Issue.record("Expected missingCookie, got \(error)")
                    return
                }
                #expect(strategy.shouldFallback(on: error, context: context))
            } catch {
                Issue.record("Expected AlibabaCodingPlanSettingsError, got \(error)")
            }
        }
    }

    @Test
    func auto_mode_skips_web_when_no_alibaba_session_is_available() async throws {
        let strategy = AlibabaCodingPlanWebFetchStrategy()
        let settings = ProviderSettingsSnapshot.make(
            alibaba: ProviderSettingsSnapshot.AlibabaCodingPlanProviderSettings(
                cookieSource: .auto,
                manualCookieHeader: nil,
                apiRegion: .international))
        let context = self.makeContext(
            sourceMode: .auto,
            settings: settings,
            env: [AlibabaCodingPlanSettingsReader.apiTokenKey: "token-abc"])

        CookieHeaderCache.clear(provider: .alibaba)
        try await AlibabaCodingPlanCookieImporter.withImportSessionOverrideForTesting { _, _ in
            throw AlibabaCodingPlanSettingsError.missingCookie()
        } operation: {
            #expect(await strategy.isAvailable(context) == false)
        }
    }
}

struct AlibabaCodingPlanRegionTests {
    @Test
    func defaults_to_international_endpoint() {
        let url = AlibabaCodingPlanUsageFetcher.resolveQuotaURL(region: .international, environment: [:])
        #expect(url.host == "modelstudio.console.alibabacloud.com")
        #expect(url.path == "/data/api.json")
    }

    @Test
    func uses_china_mainland_host() {
        let url = AlibabaCodingPlanUsageFetcher.resolveQuotaURL(region: .chinaMainland, environment: [:])
        #expect(url.host == "bailian.console.aliyun.com")
    }

    @Test
    func host_override_wins_for_quota_URL() {
        let env = [AlibabaCodingPlanSettingsReader.hostKey: "custom.aliyun.com"]
        let url = AlibabaCodingPlanUsageFetcher.resolveQuotaURL(region: .international, environment: env)
        #expect(url.host == "custom.aliyun.com")
        #expect(url.path == "/data/api.json")
    }

    @Test
    func host_override_uses_selected_region_for_quota_URL() {
        let env = [AlibabaCodingPlanSettingsReader.hostKey: "custom.aliyun.com"]
        let url = AlibabaCodingPlanUsageFetcher.resolveQuotaURL(region: .chinaMainland, environment: env)
        #expect(url.host == "custom.aliyun.com")

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let currentRegion = components?.queryItems?.first(where: { $0.name == "currentRegionId" })?.value
        #expect(currentRegion == AlibabaCodingPlanAPIRegion.chinaMainland.currentRegionID)
    }

    @Test
    func bare_host_override_builds_console_dashboard_URL() {
        let env = [AlibabaCodingPlanSettingsReader.hostKey: "custom.aliyun.com"]
        let url = AlibabaCodingPlanUsageFetcher.resolveConsoleDashboardURL(region: .international, environment: env)
        #expect(url.scheme == "https")
        #expect(url.host == "custom.aliyun.com")
        #expect(url.path == AlibabaCodingPlanAPIRegion.international.dashboardURL.path)

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let tab = components?.queryItems?.first(where: { $0.name == "tab" })?.value
        #expect(tab == "coding-plan")
    }

    @Test
    func quota_url_override_beats_host() {
        let env = [
            AlibabaCodingPlanSettingsReader.quotaURLKey:
                "https://modelstudio.console.alibabacloud.com/custom/quota",
        ]
        let url = AlibabaCodingPlanUsageFetcher.resolveQuotaURL(region: .international, environment: env)
        #expect(url.absoluteString == "https://modelstudio.console.alibabacloud.com/custom/quota")
    }

    @Test
    func custom_quota_url_override_is_preserved_by_default() {
        let env = [AlibabaCodingPlanSettingsReader.quotaURLKey: "https://attacker.example/custom/quota"]
        let url = AlibabaCodingPlanUsageFetcher.resolveQuotaURL(region: .international, environment: env)
        #expect(url.host == "attacker.example")
    }

    @Test
    func strict_provider_endpoint_mode_falls_back_to_provider_endpoint() {
        let env = [
            AlibabaCodingPlanSettingsReader.requireProviderEndpointOverridesKey: "true",
            AlibabaCodingPlanSettingsReader.quotaURLKey: "https://attacker.example/custom/quota",
        ]
        let url = AlibabaCodingPlanUsageFetcher.resolveQuotaURL(region: .international, environment: env)
        #expect(url.host == AlibabaCodingPlanAPIRegion.international.quotaURL.host)
    }

    @Test
    func explicit_endpoint_override_rejects_invalid_api_scheme_before_network() async {
        await #expect(throws: ProviderEndpointOverrideError.alibabaCodingPlan(
            AlibabaCodingPlanSettingsReader.quotaURLKey))
        {
            _ = try await AlibabaCodingPlanUsageFetcher.fetchUsage(
                apiKey: "cpk-test",
                environment: [AlibabaCodingPlanSettingsReader
                    .quotaURLKey: "http://modelstudio.console.alibabacloud.com/custom/quota"])
        }
    }

    @Test
    func explicit_endpoint_override_rejects_invalid_cookie_scheme_before_network() async {
        await #expect(throws: ProviderEndpointOverrideError.alibabaCodingPlan(
            AlibabaCodingPlanSettingsReader.quotaURLKey))
        {
            _ = try await AlibabaCodingPlanUsageFetcher.fetchUsage(
                cookieHeader: "login_aliyunid_ticket=ticket; login_aliyunid_pk=user",
                environment: [AlibabaCodingPlanSettingsReader
                    .quotaURLKey: "http://modelstudio.console.alibabacloud.com/custom/quota"])
        }
    }
}

@Suite(.serialized)
struct AlibabaCodingPlanUsageFetcherRequestTests {
    @Test
    func api401_maps_to_invalid_credentials() async throws {
        let transport = ProviderHTTPTransportHandler { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let (response, data) = Self.makeResponse(
                url: url,
                body: #"{"message":"unauthorized"}"#,
                statusCode: 401)
            return (data, response)
        }

        await #expect(throws: AlibabaCodingPlanUsageError.invalidCredentials) {
            _ = try await AlibabaCodingPlanUsageFetcher.fetchUsage(
                apiKey: "cpk-test",
                region: .chinaMainland,
                environment: [
                    AlibabaCodingPlanSettingsReader.quotaURLKey: "https://bailian.console.aliyun.com/data/api.json",
                ],
                transport: transport)
        }
    }

    @Test
    func cookie_SEC_token_fallback_survives_user_info_request_failure() async throws {
        let registered = URLProtocol.registerClass(AlibabaConsoleSECTokenStubURLProtocol.self)
        defer {
            if registered {
                URLProtocol.unregisterClass(AlibabaConsoleSECTokenStubURLProtocol.self)
            }
            AlibabaConsoleSECTokenStubURLProtocol.handler = nil
        }

        AlibabaConsoleSECTokenStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }

            if url.host == "modelstudio.console.alibabacloud.com", request.httpMethod == "GET" {
                return Self.makeResponse(url: url, body: "<html></html>", statusCode: 200)
            }

            if url.host == "modelstudio.console.alibabacloud.com", url.path == "/tool/user/info.json" {
                throw URLError(.timedOut)
            }

            if url.host == "bailian-singapore-cs.alibabacloud.com", request.httpMethod == "POST" {
                let body = Self.requestBodyString(from: request)
                #expect(body.contains("sec_token=cookie-sec-token"))
                let json = """
                {
                  "data": {
                    "codingPlanInstanceInfos": [
                      { "planName": "Alibaba Coding Plan Pro", "status": "VALID" }
                    ],
                    "codingPlanQuotaInfo": {
                      "per5HourUsedQuota": 52,
                      "per5HourTotalQuota": 1000,
                      "per5HourQuotaNextRefreshTime": 1700000300000
                    }
                  },
                  "status_code": 0
                }
                """
                return Self.makeResponse(url: url, body: json, statusCode: 200)
            }

            throw URLError(.unsupportedURL)
        }

        let snapshot = try await AlibabaCodingPlanUsageFetcher.fetchUsage(
            cookieHeader: "sec_token=cookie-sec-token; login_aliyunid_ticket=ticket; login_aliyunid_pk=user",
            region: .international,
            environment: [:],
            now: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(snapshot.planName == "Alibaba Coding Plan Pro")
        #expect(snapshot.fiveHourUsedQuota == 52)
        #expect(snapshot.fiveHourTotalQuota == 1000)
    }

    @Test
    func host_override_applies_to_user_info_SEC_token_fallback() async throws {
        let registered = URLProtocol.registerClass(AlibabaConsoleSECTokenStubURLProtocol.self)
        defer {
            if registered {
                URLProtocol.unregisterClass(AlibabaConsoleSECTokenStubURLProtocol.self)
            }
            AlibabaConsoleSECTokenStubURLProtocol.handler = nil
        }

        AlibabaConsoleSECTokenStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            #expect(url.host == "modelstudio.console.alibabacloud.com")

            if request.httpMethod == "GET", url.path == AlibabaCodingPlanAPIRegion.international.dashboardURL.path {
                return Self.makeResponse(url: url, body: "<html></html>", statusCode: 200)
            }

            if request.httpMethod == "GET", url.path == "/tool/user/info.json" {
                return Self.makeResponse(
                    url: url,
                    body: #"{"data":{"secToken":"override-sec-token"}}"#,
                    statusCode: 200)
            }

            if request.httpMethod == "POST", url.path == "/data/api.json" {
                let body = Self.requestBodyString(from: request)
                #expect(body.contains("sec_token=override-sec-token"))
                let json = """
                {
                  "data": {
                    "codingPlanInstanceInfos": [
                      { "planName": "Alibaba Coding Plan Pro", "status": "VALID" }
                    ],
                    "codingPlanQuotaInfo": {
                      "per5HourUsedQuota": 21,
                      "per5HourTotalQuota": 1000,
                      "per5HourQuotaNextRefreshTime": 1700000300000
                    }
                  },
                  "status_code": 0
                }
                """
                return Self.makeResponse(url: url, body: json, statusCode: 200)
            }

            throw URLError(.unsupportedURL)
        }

        let snapshot = try await AlibabaCodingPlanUsageFetcher.fetchUsage(
            cookieHeader: "sec_token=cookie-sec-token; login_aliyunid_ticket=ticket; login_aliyunid_pk=user",
            region: .international,
            environment: [AlibabaCodingPlanSettingsReader.hostKey: "https://modelstudio.console.alibabacloud.com"],
            now: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(snapshot.planName == "Alibaba Coding Plan Pro")
        #expect(snapshot.fiveHourUsedQuota == 21)
        #expect(snapshot.fiveHourTotalQuota == 1000)
    }

    @Test
    func console_request_body_uses_region_specific_metadata() async throws {
        let registered = URLProtocol.registerClass(AlibabaConsoleSECTokenStubURLProtocol.self)
        defer {
            if registered {
                URLProtocol.unregisterClass(AlibabaConsoleSECTokenStubURLProtocol.self)
            }
            AlibabaConsoleSECTokenStubURLProtocol.handler = nil
        }

        AlibabaConsoleSECTokenStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }

            if request.httpMethod == "GET", url.path == AlibabaCodingPlanAPIRegion.chinaMainland.dashboardURL.path {
                return Self.makeResponse(url: url, body: "<html></html>", statusCode: 200)
            }

            if request.httpMethod == "GET", url.path == "/tool/user/info.json" {
                return Self.makeResponse(url: url, body: #"{"data":{"secToken":"cn-sec-token"}}"#, statusCode: 200)
            }

            if request.httpMethod == "POST", url.path == "/data/api.json" {
                let body = Self.requestBodyString(from: request)
                let params = try #require(Self.requestParamsDictionary(from: body))
                let data = try #require(params["Data"] as? [String: Any])
                let cornerstone = try #require(data["cornerstoneParam"] as? [String: Any])
                #expect(cornerstone["domain"] as? String == AlibabaCodingPlanAPIRegion.chinaMainland.consoleDomain)
                #expect(cornerstone["consoleSite"] as? String == AlibabaCodingPlanAPIRegion.chinaMainland.consoleSite)
                #expect(
                    cornerstone["feURL"] as? String
                        == AlibabaCodingPlanAPIRegion.chinaMainland.dashboardURL.absoluteString)

                let json = """
                {
                  "data": {
                    "codingPlanInstanceInfos": [
                      { "planName": "Alibaba Coding Plan Pro", "status": "VALID" }
                    ],
                    "codingPlanQuotaInfo": {
                      "per5HourUsedQuota": 21,
                      "per5HourTotalQuota": 1000,
                      "per5HourQuotaNextRefreshTime": 1700000300000
                    }
                  },
                  "status_code": 0
                }
                """
                return Self.makeResponse(url: url, body: json, statusCode: 200)
            }

            throw URLError(.unsupportedURL)
        }

        let snapshot = try await AlibabaCodingPlanUsageFetcher.fetchUsage(
            cookieHeader: "sec_token=cookie-sec-token; login_aliyunid_ticket=ticket; login_aliyunid_pk=user",
            region: .chinaMainland,
            environment: [:],
            now: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(snapshot.planName == "Alibaba Coding Plan Pro")
        #expect(snapshot.fiveHourUsedQuota == 21)
        #expect(snapshot.fiveHourTotalQuota == 1000)
    }

    private static func makeResponse(url: URL, body: String, statusCode: Int) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        return (response, Data(body.utf8))
    }

    private static func requestBodyString(from request: URLRequest) -> String {
        if let data = request.httpBody {
            return String(data: data, encoding: .utf8) ?? ""
        }

        guard let stream = request.httpBodyStream else {
            return ""
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func requestParamsDictionary(from body: String) -> [String: Any]? {
        guard let components = URLComponents(string: "https://example.invalid/?\(body)"),
              let params = components.queryItems?.first(where: { $0.name == "params" })?.value,
              let data = params.data(using: .utf8)
        else {
            return nil
        }

        let object = try? JSONSerialization.jsonObject(with: data, options: [])
        return object as? [String: Any]
    }
}

final class AlibabaUsageFetcherStubURLProtocol: URLProtocol {
    private static let _handlerBox = LockIsolated<((URLRequest) throws -> (HTTPURLResponse, Data))?>(nil)
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { Self._handlerBox.value }
        set { Self._handlerBox.setValue(newValue) }
    }

    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "bailian.console.aliyun.com"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
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

final class AlibabaConsoleSECTokenStubURLProtocol: URLProtocol {
    private static let _handlerBox = LockIsolated<((URLRequest) throws -> (HTTPURLResponse, Data))?>(nil)
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { Self._handlerBox.value }
        set { Self._handlerBox.setValue(newValue) }
    }

    override static func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return [
            "modelstudio.console.alibabacloud.com",
            "bailian-singapore-cs.alibabacloud.com",
            "bailian.console.aliyun.com",
            "bailian-cs.console.aliyun.com",
            "bailian-beijing-cs.aliyuncs.com",
        ].contains(host)
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
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
