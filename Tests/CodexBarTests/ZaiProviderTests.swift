import Foundation
import Testing
@testable import CodexBarCore

struct ZaiSettingsReaderTests {
    @Test
    func api_token_reads_from_environment() {
        let token = ZaiSettingsReader.apiToken(environment: ["Z_AI_API_KEY": "abc123"])
        #expect(token == "abc123")
    }

    @Test
    func api_token_strips_quotes() {
        let token = ZaiSettingsReader.apiToken(environment: ["Z_AI_API_KEY": "\"token-xyz\""])
        #expect(token == "token-xyz")
    }

    @Test
    func api_host_reads_from_environment() {
        let host = ZaiSettingsReader.apiHost(environment: [ZaiSettingsReader.apiHostKey: " open.bigmodel.cn "])
        #expect(host == "open.bigmodel.cn")
    }

    @Test
    func quota_URL_infers_scheme() {
        let url = ZaiSettingsReader
            .quotaURL(environment: [ZaiSettingsReader.quotaURLKey: "open.bigmodel.cn/api/coding"])
        #expect(url?.absoluteString == "https://open.bigmodel.cn/api/coding")
    }

    @Test
    func endpoint_override_validation_accepts_HTTPS_and_bare_hosts() throws {
        try ZaiSettingsReader.validateEndpointOverrides(environment: [
            ZaiSettingsReader.quotaURLKey: "https://open.bigmodel.cn/api/coding",
        ])
        try ZaiSettingsReader.validateEndpointOverrides(environment: [
            ZaiSettingsReader.apiHostKey: "open.bigmodel.cn",
        ])
    }

    @Test
    func endpoint_override_validation_rejects_insecure_URLs() {
        #expect(throws: ZaiSettingsError.invalidEndpointOverride(ZaiSettingsReader.quotaURLKey)) {
            try ZaiSettingsReader.validateEndpointOverrides(environment: [
                ZaiSettingsReader.quotaURLKey: "http://attacker.test/quota",
            ])
        }
        #expect(throws: ZaiSettingsError.invalidEndpointOverride(ZaiSettingsReader.apiHostKey)) {
            try ZaiSettingsReader.validateEndpointOverrides(environment: [
                ZaiSettingsReader.apiHostKey: "http://attacker.test",
            ])
        }
    }
}

