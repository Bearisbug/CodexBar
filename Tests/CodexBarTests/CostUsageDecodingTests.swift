import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageDecodingTests {
    @Test
    func decodes_daily_report_type_format() throws {
        let json = """
        {
          "type": "daily",
          "data": [
            {
              "date": "2025-12-20",
              "inputTokens": 10,
              "cacheReadTokens": 2,
              "cacheCreationTokens": 3,
              "outputTokens": 20,
              "totalTokens": 30,
              "costUSD": 0.12
            }
          ],
          "summary": {
            "totalInputTokens": 10,
            "totalOutputTokens": 20,
            "cacheReadTokens": 2,
            "cacheCreationTokens": 3,
            "totalTokens": 30,
            "totalCostUSD": 0.12
          }
        }
        """

        let report = try JSONDecoder().decode(CostUsageDailyReport.self, from: Data(json.utf8))
        #expect(report.data.count == 1)
        #expect(report.data[0].date == "2025-12-20")
        #expect(report.data[0].totalTokens == 30)
        #expect(report.data[0].cacheReadTokens == 2)
        #expect(report.data[0].cacheCreationTokens == 3)
        #expect(report.data[0].costUSD == 0.12)
        #expect(report.summary?.totalCostUSD == 0.12)
        #expect(report.summary?.cacheReadTokens == 2)
        #expect(report.summary?.cacheCreationTokens == 3)
    }

    @Test
    func decodes_daily_report_legacy_format() throws {
        let json = """
        {
          "daily": [
            {
              "date": "2025-12-20",
              "inputTokens": 1,
              "cacheReadTokens": 2,
              "cacheCreationTokens": 3,
              "outputTokens": 2,
              "totalTokens": 3,
              "totalCost": 0.01
            }
          ],
          "totals": {
            "totalInputTokens": 1,
            "totalOutputTokens": 2,
            "cacheReadTokens": 2,
            "cacheCreationTokens": 3,
            "totalTokens": 3,
            "totalCost": 0.01
          }
        }
        """

        let report = try JSONDecoder().decode(CostUsageDailyReport.self, from: Data(json.utf8))
        #expect(report.data.count == 1)
        #expect(report.summary?.totalTokens == 3)
        #expect(report.summary?.totalCostUSD == 0.01)
        #expect(report.data[0].cacheReadTokens == 2)
        #expect(report.data[0].cacheCreationTokens == 3)
        #expect(report.summary?.cacheReadTokens == 2)
        #expect(report.summary?.cacheCreationTokens == 3)
    }

    @Test
    func decodes_legacy_cache_token_keys() throws {
        let json = """
        {
          "type": "daily",
          "data": [
            {
              "date": "2025-12-20",
              "cacheReadInputTokens": 4,
              "cacheCreationInputTokens": 5,
              "totalTokens": 9
            }
          ],
          "summary": {
            "totalCacheReadTokens": 4,
            "totalCacheCreationTokens": 5,
            "totalTokens": 9
          }
        }
        """

        let report = try JSONDecoder().decode(CostUsageDailyReport.self, from: Data(json.utf8))
        #expect(report.data[0].cacheReadTokens == 4)
        #expect(report.data[0].cacheCreationTokens == 5)
        #expect(report.summary?.cacheReadTokens == 4)
        #expect(report.summary?.cacheCreationTokens == 5)
    }

    @Test
    func decodes_daily_report_legacy_format_with_model_map() throws {
        let json = """
        {
          "daily": [
            {
              "date": "Dec 20, 2025",
              "inputTokens": 10,
              "outputTokens": 20,
              "totalTokens": 30,
              "costUSD": 0.12,
              "models": {
                "gpt-5.2-codex": {
                  "inputTokens": 10,
                  "outputTokens": 20,
                  "totalTokens": 30,
                  "isFallback": false
                }
              }
            }
          ],
          "totals": {
            "totalTokens": 30,
            "costUSD": 0.12
          }
        }
        """

        let report = try JSONDecoder().decode(CostUsageDailyReport.self, from: Data(json.utf8))
        #expect(report.data.count == 1)
        #expect(report.data[0].costUSD == 0.12)
        #expect(report.data[0].modelsUsed == ["gpt-5.2-codex"])
    }

    @Test
    func decodes_daily_report_legacy_format_with_model_map_sorted() throws {
        let json = """
        {
          "daily": [
            {
              "date": "Dec 20, 2025",
              "totalTokens": 30,
              "costUSD": 0.12,
              "models": {
                "z-model": { "totalTokens": 10 },
                "a-model": { "totalTokens": 20 },
                "m-model": { "totalTokens": 0 }
              }
            }
          ]
        }
        """

        let report = try JSONDecoder().decode(CostUsageDailyReport.self, from: Data(json.utf8))
        #expect(report.data[0].modelsUsed == ["a-model", "m-model", "z-model"])
    }

    @Test
    func decodes_daily_report_legacy_format_with_empty_model_map_as_nil() throws {
        let json = """
        {
          "daily": [
            {
              "date": "Dec 20, 2025",
              "totalTokens": 30,
              "costUSD": 0.12,
              "models": {}
            }
          ]
        }
        """

        let report = try JSONDecoder().decode(CostUsageDailyReport.self, from: Data(json.utf8))
        #expect(report.data[0].modelsUsed == nil)
    }

    @Test
    func decodes_daily_report_legacy_format_prefers_models_used_list_over_models_map() throws {
        let json = """
        {
          "daily": [
            {
              "date": "Dec 20, 2025",
              "totalTokens": 30,
              "costUSD": 0.12,
              "modelsUsed": ["gpt-5.2-codex"],
              "models": {
                "ignored-model": { "totalTokens": 30 }
              }
            }
          ]
        }
        """

        let report = try JSONDecoder().decode(CostUsageDailyReport.self, from: Data(json.utf8))
        #expect(report.data[0].modelsUsed == ["gpt-5.2-codex"])
    }

    @Test
    func decodes_daily_report_legacy_format_with_models_list() throws {
        let json = """
        {
          "daily": [
            {
              "date": "Dec 20, 2025",
              "totalTokens": 30,
              "costUSD": 0.12,
              "models": ["gpt-5.2-codex", "gpt-5.2-mini"]
            }
          ]
        }
        """

        let report = try JSONDecoder().decode(CostUsageDailyReport.self, from: Data(json.utf8))
        #expect(report.data[0].modelsUsed == ["gpt-5.2-codex", "gpt-5.2-mini"])
    }

    @Test
    func decodes_model_breakdown_total_tokens() throws {
        let json = """
        {
          "type": "daily",
          "data": [
            {
              "date": "2025-12-20",
              "totalTokens": 30,
              "costUSD": 0.12,
              "modelBreakdowns": [
                {
                  "modelName": "gpt-5.2-codex",
                  "costUSD": 0.12,
                  "totalTokens": 30
                }
              ]
            }
          ]
        }
        """

        let report = try JSONDecoder().decode(CostUsageDailyReport.self, from: Data(json.utf8))
        #expect(report.data[0].modelBreakdowns == [
            CostUsageDailyReport.ModelBreakdown(modelName: "gpt-5.2-codex", costUSD: 0.12, totalTokens: 30),
        ])
    }

    @Test
    func decodes_daily_report_legacy_format_with_invalid_models_field() throws {
        let json = """
        {
          "daily": [
            {
              "date": "Dec 20, 2025",
              "totalTokens": 30,
              "costUSD": 0.12,
              "models": "gpt-5.2"
            }
          ]
        }
        """

        let report = try JSONDecoder().decode(CostUsageDailyReport.self, from: Data(json.utf8))
        #expect(report.data[0].modelsUsed == nil)
    }

    @Test
    func decodes_monthly_report_legacy_format() throws {
        let json = """
        {
          "monthly": [
            {
              "month": "Dec 2025",
              "totalTokens": 123,
              "costUSD": 4.56
            }
          ],
          "totals": {
            "totalTokens": 123,
            "costUSD": 4.56
          }
        }
        """

        let report = try JSONDecoder().decode(CostUsageMonthlyReport.self, from: Data(json.utf8))
        #expect(report.data.count == 1)
        #expect(report.data[0].month == "Dec 2025")
        #expect(report.data[0].costUSD == 4.56)
        #expect(report.summary?.totalCostUSD == 4.56)
    }

    @Test
    func selects_most_recent_session() throws {
        let json = """
        {
          "type": "session",
          "data": [
            {
              "session": "A",
              "totalTokens": 100,
              "costUSD": 0.50,
              "lastActivity": "2025-12-19"
            },
            {
              "session": "B",
              "totalTokens": 50,
              "costUSD": 0.20,
              "lastActivity": "2025-12-20T12:00:00Z"
            },
            {
              "session": "C",
              "totalTokens": 200,
              "costUSD": 0.10,
              "lastActivity": "2025-12-20T11:00:00Z"
            }
          ],
          "summary": {
            "totalCostUSD": 0.80
          }
        }
        """

        let report = try JSONDecoder().decode(CostUsageSessionReport.self, from: Data(json.utf8))
        let selected = CostUsageFetcher.selectCurrentSession(from: report.data)
        #expect(selected?.session == "B")
    }

    @Test
    func selects_most_recent_supported_month_format() throws {
        let json = """
        {
          "type": "monthly",
          "data": [
            { "month": "Dec 2025", "totalTokens": 100, "costUSD": 1.00 },
            { "month": "January 2026", "totalTokens": 200, "costUSD": 2.00 },
            { "month": "2026-02", "totalTokens": 300, "costUSD": 3.00 }
          ]
        }
        """

        let report = try JSONDecoder().decode(CostUsageMonthlyReport.self, from: Data(json.utf8))
        let selected = CostUsageFetcher.selectMostRecentMonth(from: report.data)
        #expect(selected?.month == "2026-02")
        #expect(selected?.totalTokens == 300)
    }

    @Test
    func date_parsers_handle_concurrent_mixed_formats() async {
        let dateInputs = [
            "2026-02-03T04:05:06.789Z",
            "2026-02-03T04:05:06Z",
            "2026-02-03",
            "Feb 3, 2026",
        ]
        let monthInputs = ["Feb 2026", "February 2026", "2026-02"]

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    for _ in 0..<250 {
                        guard dateInputs.allSatisfy({ CostUsageDateParser.parse($0) != nil }),
                              monthInputs.allSatisfy({ CostUsageDateParser.parseMonth($0) != nil })
                        else {
                            return false
                        }
                    }
                    return true
                }
            }

            for await succeeded in group {
                #expect(succeeded)
            }
        }
    }

    @Test
    func token_snapshot_selects_current_local_day() throws {
        let json = """
        {
          "type": "daily",
          "data": [
            {
              "date": "Dec 20, 2025",
              "totalTokens": 30,
              "costUSD": 1.23
            },
            {
              "date": "2025-12-21",
              "totalTokens": 10,
              "costUSD": 4.56
            }
          ],
          "summary": {
            "totalCostUSD": 5.79
          }
        }
        """

        let report = try JSONDecoder().decode(CostUsageDailyReport.self, from: Data(json.utf8))
        let now = try Self.localNoon(year: 2025, month: 12, day: 21)
        let snapshot = CostUsageFetcher.tokenSnapshot(from: report, now: now)
        #expect(snapshot.sessionTokens == 10)
        #expect(snapshot.sessionCostUSD == 4.56)
        #expect(snapshot.last30DaysCostUSD == 5.79)
        #expect(snapshot.daily.count == 2)
        #expect(snapshot.updatedAt == now)
    }

    @Test
    func token_snapshot_rejects_impossible_later_calendar_day() throws {
        let json = """
        {
          "type": "daily",
          "data": [
            {
              "date": "2026-05-13",
              "totalTokens": 30,
              "costUSD": 23.45
            },
            {
              "date": "2026-06-31",
              "totalTokens": 40,
              "costUSD": 99.00
            }
          ]
        }
        """

        let report = try JSONDecoder().decode(CostUsageDailyReport.self, from: Data(json.utf8))
        let snapshot = CostUsageFetcher.tokenSnapshot(
            from: report,
            now: Date(),
            useCurrentLocalDayForSession: false)

        #expect(snapshot.sessionTokens == 30)
        #expect(snapshot.sessionCostUSD == 23.45)
    }

    @Test
    func token_snapshot_uses_summary_total_cost_when_available() throws {
        let json = """
        {
          "type": "daily",
          "data": [
            { "date": "2025-12-20", "costUSD": 1.00 },
            { "date": "2025-12-21", "costUSD": 2.00 }
          ],
          "summary": {
            "totalCostUSD": 99.00
          }
        }
        """

        let report = try JSONDecoder().decode(CostUsageDailyReport.self, from: Data(json.utf8))
        let snapshot = CostUsageFetcher.tokenSnapshot(from: report, now: Date())
        #expect(snapshot.last30DaysCostUSD == 99.00)
    }

    @Test
    func token_snapshot_falls_back_to_summed_entries_when_summary_missing() throws {
        let json = """
        {
          "type": "daily",
          "data": [
            { "date": "2025-12-20", "costUSD": 1.00 },
            { "date": "2025-12-21", "costUSD": 2.00 }
          ]
        }
        """

        let report = try JSONDecoder().decode(CostUsageDailyReport.self, from: Data(json.utf8))
        let snapshot = CostUsageFetcher.tokenSnapshot(from: report, now: Date())
        #expect(snapshot.last30DaysCostUSD == 3.00)
    }

    @Test
    func token_snapshot_returns_nil_total_when_no_costs_present() throws {
        let json = """
        {
          "type": "daily",
          "data": [
            { "date": "2025-12-20", "totalTokens": 10 },
            { "date": "2025-12-21", "totalTokens": 20 }
          ]
        }
        """

        let report = try JSONDecoder().decode(CostUsageDailyReport.self, from: Data(json.utf8))
        let snapshot = CostUsageFetcher.tokenSnapshot(from: report, now: Date())
        #expect(snapshot.last30DaysCostUSD == nil)
    }

    private static func localNoon(year: Int, month: Int, day: Int) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }
}
