import Foundation
import Testing
@testable import CodexBarCore

struct OpenCodeGoUsageParserTests {
    @Test
    func parses_workspace_ids() {
        let text = ";0x00000089;((self.$R=self.$R||{})[\"codexbar\"]=[]," +
            "($R=>$R[0]=[$R[1]={id:\"wrk_01K6AR1ZET89H8NB691FQ2C2VB\",name:\"Default\",slug:null}])" +
            "($R[\"codexbar\"]))"
        let ids = OpenCodeGoUsageFetcher.parseWorkspaceIDs(text: text)
        #expect(ids == ["wrk_01K6AR1ZET89H8NB691FQ2C2VB"])
    }

    @Test
    func parses_subscription_usage_from_seroval_response() throws {
        let text =
            "$R[16]($R[30],$R[41]={rollingUsage:$R[42]={status:\"ok\",resetInSec:5944,usagePercent:17}," +
            "weeklyUsage:$R[43]={status:\"ok\",resetInSec:278201,usagePercent:75}," +
            "monthlyUsage:$R[44]={status:\"ok\",resetInSec:880201,usagePercent:91}});"
        let now = Date(timeIntervalSince1970: 0)

        let snapshot = try OpenCodeGoUsageFetcher.parseSubscription(text: text, now: now)

        #expect(snapshot.rollingUsagePercent == 17)
        #expect(snapshot.weeklyUsagePercent == 75)
        #expect(snapshot.hasMonthlyUsage == true)
        #expect(snapshot.monthlyUsagePercent == 91)
        #expect(snapshot.rollingResetInSec == 5944)
        #expect(snapshot.weeklyResetInSec == 278_201)
        #expect(snapshot.monthlyResetInSec == 880_201)
    }

    @Test
    func parses_zen_balance_from_workspace_page_text() {
        let text = """
        <main>
        <h2>現在の残高 $1,234.56</h2>
        <p>Claude Opus and GPT-5 models enabled</p>
        </main>
        """

        #expect(OpenCodeGoUsageFetcher.parseZenBalance(text: text) == 1234.56)
    }