struct ZaiUsageSnapshotTests {
    @Test
    func maps_usage_snapshot_windows() {
        let reset = Date(timeIntervalSince1970: 123)
        let tokenLimit = ZaiLimitEntry(
            type: .tokensLimit,
            unit: .hours,
            number: 5,
            usage: 100,
            currentValue: 20,
            remaining: 80,
            percentage: 25,
            usageDetails: [],
            nextResetTime: reset)
        let timeLimit = ZaiLimitEntry(
            type: .timeLimit,
            unit: .days,
            number: 30,
            usage: 200,
            currentValue: 40,
            remaining: 160,
            percentage: 50,
            usageDetails: [],
            nextResetTime: nil)
        let snapshot = ZaiUsageSnapshot(
            tokenLimit: tokenLimit,
            timeLimit: timeLimit,
            planName: nil,
            updatedAt: reset)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 20)
        #expect(usage.primary?.windowMinutes == 300)
        #expect(usage.primary?.resetsAt == reset)
        #expect(usage.primary?.resetDescription == "5 hours window")
        #expect(usage.secondary?.usedPercent == 20)
        #expect(usage.secondary?.resetDescription == "30 days window")
        #expect(usage.tertiary == nil)
        #expect(usage.zaiUsage?.tokenLimit?.usage == 100)
        #expect(usage.zaiUsage?.sessionTokenLimit == nil)
    }

    @Test
    func maps_usage_snapshot_windows_with_missing_fields() {
        let reset = Date(timeIntervalSince1970: 123)
        let tokenLimit = ZaiLimitEntry(
            type: .tokensLimit,
            unit: .hours,
            number: 5,
            usage: nil,
            currentValue: nil,
            remaining: nil,
            percentage: 25,
            usageDetails: [],
            nextResetTime: reset)
        let snapshot = ZaiUsageSnapshot(
            tokenLimit: tokenLimit,
            timeLimit: nil,
            planName: nil,
            updatedAt: reset)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 25)
        #expect(usage.primary?.windowMinutes == 300)
        #expect(usage.primary?.resetsAt == reset)
        #expect(usage.primary?.resetDescription == "5 hours window")
        #expect(usage.zaiUsage?.tokenLimit?.usage == nil)
    }

    @Test
    func maps_usage_snapshot_windows_with_missing_remaining_uses_current_value() {
        let reset = Date(timeIntervalSince1970: 123)
        let tokenLimit = ZaiLimitEntry(
            type: .tokensLimit,
            unit: .hours,
            number: 5,
            usage: 100,
            currentValue: 20,
            remaining: nil,
            percentage: 25,
            usageDetails: [],
            nextResetTime: reset)
        let snapshot = ZaiUsageSnapshot(
            tokenLimit: tokenLimit,
            timeLimit: nil,
            planName: nil,
            updatedAt: reset)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 20)
    }

    @Test
    func maps_usage_snapshot_windows_with_missing_current_value_uses_remaining() {
        let reset = Date(timeIntervalSince1970: 123)
        let tokenLimit = ZaiLimitEntry(
            type: .tokensLimit,
            unit: .hours,
            number: 5,
            usage: 100,
            currentValue: nil,
            remaining: 80,
            percentage: 25,
            usageDetails: [],
            nextResetTime: reset)
        let snapshot = ZaiUsageSnapshot(
            tokenLimit: tokenLimit,
            timeLimit: nil,
            planName: nil,
            updatedAt: reset)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 20)
    }

    @Test
    func maps_usage_snapshot_windows_with_missing_remaining_and_current_value_falls_back_to_percentage() {
        let reset = Date(timeIntervalSince1970: 123)
        let tokenLimit = ZaiLimitEntry(
            type: .tokensLimit,
            unit: .hours,
            number: 5,
            usage: 100,
            currentValue: nil,
            remaining: nil,
            percentage: 25,
            usageDetails: [],
            nextResetTime: reset)
        let snapshot = ZaiUsageSnapshot(
            tokenLimit: tokenLimit,
            timeLimit: nil,
            planName: nil,
            updatedAt: reset)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 25)
    }
}

struct ZaiUsageParsingTests {
    @Test
    func empty_body_returns_parse_failed() {
        do {
            _ = try ZaiUsageFetcher.parseUsageSnapshot(from: Data())
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case let ZaiUsageError.parseFailed(message) = error else { return false }
                return message == "Empty response body"
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func parses_usage_response() throws {
        let json = """
        {
          "code": 200,
          "msg": "Operation successful",
          "data": {
            "limits": [
              {
                "type": "TIME_LIMIT",
                "unit": 5,
                "number": 1,
                "usage": 100,
                "currentValue": 102,
                "remaining": 0,
                "percentage": 100,
                "usageDetails": [
                  { "modelCode": "search-prime", "usage": 95 }
                ]
              },
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "number": 5,
                "usage": 40000000,
                "currentValue": 13628365,
                "remaining": 26371635,
                "percentage": 34,
                "nextResetTime": 1768507567547
              }
            ],
            "planName": "Pro"
          },
          "success": true
        }
        """

        let snapshot = try ZaiUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))

        #expect(snapshot.planName == "Pro")
        #expect(snapshot.tokenLimit?.usage == 40_000_000)
        #expect(snapshot.timeLimit?.usageDetails.first?.modelCode == "search-prime")
        #expect(snapshot.tokenLimit?.percentage == 34.0)

        let usage = snapshot.toUsageSnapshot()
        #expect(usage.secondary?.windowMinutes == nil)
        #expect(usage.secondary?.resetDescription == "Monthly")
    }

