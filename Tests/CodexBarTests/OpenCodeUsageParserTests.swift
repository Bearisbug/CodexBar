import Foundation
import Testing
@testable import CodexBarCore

struct OpenCodeUsageParserTests {
    @Test
    func parses_workspace_I_ds() {
        let text = ";0x00000089;((self.$R=self.$R||{})[\"codexbar\"]=[]," +
            "($R=>$R[0]=[$R[1]={id:\"wrk_01K6AR1ZET89H8NB691FQ2C2VB\",name:\"Default\",slug:null}])" +
            "($R[\"codexbar\"]))"
        let ids = OpenCodeUsageFetcher.parseWorkspaceIDs(text: text)
        #expect(ids == ["wrk_01K6AR1ZET89H8NB691FQ2C2VB"])
    }

    @Test
    func parses_subscription_usage() throws {
        let text = "$R[16]($R[30],$R[41]={rollingUsage:$R[42]={status:\"ok\",resetInSec:5944,usagePercent:17}," +
            "weeklyUsage:$R[43]={status:\"ok\",resetInSec:278201,usagePercent:75}});"
        let now = Date(timeIntervalSince1970: 0)
        let snapshot = try OpenCodeUsageFetcher.parseSubscription(text: text, now: now)
        #expect(snapshot.rollingUsagePercent == 17)
        #expect(snapshot.weeklyUsagePercent == 75)
        #expect(snapshot.rollingResetInSec == 5944)
        #expect(snapshot.weeklyResetInSec == 278_201)
    }