    @Test
    func parses_zen_balance_from_nested_JSON() throws {
        let payload: [String: Any] = [
            "data": [
                "billing": [
                    "balanceEnabled": true,
                    "zenBalance": "1,042.75",
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        #expect(OpenCodeGoUsageFetcher.parseZenBalance(text: text) == 1042.75)
    }

    @Test
    func parses_scaled_zen_balance_from_billing_server_response() {
        let text =
            #";0x00000120;((self.$R=self.$R||{})["server-fn:test"]=[],"# +
            #"($R=>$R[0]=$R[1]={customerID:"cus_test",balance:$R[2]=2375000000,reload:!1})"# +
            #"($R["server-fn:test"]))"#

        #expect(OpenCodeGoZenBalanceParser.parseBillingServerResponse(text: text) == 23.75)
    }

    @Test
    func billing_server_parser_ignores_unrelated_balance_metadata() {
        let text = #"$R[0]={balanceEnabled:!0,balanceUpdatedAt:1800000000}"#

        #expect(OpenCodeGoZenBalanceParser.parseBillingServerResponse(text: text) == nil)
    }

    @Test
    func billing_server_parser_ignores_balance_when_billing_is_disabled() {
        let text = #"$R[0]={customerID:null,balance:0,reload:!1}"#

        #expect(OpenCodeGoZenBalanceParser.parseBillingServerResponse(text: text) == nil)
    }

    @Test
    func zen_balance_parser_ignores_metadata_before_amount() throws {
        let payload: [String: Any] = [
            "data": [
                "billing": [
                    "balanceUpdatedAt": 1_800_000_000,
                    "balanceRefreshInterval": 60,
                    "zenBalance": "42.50",
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        #expect(OpenCodeGoUsageFetcher.parseZenBalance(text: text) == 42.50)
    }

    @Test
    func parses_subscription_usage_from_live_go_page_hydration() throws {
        let rollingResetInSec = 17591
        let weeklyResetInSec = 444_552
        let monthlyResetInSec = 2_591_424
        let text =
            "_$HY.r[\"lite.subscription.get[\\\"wrk_LIVE123\\\"]\"]=$R[17]=$R[2]($R[18]={p:0,s:0,f:0});" +
            "$R[24]($R[18],$R[27]={mine:!0,useBalance:!1," +
            "rollingUsage:$R[28]={status:\"ok\",resetInSec:\(rollingResetInSec),usagePercent:0}," +
            "weeklyUsage:$R[29]={status:\"ok\",resetInSec:\(weeklyResetInSec),usagePercent:0}," +
            "monthlyUsage:$R[30]={status:\"ok\",resetInSec:\(monthlyResetInSec),usagePercent:0}});"
        let now = Date(timeIntervalSince1970: 0)

        let snapshot = try OpenCodeGoUsageFetcher.parseSubscription(text: text, now: now)

        #expect(snapshot.rollingUsagePercent == 0)
        #expect(snapshot.weeklyUsagePercent == 0)
        #expect(snapshot.hasMonthlyUsage == true)
        #expect(snapshot.monthlyUsagePercent == 0)
        #expect(snapshot.rollingResetInSec == rollingResetInSec)
        #expect(snapshot.weeklyResetInSec == weeklyResetInSec)
        #expect(snapshot.monthlyResetInSec == monthlyResetInSec)
    }

    @Test
    func parses_rolling_only_usage_from_seroval_response() throws {
        let text =
            "$R[16]($R[30],$R[41]={rollingUsage:$R[42]={status:\"ok\",resetInSec:5944,usagePercent:17}});"
        let now = Date(timeIntervalSince1970: 0)

        let snapshot = try OpenCodeGoUsageFetcher.parseSubscription(text: text, now: now)
        let usage = snapshot.toUsageSnapshot()

        #expect(snapshot.rollingUsagePercent == 17)
        #expect(snapshot.rollingResetInSec == 5944)
        #expect(snapshot.hasWeeklyUsage == false)
        #expect(usage.primary?.usedPercent == 17)
        #expect(usage.secondary == nil)
        #expect(usage.tertiary == nil)
    }

    @Test
    func parses_rolling_only_usage_from_JSON_response() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let payload: [String: Any] = [
            "usage": [
                "rollingUsage": [
                    "usagePercent": 25,
                    "resetInSec": 600,
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeGoUsageFetcher.parseSubscription(text: text, now: now)
        let usage = snapshot.toUsageSnapshot()

        #expect(snapshot.rollingUsagePercent == 25)
        #expect(snapshot.rollingResetInSec == 600)
        #expect(snapshot.hasWeeklyUsage == false)
        #expect(usage.primary?.usedPercent == 25)
        #expect(usage.secondary == nil)
        #expect(usage.tertiary == nil)
    }

    @Test
    func recovers_weekly_usage_from_nested_JSON_window() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let payload: [String: Any] = [
            "usage": [
                "rollingUsage": [
                    "usagePercent": 25,
                    "resetInSec": 600,
                ],
                "weeklyUsage": [
                    "window": [
                        "usagePercent": 75,
                        "resetInSec": 7200,
                    ],
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeGoUsageFetcher.parseSubscription(text: text, now: now)
        let usage = snapshot.toUsageSnapshot()

        #expect(snapshot.hasWeeklyUsage == true)
        #expect(snapshot.weeklyUsagePercent == 75)
        #expect(snapshot.weeklyResetInSec == 7200)
        #expect(usage.secondary?.usedPercent == 75)
    }

    @Test
    func parses_subscription_from_JSON_with_reset_at_and_ratio_percentages() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let rollingResetAt = now.addingTimeInterval(3600)
        let monthlyResetAt = now.addingTimeInterval(86400)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload: [String: Any] = [
            "usage": [
                "rollingUsage": [
                    "usagePercent": 0.25,
                    "resetAt": formatter.string(from: rollingResetAt),
                ],
                "weeklyUsage": [
                    "usagePercent": 75,
                    "resetInSec": 7200,
                ],
                "monthlyUsage": [
                    "usagePercent": 0.9,
                    "resetAt": formatter.string(from: monthlyResetAt),
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeGoUsageFetcher.parseSubscription(text: text, now: now)

        #expect(snapshot.rollingUsagePercent == 25)
        #expect(snapshot.weeklyUsagePercent == 75)
        #expect(snapshot.hasMonthlyUsage == true)
        #expect(snapshot.monthlyUsagePercent == 90)
        #expect(snapshot.rollingResetInSec == 3600)
        #expect(snapshot.weeklyResetInSec == 7200)
        #expect(snapshot.monthlyResetInSec == 86400)
    }

    @Test(arguments: ["1e309", "1e308"])
    func ignores_reset_timestamps_outside_integer_range(resetAt: String) throws {
        let text = """
        {
          "rollingUsage": { "usagePercent": 17, "resetAt": "\(resetAt)" },
          "weeklyUsage": { "usagePercent": 75, "resetInSec": 7200 }
        }
        """

        let snapshot = try OpenCodeGoUsageFetcher.parseSubscription(
            text: text,
            now: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(snapshot.rollingUsagePercent == 17)
        #expect(snapshot.weeklyUsagePercent == 75)
        #expect(snapshot.rollingResetInSec == 0)
        #expect(snapshot.weeklyResetInSec == 7200)
    }

    @Test
    func computes_usage_percent_from_totals_and_treats_monthly_as_optional() throws {
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

        let snapshot = try OpenCodeGoUsageFetcher.parseSubscription(text: text, now: now)
        let usage = snapshot.toUsageSnapshot()

        #expect(snapshot.rollingUsagePercent == 25)
        #expect(snapshot.weeklyUsagePercent == 25)
        #expect(snapshot.hasMonthlyUsage == false)
        #expect(snapshot.monthlyUsagePercent == 0)
        #expect(snapshot.monthlyResetInSec == 0)
        #expect(usage.tertiary == nil)
    }

    @Test
    func snapshot_exposes_zen_balance_as_provider_cost() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = OpenCodeGoUsageSnapshot(
            hasMonthlyUsage: false,
            rollingUsagePercent: 10,
            weeklyUsagePercent: 20,
            monthlyUsagePercent: 0,
            rollingResetInSec: 600,
            weeklyResetInSec: 3600,
            monthlyResetInSec: 0,
            zenBalanceUSD: 12.34,
            updatedAt: now)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.providerCost?.period == "Zen balance")
        #expect(usage.providerCost?.used == 12.34)
        #expect(usage.providerCost?.limit == 0)
        #expect(usage.providerCost?.currencyCode == "USD")
    }

    @Test
    func zen_balance_parser_ignores_balance_flags_without_amounts() throws {
        let payload: [String: Any] = [
            "billing": [
                "balanceEnabled": true,
                "useBalance": false,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        #expect(OpenCodeGoUsageFetcher.parseZenBalance(text: text) == nil)
    }

    @Test
    func parses_subscription_from_nested_candidate_windows() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let payload: [String: Any] = [
            "windows": [
                "primaryWindow": [
                    "used": 15,
                    "limit": 100,
                    "resetInSec": 600,
                ],
                "weeklyQuota": [
                    "used": 80,
                    "limit": 200,
                    "resetInSec": 7200,
                ],
                "monthlyBucket": [
                    "used": 90,
                    "limit": 300,
                    "resetInSec": 86400,
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeGoUsageFetcher.parseSubscription(text: text, now: now)

        #expect(snapshot.rollingUsagePercent == 15)
        #expect(snapshot.weeklyUsagePercent == 40)
        #expect(snapshot.hasMonthlyUsage == true)
        #expect(snapshot.monthlyUsagePercent == 30)
        #expect(snapshot.monthlyResetInSec == 86400)
    }

    @Test
    func candidate_fallback_preserves_missing_weekly_window() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let payload: [String: Any] = [
            "windows": [
                "primaryWindow": [
                    "used": 15,
                    "limit": 100,
                    "resetInSec": 600,
                ],
                "monthlyBucket": [
                    "used": 90,
                    "limit": 300,
                    "resetInSec": 86400,
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeGoUsageFetcher.parseSubscription(text: text, now: now)
        let usage = snapshot.toUsageSnapshot()

        #expect(snapshot.rollingUsagePercent == 15)
        #expect(snapshot.hasWeeklyUsage == false)
        #expect(snapshot.hasMonthlyUsage == true)
        #expect(snapshot.monthlyUsagePercent == 30)
        #expect(usage.secondary == nil)
        #expect(usage.tertiary?.usedPercent == 30)
    }

    @Test
    func clamps_invalid_percentages() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let payload: [String: Any] = [
            "rollingUsage": [
                "usagePercent": 150,
                "resetInSec": 60,
            ],
            "weeklyUsage": [
                "usagePercent": -10,
                "resetInSec": 120,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeGoUsageFetcher.parseSubscription(text: text, now: now)

        #expect(snapshot.rollingUsagePercent == 100)
        #expect(snapshot.weeklyUsagePercent == 0)
    }

    @Test
    func parse_subscription_throws_when_required_fields_are_missing() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let text = "{\"monthlyUsage\":{\"usagePercent\":50,\"resetInSec\":123}}"

        #expect(throws: OpenCodeGoUsageError.self) {
            _ = try OpenCodeGoUsageFetcher.parseSubscription(text: text, now: now)
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
            "monthlyUsage": ["usagePercent": 25, "resetInSec": 7200],
            "renewAt": formatter.string(from: renewAt),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeGoUsageFetcher.parseSubscription(text: text, now: now)

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
            "monthlyUsage": ["usagePercent": 25, "resetInSec": 7200],
            "renew_at": formatter.string(from: renewAt),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeGoUsageFetcher.parseSubscription(text: text, now: now)

        #expect(snapshot.renewsAt != nil)
        #expect(snapshot.renewsAt == renewAt)
    }

    @Test
    func renewsAt_is_nil_when_absent() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let payload: [String: Any] = [
            "rollingUsage": ["usagePercent": 10, "resetInSec": 600],
            "weeklyUsage": ["usagePercent": 50, "resetInSec": 3600],
            "monthlyUsage": ["usagePercent": 25, "resetInSec": 7200],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeGoUsageFetcher.parseSubscription(text: text, now: now)

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
                "monthlyUsage": ["usagePercent": 25, "resetInSec": 7200],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeGoUsageFetcher.parseSubscription(text: text, now: now)

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
                "monthlyUsage": ["usagePercent": 25, "resetInSec": 7200],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeGoUsageFetcher.parseSubscription(text: text, now: now)

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
                "monthlyUsage": ["usagePercent": 25, "resetInSec": 7200],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeGoUsageFetcher.parseSubscription(text: text, now: now)

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
            "monthlyUsage": ["usagePercent": 25, "resetInSec": 7200],
            "renewAt": formatter.string(from: renewAt),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        let snapshot = try OpenCodeGoUsageFetcher.parseSubscription(text: text, now: now)
        let usage = snapshot.toUsageSnapshot()

        #expect(usage.extraRateWindows != nil)
        #expect(usage.extraRateWindows?.count == 1)
        #expect(usage.extraRateWindows?[0].id == "renewal")
        #expect(usage.extraRateWindows?[0].title == "Renews")
        #expect(usage.extraRateWindows?[0].window.resetsAt == renewAt)
    }
}
