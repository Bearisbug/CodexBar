import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar

struct MenuCardProviderRegressionTests {
    @Test
    func menu_card_keeps_positive_sub_percent_usage_visible() {
        let metric = UsageMenuCardView.Model.Metric(
            id: "sub-percent",
            title: "Monthly",
            percent: 0.1,
            percentStyle: .used,
            resetText: nil,
            detailText: nil,
            detailLeftText: nil,
            detailRightText: nil,
            pacePercent: nil,
            paceOnTop: false)

        #expect(metric.percentLabel == "<1% used")
    }

    @Test
    func elevenlabs_progress_color_stays_visible_in_light_menus() {
        #expect(UsageMenuCardView.Model.progressColor(for: .elevenlabs) == Color(nsColor: .labelColor))
    }

    @Test
    func open_router_model_shows_daily_and_weekly_key_spend() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.openrouter])
        let snapshot = OpenRouterUsageSnapshot(
            totalCredits: 50,
            totalUsage: 45.3895596325,
            balance: 4.6104403675,
            usedPercent: 90.779119265,
            keyLimit: 20,
            keyUsage: 0.5,
            keyUsageDaily: 0.12,
            keyUsageWeekly: 0.74,
            rateLimit: nil,
            updatedAt: now).toUsageSnapshot()

        let model = UsageMenuCardView.Model.make(.init(
            provider: .openrouter,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        #expect(model.usageNotes == ["Today: $0.12 · This week: $0.74"])
    }

    @Test
    func ollama_api_key_model_explains_browser_session_quota_requirement() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.ollama])
        let snapshot = OllamaAPIUsageSnapshot(modelCount: 3, updatedAt: now).toUsageSnapshot()

        let model = UsageMenuCardView.Model.make(.init(
            provider: .ollama,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            sourceLabel: "api",
            hidePersonalInfo: false,
            now: now))

        #expect(model.metrics.isEmpty)
        #expect(model.placeholder == nil)
        #expect(model.planText == "API key")
        #expect(model.usageNotes == [
            "API key verified. Cloud quotas need browser cookies. Sign in to Ollama.",
        ])
    }

    @Test
    func wayfinder_model_shows_gateway_routing_savings_and_latency() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.wayfinder])
        let usage = WayfinderUsageSnapshot(
            gatewayStatus: "ok",
            offline: false,
            dryRun: true,
            missingKeys: [],
            modelCount: 2,
            requests: 14,
            tokens: 1028,
            realized: 0.003558,
            baseline: 0.009252,
            saved: 0.005694,
            savedPct: 61.5,
            priced: true,
            routes: [
                .init(name: "local", requests: 10, saved: 0.005694, tokens: 662),
                .init(name: "cloud", requests: 4, saved: 0, tokens: 366),
            ],
            avgDecisionMs: 0.0804,
            updatedAt: now)

        let model = UsageMenuCardView.Model.make(.init(
            provider: .wayfinder,
            metadata: metadata,
            snapshot: usage.toUsageSnapshot(),
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        #expect(model.usageNotes == [
            "Gateway: ok · 2 models · dry run",
            "Routed: local: 10 · cloud: 4",
            "Saved: <$0.01 · 61.5% vs highest-cost route",
            "Avg decision: 0.1 ms",
        ])
    }

    @Test
    func copilot_over_quota_usage_keeps_used_percentage_detail() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.copilot])
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 115, windowMinutes: nil, resetsAt: nil, resetDescription: "115% used"),
            secondary: nil,
            tertiary: nil,
            updatedAt: now,
            identity: nil)

        let model = UsageMenuCardView.Model.make(.init(
            provider: .copilot,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        let metric = try #require(model.metrics.first)
        #expect(metric.percent == 0)
        #expect(metric.percentLabel == "0% left")
        #expect(metric.detailLeftText == "115% used")
    }
}