    @Test
    func parses_subscription_from_JSON_with_reset_at() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let resetAt = now.addingTimeInterval(3600)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload: [String: Any] = [
            "usage": [
                "rollingUsage": [
                    "usagePercent": 0.25,
                    "resetAt": formatter.string(from: resetAt),
                ],
                "weeklyUsage": [
                    "usagePercent": 75,
                    "resetInSec": 7200,
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeUsageFetcher.parseSubscription(text: text, now: now)

        #expect(snapshot.rollingUsagePercent == 25)
        #expect(snapshot.weeklyUsagePercent == 75)
        #expect(snapshot.rollingResetInSec == 3600)
        #expect(snapshot.weeklyResetInSec == 7200)
    }

    @Test(arguments: ["1e309", "1e308"])
    func ignores_reset_timestamps_outside_integer_range(resetAt: String) throws {
        let text = """
        {
          "rollingUsage": { "usagePercent": 17, "resetAt": "\(resetAt)" },
          "weeklyUsage": { "usagePercent": 75, "resetInSec": 7200 }
        }
        """

        let snapshot = try OpenCodeUsageFetcher.parseSubscription(
            text: text,
            now: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(snapshot.rollingUsagePercent == 17)
        #expect(snapshot.weeklyUsagePercent == 75)
        #expect(snapshot.rollingResetInSec == 0)
        #expect(snapshot.weeklyResetInSec == 7200)
    }

    @Test
    func parses_subscription_from_candidate_windows() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let payload: [String: Any] = [
            "windows": [
                "primaryWindow": [
                    "percent": 0.1,
                    "resetInSec": 300,
                ],
                "secondaryWindow": [
                    "percent": 0.5,
                    "resetInSec": 1200,
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeUsageFetcher.parseSubscription(text: text, now: now)

        #expect(snapshot.rollingUsagePercent == 10)
        #expect(snapshot.weeklyUsagePercent == 50)
        #expect(snapshot.rollingResetInSec == 300)
        #expect(snapshot.weeklyResetInSec == 1200)
    }

    @Test
    func computes_usage_percent_from_totals() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let payload: [String: Any] = [
            "rollingUsage": [
                "used": 25,
                "limit": 100,
                "resetInSec": 600,
            ],
            "weeklyUsage": [
                "used": 50,
                "limit": 200,
                "resetInSec": 3600,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeUsageFetcher.parseSubscription(text: text, now: now)

        #expect(snapshot.rollingUsagePercent == 25)
        #expect(snapshot.weeklyUsagePercent == 25)
    }

    @Test
    func parse_subscription_throws_when_fields_missing() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let text = "{\"ok\":true}"

        #expect(throws: OpenCodeUsageError.self) {
            _ = try OpenCodeUsageFetcher.parseSubscription(text: text, now: now)
        }
    }

    @Test
    func renewsAt_parses_from_ISO8601_renewAt_key() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let renewAt = now.addingTimeInterval(86400 * 30)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload: [String: Any] = [
            "rollingUsage": ["usagePercent": 10, "resetInSec": 600],
            "weeklyUsage": ["usagePercent": 50, "resetInSec": 3600],
            "renewAt": formatter.string(from: renewAt),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeUsageFetcher.parseSubscription(text: text, now: now)

        #expect(snapshot.renewsAt != nil)
        #expect(snapshot.renewsAt == renewAt)
    }

    @Test
    func renewsAt_parses_from_renew_at_key() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let renewAt = now.addingTimeInterval(86400 * 30)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload: [String: Any] = [
            "rollingUsage": ["usagePercent": 10, "resetInSec": 600],
            "weeklyUsage": ["usagePercent": 50, "resetInSec": 3600],
            "renew_at": formatter.string(from: renewAt),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeUsageFetcher.parseSubscription(text: text, now: now)

        #expect(snapshot.renewsAt != nil)
        #expect(snapshot.renewsAt == renewAt)
    }

    @Test
    func renewsAt_is_nil_when_absent() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let payload: [String: Any] = [
            "rollingUsage": ["usagePercent": 10, "resetInSec": 600],
            "weeklyUsage": ["usagePercent": 50, "resetInSec": 3600],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeUsageFetcher.parseSubscription(text: text, now: now)

        #expect(snapshot.renewsAt == nil)
    }

    @Test
    func top_level_renewAt_is_preserved_for_nested_usage_object() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let renewAt = now.addingTimeInterval(86400 * 30)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload: [String: Any] = [
            "renewAt": formatter.string(from: renewAt),
            "usage": [
                "rollingUsage": ["usagePercent": 10, "resetInSec": 600],
                "weeklyUsage": ["usagePercent": 50, "resetInSec": 3600],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeUsageFetcher.parseSubscription(text: text, now: now)

        #expect(snapshot.renewsAt == renewAt)
    }

    @Test
    func top_level_renew_at_is_preserved_for_nested_usage_object() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let renewAt = now.addingTimeInterval(86400 * 30)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload: [String: Any] = [
            "renew_at": formatter.string(from: renewAt),
            "usage": [
                "rollingUsage": ["usagePercent": 10, "resetInSec": 600],
                "weeklyUsage": ["usagePercent": 50, "resetInSec": 3600],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeUsageFetcher.parseSubscription(text: text, now: now)

        #expect(snapshot.renewsAt == renewAt)
    }

    @Test
    func child_renewAt_overrides_parent_renewAt() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let parentRenewAt = now.addingTimeInterval(86400 * 30)
        let childRenewAt = now.addingTimeInterval(86400 * 45)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload: [String: Any] = [
            "renewAt": formatter.string(from: parentRenewAt),
            "usage": [
                "renewAt": formatter.string(from: childRenewAt),
                "rollingUsage": ["usagePercent": 10, "resetInSec": 600],
                "weeklyUsage": ["usagePercent": 50, "resetInSec": 3600],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeUsageFetcher.parseSubscription(text: text, now: now)

        #expect(snapshot.renewsAt == childRenewAt)
    }

    @Test
    func toUsageSnapshot_includes_renewal_NamedRateWindow_when_renewsAt_present() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let renewAt = now.addingTimeInterval(86400 * 30)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload: [String: Any] = [
            "rollingUsage": ["usagePercent": 10, "resetInSec": 600],
            "weeklyUsage": ["usagePercent": 50, "resetInSec": 3600],
            "renewAt": formatter.string(from: renewAt),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeUsageFetcher.parseSubscription(text: text, now: now)
        let usage = snapshot.toUsageSnapshot()

        #expect(usage.extraRateWindows != nil)
        #expect(usage.extraRateWindows?.count == 1)
        #expect(usage.extraRateWindows?[0].id == "renewal")
        #expect(usage.extraRateWindows?[0].title == "Renews")
        #expect(usage.extraRateWindows?[0].window.resetsAt == renewAt)
    }
}