    @Test
    func zai_mcp_time_limit_displays_monthly_instead_of_one_minute_window() throws {
        let json = """
        {
          "code": 200,
          "msg": "Operation successful",
          "data": {
            "limits": [
              {
                "type": "TIME_LIMIT",
                "unit": 5,
                "number": 1,
                "usage": 100,
                "currentValue": 50,
                "remaining": 50,
                "percentage": 50,
                "usageDetails": []
              },
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "number": 5,
                "percentage": 34,
                "nextResetTime": 1768507567547
              }
            ]
          },
          "success": true
        }
        """

        let snapshot = try ZaiUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))
        let usage = snapshot.toUsageSnapshot()

        #expect(snapshot.timeLimit?.windowDescription == "1 minute")
        #expect(usage.secondary?.windowMinutes == nil)
        #expect(usage.secondary?.resetDescription == "Monthly")
    }

    @Test
    func missing_data_returns_api_error() {
        let json = """
        { "code": 1001, "msg": "Authorization Token Missing", "success": false }
        """

        do {
            _ = try ZaiUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case let ZaiUsageError.apiError(message) = error else { return false }
                return message == "Authorization Token Missing"
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func failed_response_without_message_reports_the_API_code() {
        let json = """
        { "code": 1001, "success": false }
        """

        do {
            _ = try ZaiUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case let ZaiUsageError.apiError(message) = error else { return false }
                return message == "Z.ai quota API returned code 1001"
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func success_without_data_returns_parse_failed() {
        let json = """
        { "code": 200, "msg": "Operation successful", "success": true }
        """

        do {
            _ = try ZaiUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case let ZaiUsageError.parseFailed(message) = error else { return false }
                return message == "Missing data"
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func success_without_limits_parses_empty_usage() throws {
        let json = """
        {
          "code": 200,
          "msg": "Operation successful",
          "data": { "planName": "Pro" },
          "success": true
        }
        """

        let snapshot = try ZaiUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))

        #expect(snapshot.planName == "Pro")
        #expect(snapshot.tokenLimit == nil)
        #expect(snapshot.timeLimit == nil)
    }

    @Test
    func parses_new_schema_with_missing_token_limit_fields() throws {
        let json = """
        {
          "code": 200,
          "msg": "Operation successful",
          "data": {
            "limits": [
              {
                "type": "TIME_LIMIT",
                "unit": 5,
                "number": 1,
                "usage": 100,
                "currentValue": 0,
                "remaining": 100,
                "percentage": 0,
                "usageDetails": [
                  { "modelCode": "search-prime", "usage": 0 },
                  { "modelCode": "web-reader", "usage": 1 },
                  { "modelCode": "zread", "usage": 0 }
                ]
              },
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "number": 5,
                "percentage": 1,
                "nextResetTime": 1770724088678
              }
            ]
          },
          "success": true
        }
        """

        let snapshot = try ZaiUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))

        #expect(snapshot.tokenLimit?.percentage == 1.0)
        #expect(snapshot.tokenLimit?.usage == nil)
        #expect(snapshot.tokenLimit?.currentValue == nil)
        #expect(snapshot.tokenLimit?.remaining == nil)
        #expect(snapshot.tokenLimit?.usedPercent == 1.0)
        #expect(snapshot.tokenLimit?.windowMinutes == 300)
        #expect(snapshot.timeLimit?.usage == 100)
    }

    @Test
    func parses_BigModel_CN_quota_response_without_message() throws {
        let json = """
        {
          "code": 200,
          "data": {
            "limits": [
              {
                "type": "TIME_LIMIT",
                "unit": 5,
                "number": 1,
                "usage": 1000,
                "currentValue": 147,
                "remaining": 853,
                "percentage": 14,
                "nextResetTime": 1784706344993,
                "usageDetails": [
                  { "modelCode": "search-prime", "usage": 84 },
                  { "modelCode": "web-reader", "usage": 41 },
                  { "modelCode": "zread", "usage": 8 }
                ]
              },
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "number": 5,
                "percentage": 8,
                "nextResetTime": 1783049703178
              },
              {
                "type": "TOKENS_LIMIT",
                "unit": 6,
                "number": 1,
                "percentage": 7,
                "nextResetTime": 1783496744998
              }
            ],
            "level": "pro"
          },
          "success": true
        }
        """

        let snapshot = try ZaiUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))
        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 7)
        #expect(usage.secondary?.usedPercent == 14.7)
        #expect(usage.tertiary?.usedPercent == 8)
    }
}

struct ZaiBigModelTeamScopeTests {
    @Test
    func team_scope_appends_type_2_and_sends_BigModel_project_headers() async throws {
        let transport = ProviderHTTPTransportStub { request in
            let json = """
            {
              "code": 200,
              "msg": "操作成功",
              "data": {
                "level": "pro",
                "limits": [
                  {
                    "type": "TIME_LIMIT",
                    "unit": 5,
                    "number": 1,
                    "usage": 1000,
                    "currentValue": 224,
                    "remaining": 776,
                    "percentage": 22,
                    "nextResetTime": 1777575229998,
                    "usageDetails": []
                  },
                  {
                    "type": "TOKENS_LIMIT",
                    "unit": 3,
                    "number": 5,
                    "percentage": 25,
                    "nextResetTime": 1775020168897
                  },
                  {
                    "type": "TOKENS_LIMIT",
                    "unit": 6,
                    "number": 1,
                    "percentage": 9,
                    "nextResetTime": 1775588029998
                  }
                ]
              },
              "success": true
            }
            """
            return (
                Data(json.utf8),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil)!)
        }

