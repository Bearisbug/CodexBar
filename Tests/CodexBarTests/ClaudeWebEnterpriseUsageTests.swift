import Foundation
import Testing
@testable import CodexBarCore

struct ClaudeWebEnterpriseUsageTests {
    @Test
    func parses_usage_response_when_session_window_is_null() throws {
        let json = """
        {
          "five_hour": null,
          "seven_day": { "utilization": 42, "resets_at": "2025-12-29T23:00:00.000Z" }
        }
        """
        let data = Data(json.utf8)
        let parsed = try ClaudeWebAPIFetcher._parseUsageResponseForTesting(data)
        #expect(parsed.sessionPercentUsed == 0)
        #expect(parsed.weeklyPercentUsed == 42)
    }

    @Test
    func parses_enterprise_credit_spend_from_usage_response() throws {
        let json = """
        {
          "five_hour": null,
          "seven_day": null,
          "extra_usage": {
            "monthly_limit": 100000,
            "used_credits": 4132
          }
        }
        """
        let data = Data(json.utf8)
        let parsed = try ClaudeWebAPIFetcher._parseUsageResponseForTesting(data)

        #expect(parsed.sessionPercentUsed == 0)
        #expect(parsed.sessionResetsAt == nil)
        #expect(parsed.weeklyPercentUsed == nil)
        #expect(parsed.extraUsageCost?.used == 41.32)
        #expect(parsed.extraUsageCost?.limit == 1000)
        #expect(parsed.extraUsageCost?.currencyCode == "USD")
        #expect(parsed.extraUsageCost?.period == "Monthly cap")
    }
}
