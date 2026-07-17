import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar

struct CopilotMenuCardModelTests {
    @Test
    func hides_copilot_budget_bars_when_budget_extras_are_disabled() throws {
        let now = Date()
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 30, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            extraRateWindows: [
                NamedRateWindow(
                    id: "copilot-budget-agent",
                    title: "Budget - Copilot Agent Premium Requests",
                    window: RateWindow(usedPercent: 65, windowMinutes: nil, resetsAt: nil, resetDescription: nil)),
            ],
            updatedAt: now)
        let metadata = try #require(ProviderDefaults.metadata[.copilot])
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

        #expect(model.metrics.map(\.title) == ["Premium", "Chat"])
        #expect(model.metrics.allSatisfy { $0.detailLeftText == nil })
        #expect(model.metrics.allSatisfy { $0.detailRightText == nil })
        #expect(model.metrics.allSatisfy { $0.pacePercent == nil })
    }

    @Test
    func monthly_quotas_show_projections_and_pace_markers() throws {
        let now = try Self.date("2026-07-16T12:00:00Z")
        let reset = try Self.date("2026-08-01T00:00:00Z")
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 70, windowMinutes: nil, resetsAt: reset, resetDescription: nil),
            secondary: RateWindow(usedPercent: 30, windowMinutes: nil, resetsAt: reset, resetDescription: nil),
            updatedAt: now)

        let model = try Self.model(snapshot: snapshot, now: now)

        let premium = try #require(model.metrics.first { $0.id == "primary" })
        #expect(premium.resetText == "Resets in 15d 12h")
        #expect(premium.detailLeftText == "20% in deficit")
        #expect(premium.detailRightText == "Runs out in 6d 15h")
        #expect(try #require(premium.pacePercent) == 50)
        #expect(premium.paceOnTop == false)

        let chat = try #require(model.metrics.first { $0.id == "secondary" })
        #expect(chat.resetText == "Resets in 15d 12h")
        #expect(chat.detailLeftText == "20% in reserve")
        #expect(chat.detailRightText == "Lasts until reset")
        #expect(try #require(chat.pacePercent) == 50)
        #expect(chat.paceOnTop == true)
    }

    @Test
    func monthly_projection_uses_the_calendar_month_ending_at_reset() throws {
        let now = try Self.date("2026-02-15T00:00:00Z")
        let reset = try Self.date("2026-03-01T00:00:00Z")
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 70, windowMinutes: nil, resetsAt: reset, resetDescription: nil),
            secondary: nil,
            updatedAt: now)

        let model = try Self.model(snapshot: snapshot, now: now)

        let premium = try #require(model.metrics.first)
        #expect(premium.detailLeftText == "20% in deficit")
        #expect(try #require(premium.pacePercent) == 50)
    }

    @Test
    func over_quota_usage_keeps_raw_detail_when_reset_is_known() throws {
        let now = try Self.date("2026-07-16T12:00:00Z")
        let reset = try Self.date("2026-08-01T00:00:00Z")
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 115,
                windowMinutes: nil,
                resetsAt: reset,
                resetDescription: "115% used"),
            secondary: nil,
            updatedAt: now)

        let model = try Self.model(snapshot: snapshot, now: now)

        let premium = try #require(model.metrics.first)
        #expect(premium.detailLeftText == "115% used")
        #expect(premium.detailRightText == nil)
        #expect(premium.pacePercent == nil)
    }

    private static func model(snapshot: UsageSnapshot, now: Date) throws -> UsageMenuCardView.Model {
        let metadata = try #require(ProviderDefaults.metadata[.copilot])
        return UsageMenuCardView.Model.make(.init(
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
    }

    private static func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}