        let snapshot = try await ZaiUsageFetcher.fetchUsage(
            apiKey: "zai-test-token",
            region: .bigmodelCN,
            usageScope: .team,
            teamContext: ZaiBigModelTeamContext(
                organizationID: "org-test",
                projectID: "proj-test"),
            environment: [:],
            transport: transport)

        let requests = await transport.requests()
        let request = try #require(requests.first)

        #expect(request.url?.absoluteString == "https://open.bigmodel.cn/api/monitor/usage/quota/limit?type=2")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer zai-test-token")
        #expect(request.value(forHTTPHeaderField: "Bigmodel-Organization") == "org-test")
        #expect(request.value(forHTTPHeaderField: "Bigmodel-Project") == "proj-test")
        #expect(snapshot.tokenLimit?.unit == .weeks)
        #expect(snapshot.sessionTokenLimit?.unit == .hours)
        #expect(snapshot.timeLimit?.usage == 1000)
    }

    @Test
    func personal_scope_keeps_existing_quota_URL_and_omits_team_headers() async throws {
        let transport = ProviderHTTPTransportStub { request in
            let json = """
            {
              "code": 200,
              "msg": "Operation successful",
              "data": {
                "limits": [
                  {
                    "type": "TOKENS_LIMIT",
                    "unit": 3,
                    "number": 5,
                    "percentage": 34,
                    "nextResetTime": 1768507567547
                  }
                ]
              },
              "success": true
            }
            """
            return (
                Data(json.utf8),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil)!)
        }

        _ = try await ZaiUsageFetcher.fetchUsage(
            apiKey: "zai-test-token",
            region: .bigmodelCN,
            usageScope: .personal,
            teamContext: ZaiBigModelTeamContext(
                organizationID: "org-test",
                projectID: "proj-test"),
            environment: [:],
            transport: transport)

        let requests = await transport.requests()
        let request = try #require(requests.first)

        #expect(request.url?.absoluteString == "https://open.bigmodel.cn/api/monitor/usage/quota/limit")
        #expect(request.value(forHTTPHeaderField: "Bigmodel-Organization") == nil)
        #expect(request.value(forHTTPHeaderField: "Bigmodel-Project") == nil)
    }

    @Test
    func team_scope_requires_complete_BigModel_context() async {
        let transport = ProviderHTTPTransportStub { request in
            (
                Data(),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil)!)
        }

        await self.expectMissingTeamContext {
            _ = try await ZaiUsageFetcher.fetchUsage(
                apiKey: "zai-test-token",
                region: .bigmodelCN,
                usageScope: .team,
                teamContext: nil,
                environment: [:],
                transport: transport)
        }

        let requests = await transport.requests()
        #expect(requests.isEmpty)

        await self.expectMissingTeamContext {
            _ = try await ZaiUsageFetcher.fetchUsage(
                apiKey: "zai-test-token",
                region: .bigmodelCN,
                usageScope: .team,
                teamContext: nil,
                environment: [ZaiSettingsReader.bigModelOrganizationKey: "org-only"],
                transport: transport)
        }

        await self.expectMissingTeamContext {
            _ = try await ZaiUsageFetcher.fetchUsage(
                apiKey: "zai-test-token",
                region: .bigmodelCN,
                usageScope: .team,
                teamContext: nil,
                environment: [ZaiSettingsReader.bigModelProjectKey: "proj-only"],
                transport: transport)
        }
    }

    @Test
    func team_model_usage_appends_type_3_and_sends_BigModel_project_headers() async throws {
        let transport = ProviderHTTPTransportStub { request in
            let json = """
            {
              "code": 200,
              "msg": "success",
              "success": true,
              "data": {
                "x_time": ["2026-06-21 08:00"],
                "modelDataList": [
                  { "modelName": "glm-4.6", "tokensUsage": [100] }
                ]
              }
            }
            """
            return (
                Data(json.utf8),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil)!)
        }

        let usage = try await ZaiUsageFetcher.fetchModelUsage(
            apiKey: "zai-test-token",
            region: .bigmodelCN,
            usageScope: .team,
            teamContext: ZaiBigModelTeamContext(
                organizationID: "org-test",
                projectID: "proj-test"),
            environment: [:],
            transport: transport)

        let requests = await transport.requests()
        let request = try #require(requests.first)
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))

        #expect(components.path == "/api/monitor/usage/model-usage")
        #expect(components.queryItems?.first { $0.name == "type" }?.value == "3")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer zai-test-token")
        #expect(request.value(forHTTPHeaderField: "Bigmodel-Organization") == "org-test")
        #expect(request.value(forHTTPHeaderField: "Bigmodel-Project") == "proj-test")
        #expect(usage.modelNames == ["glm-4.6"])
    }

    @Test
    func team_quota_rejects_insecure_override_before_sending_credentials() async throws {
        let transport = ProviderHTTPTransportStub { request in
            Issue.record("Unexpected z.ai team quota request to \(request.url?.absoluteString ?? "<nil>")")
            throw URLError(.badURL)
        }

        await #expect(throws: ZaiSettingsError.invalidEndpointOverride(ZaiSettingsReader.quotaURLKey)) {
            try await ZaiUsageFetcher.fetchUsage(
                apiKey: "zai-test-token",
                region: .bigmodelCN,
                usageScope: .team,
                teamContext: ZaiBigModelTeamContext(
                    organizationID: "org-test",
                    projectID: "proj-test"),
                environment: [ZaiSettingsReader.quotaURLKey: "http://attacker.test/quota"],
                transport: transport)
        }

        let requests = await transport.requests()
        #expect(requests.isEmpty)
    }

    @Test
    func team_model_usage_rejects_insecure_API_host_before_sending_credentials() async throws {
        let transport = ProviderHTTPTransportStub { request in
            Issue.record("Unexpected z.ai team model usage request to \(request.url?.absoluteString ?? "<nil>")")
            throw URLError(.badURL)
        }

        await #expect(throws: ZaiSettingsError.invalidEndpointOverride(ZaiSettingsReader.apiHostKey)) {
            try await ZaiUsageFetcher.fetchModelUsage(
                apiKey: "zai-test-token",
                region: .bigmodelCN,
                usageScope: .team,
                teamContext: ZaiBigModelTeamContext(
                    organizationID: "org-test",
                    projectID: "proj-test"),
                environment: [ZaiSettingsReader.apiHostKey: "http://attacker.test"],
                transport: transport)
        }

        let requests = await transport.requests()
        #expect(requests.isEmpty)
    }

    private func expectMissingTeamContext(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            Issue.record("Expected z.ai missing team context error.")
        } catch ZaiUsageError.missingTeamContext {
            // Expected.
        } catch {
            Issue.record("Expected z.ai missing team context error, got \(error).")
        }
    }

    @Test
    func team_context_can_be_resolved_from_environment() {
        let env = [
            ZaiSettingsReader.bigModelOrganizationKey: " org-env ",
            ZaiSettingsReader.bigModelProjectKey: " proj-env ",
        ]

        #expect(ZaiBigModelTeamContext(environment: env)?.organizationID == "org-env")
        #expect(ZaiBigModelTeamContext(environment: env)?.projectID == "proj-env")
    }
}

struct ZaiHourlyUsageTests {
    @Test
    func model_usage_parser_decodes_hourly_model_payload() throws {
        let json = """
        {
          "code": 200,
          "msg": "success",
          "success": true,
          "data": {
            "x_time": ["2026-05-14 08:00", "2026-05-14 09:00"],
            "modelDataList": [
              { "modelName": "glm-4.6", "tokensUsage": [100, null] },
              { "modelName": "glm-4.5", "tokensUsage": [50, 25] }
            ]
          }
        }
        """

        let usage = try ZaiUsageFetcher.parseModelUsage(from: Data(json.utf8))

        #expect(usage.xTime == ["2026-05-14 08:00", "2026-05-14 09:00"])
        #expect(usage.modelNames == ["glm-4.6", "glm-4.5"])
        #expect(usage.modelDataList[0].tokensUsage == [100, nil])
        #expect(usage.modelDataList[1].tokensUsage == [50, 25])
    }

    @Test
    func today_hourly_bars_filter_earlier_days_and_skip_empty_hours() {
        let reference = Self.localDate(year: 2026, month: 5, day: 14, hour: 12)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: reference) ?? reference
        let modelData = ZaiModelUsageData(
            xTime: [
                Self.hourString(yesterday),
                "2026-05-14 08:00",
                "2026-05-14 09:00",
            ],
            modelDataList: [
                ZaiModelDataItem(modelName: "glm-4.6", tokensUsage: [999, 100, 0]),
                ZaiModelDataItem(modelName: "glm-4.5", tokensUsage: [0, 50, nil]),
            ])

        let bars = ZaiHourlyBars.from(modelData: modelData, range: .today(referenceDate: reference), now: reference)

        #expect(bars.map(\.label) == ["08"])
        #expect(bars.first?.totalTokens == 150)
        #expect(bars.first?.segments.count == 2)
    }

    @Test
    func last_24_hour_bars_filter_data_outside_trailing_window() {
        let reference = Self.localDate(year: 2026, month: 5, day: 14, hour: 12)
        let old = Calendar.current.date(byAdding: .hour, value: -25, to: reference) ?? reference
        let inWindow = Calendar.current.date(byAdding: .hour, value: -23, to: reference) ?? reference
        let modelData = ZaiModelUsageData(
            xTime: [
                Self.hourString(old),
                Self.hourString(inWindow),
                Self.hourString(reference),
            ],
            modelDataList: [
                ZaiModelDataItem(modelName: "glm-4.6", tokensUsage: [10, 20, 30]),
            ])

        let bars = ZaiHourlyBars.from(modelData: modelData, range: .last24h, now: reference)

        #expect(bars.map(\.label) == [Self.hourLabel(inWindow), Self.hourLabel(reference)])
        #expect(bars.map(\.totalTokens) == [20, 30])
    }

    private static func localDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? Date()
    }

    private static func hourString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func hourLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}

struct ZaiThreeLimitTests {
    @Test
    func parses_three_limit_entries_into_session_weekly_and_mcp_slots() throws {
        let json = """
        {
          "code": 200,
          "msg": "操作成功",
          "data": {
            "limits": [
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "number": 5,
                "percentage": 25,
                "nextResetTime": 1775020168897
              },
              {
                "type": "TOKENS_LIMIT",
                "unit": 6,
                "number": 1,
                "percentage": 9,
                "nextResetTime": 1775588029998
              },
              {
                "type": "TIME_LIMIT",
                "unit": 5,
                "number": 1,
                "usage": 1000,
                "currentValue": 224,
                "remaining": 776,
                "percentage": 22,
                "nextResetTime": 1777575229998,
                "usageDetails": [
                  { "modelCode": "search-prime", "usage": 210 },
                  { "modelCode": "web-reader", "usage": 14 }
                ]
              }
            ],
            "level": "pro"
          },
          "success": true
        }
        """

        let snapshot = try ZaiUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))

        // Weekly token limit (unit:6=weeks, longer window) → tokenLimit (primary)
        #expect(snapshot.tokenLimit?.unit == .weeks)
        #expect(snapshot.tokenLimit?.number == 1)
        #expect(snapshot.tokenLimit?.percentage == 9.0)
        #expect(snapshot.tokenLimit?.windowMinutes == 10080)

        // 5-hour token limit (unit:3=hours, number:5 → 300 min) → sessionTokenLimit (tertiary)
        #expect(snapshot.sessionTokenLimit?.unit == .hours)
        #expect(snapshot.sessionTokenLimit?.number == 5)
        #expect(snapshot.sessionTokenLimit?.percentage == 25.0)
        #expect(snapshot.sessionTokenLimit?.windowMinutes == 300)

        // MCP time limit → timeLimit (secondary)
        #expect(snapshot.timeLimit?.usage == 1000)
        #expect(snapshot.timeLimit?.usageDetails.first?.modelCode == "search-prime")

        // UsageSnapshot slot mapping
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.usedPercent == 9.0)
        #expect(usage.primary?.windowMinutes == 10080)
        #expect(usage.secondary != nil) // MCP
        #expect(usage.tertiary?.usedPercent == 25.0)
        #expect(usage.tertiary?.windowMinutes == 300)
    }

    @Test
    func unit_6_maps_to_weeks_with_correct_window_minutes() {
        let entry = ZaiLimitEntry(
            type: .tokensLimit,
            unit: .weeks,
            number: 1,
            usage: nil,
            currentValue: nil,
            remaining: nil,
            percentage: 9,
            usageDetails: [],
            nextResetTime: nil)
        #expect(entry.windowMinutes == 10080)
        #expect(entry.windowDescription == "1 week")
        #expect(entry.windowLabel == "1 week window")
    }

    @Test
    func two_limit_entries_remain_backward_compatible() throws {
        let json = """
        {
          "code": 200,
          "msg": "Operation successful",
          "data": {
            "limits": [
              {
                "type": "TIME_LIMIT",
                "unit": 5,
                "number": 1,
                "usage": 100,
                "currentValue": 50,
                "remaining": 50,
                "percentage": 50,
                "usageDetails": []
              },
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "number": 5,
                "percentage": 34,
                "nextResetTime": 1768507567547
              }
            ]
          },
          "success": true
        }
        """

        let snapshot = try ZaiUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))

        #expect(snapshot.tokenLimit != nil)
        #expect(snapshot.sessionTokenLimit == nil)
        #expect(snapshot.timeLimit != nil)

        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary != nil)
        #expect(usage.secondary != nil)
        #expect(usage.tertiary == nil)
    }
}

struct ZaiAPIRegionTests {
    @Test
    func dashboard_URLs_follow_selected_region() {
        #expect(
            ZaiAPIRegion.global.dashboardURL.absoluteString ==
                "https://z.ai/manage-apikey/coding-plan/personal/my-plan")
        #expect(
            ZaiAPIRegion.bigmodelCN.dashboardURL.absoluteString ==
                "https://bigmodel.cn/coding-plan/personal/usage")
        #expect(
            ZaiProviderDescriptor.descriptor.metadata.dashboardURL ==
                ZaiAPIRegion.global.dashboardURL.absoluteString)
    }

    @Test
    func defaults_to_global_endpoint() {
        let url = ZaiUsageFetcher.resolveQuotaURL(region: .global, environment: [:])
        #expect(url.absoluteString == "https://api.z.ai/api/monitor/usage/quota/limit")
    }

    @Test
    func uses_big_model_region_when_selected() {
        let url = ZaiUsageFetcher.resolveQuotaURL(region: .bigmodelCN, environment: [:])
        #expect(url.absoluteString == "https://open.bigmodel.cn/api/monitor/usage/quota/limit")
    }

    @Test
    func quota_url_environment_override_wins() {
        let env = [ZaiSettingsReader.quotaURLKey: "https://open.bigmodel.cn/api/coding/paas/v4"]
        let url = ZaiUsageFetcher.resolveQuotaURL(region: .global, environment: env)
        #expect(url.absoluteString == "https://open.bigmodel.cn/api/coding/paas/v4")
    }

    @Test
    func api_host_environment_appends_quota_path() {
        let env = [ZaiSettingsReader.apiHostKey: "open.bigmodel.cn"]
        let url = ZaiUsageFetcher.resolveQuotaURL(region: .global, environment: env)
        #expect(url.absoluteString == "https://open.bigmodel.cn/api/monitor/usage/quota/limit")
    }

    @Test
    func dashboard_follows_known_endpoint_overrides() {
        let china = ZaiUsageFetcher.resolveDashboardURL(
            region: .global,
            environment: [ZaiSettingsReader.apiHostKey: "open.bigmodel.cn"])
        #expect(china == ZaiAPIRegion.bigmodelCN.dashboardURL)

        let global = ZaiUsageFetcher.resolveDashboardURL(
            region: .bigmodelCN,
            environment: [ZaiSettingsReader.apiHostKey: "api.z.ai"])
        #expect(global == ZaiAPIRegion.global.dashboardURL)
    }

    @Test
    func dashboard_keeps_selected_region_for_custom_endpoint_override() {
        let dashboard = ZaiUsageFetcher.resolveDashboardURL(
            region: .bigmodelCN,
            environment: [ZaiSettingsReader.apiHostKey: "zai.internal.example"])

        #expect(dashboard == ZaiAPIRegion.bigmodelCN.dashboardURL)
    }
}
