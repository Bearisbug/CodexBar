import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct MenuCardQuotaWarningMarkerTests {
    @Test
    func progress_fill_matches_rounded_edge_labels() {
        #expect(UsageProgressBar.renderedFillPercent(0.4) == 0)
        #expect(UsageProgressBar.renderedFillPercent(0.6) == 0.6)
        #expect(UsageProgressBar.renderedFillPercent(99.4) == 99.4)
        #expect(UsageProgressBar.renderedFillPercent(99.6) == 100)
    }

    @Test
    func quota_warning_marker_geometry_matches_pace_stripe_edges() {
        let rect = UsageProgressBar.warningMarkerRect(
            x: 50,
            size: CGSize(width: 100, height: 6),
            scale: 2)
        let stripe = UsageProgressBar.warningMarkerStripeRect(
            rect,
            scale: 2)

        #expect(rect.width == 5)
        #expect(rect.height == 6)
        #expect(rect.minY == 0)
        #expect(rect.maxY == 6)
        #expect(abs(rect.midX - 50) <= 0.5)
        #expect(stripe.width == 1)
        #expect(stripe.height == rect.height)
        #expect(abs(stripe.midX - rect.midX) <= 0.001)
        #expect(stripe.minX > rect.minX)
        #expect(stripe.maxX < rect.maxX)
    }

    @Test
    func quota_warning_marker_geometry_stays_centered_across_display_scales() {
        let scales: [CGFloat] = [1, 2, 3]

        for scale in scales {
            let rect = UsageProgressBar.warningMarkerRect(
                x: 33,
                size: CGSize(width: 100, height: 6),
                scale: scale)
            let stripe = UsageProgressBar.warningMarkerStripeRect(
                rect,
                scale: scale)

            #expect(rect.minY == 0)
            #expect(rect.height == 6)
            #expect(rect.width == 5)
            #expect(stripe.width == 1)
            #expect(stripe.height == rect.height)
            #expect(abs(stripe.midX - rect.midX) <= 1 / scale)
            #expect(stripe.minX > rect.minX)
            #expect(stripe.maxX < rect.maxX)
        }
    }

    @Test
    func workday_boundary_is_a_subtle_lower_tick() {
        let rect = UsageProgressBar.workdayMarkerRect(
            x: 50,
            size: CGSize(width: 100, height: 6),
            scale: 2)

        #expect(rect.width == 0.5)
        #expect(rect.height == 3)
        #expect(rect.minY == 3)
        #expect(abs(rect.midX - 50) <= 0.5)
    }

    @Test
    func quota_warning_wins_when_marker_kinds_overlap() {
        let markers = UsageProgressBar.resolvedMarkers(
            warningPercents: [50, 80],
            workdayPercents: [20, 50, 60])

        #expect(markers == [
            .init(percent: 20, kind: .workdayBoundary),
            .init(percent: 50, kind: .quotaWarning),
            .init(percent: 60, kind: .workdayBoundary),
            .init(percent: 80, kind: .quotaWarning),
        ])
    }

    @Test
    func marker_resolver_removes_edges_duplicates_and_invalid_values() {
        let markers = UsageProgressBar.resolvedMarkers(
            warningPercents: [-10, 0, 50, 50, 100, 120],
            workdayPercents: [Double.nan, 25, 25])

        #expect(markers == [
            .init(percent: 25, kind: .workdayBoundary),
            .init(percent: 50, kind: .quotaWarning),
        ])
    }

    @Test
    func omits_quota_warning_markers_for_disabled_windows() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.codex])
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: "Plus Plan")
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 20,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 40,
                windowMinutes: 10080,
                resetsAt: nil,
                resetDescription: nil),
            updatedAt: now,
            identity: identity)
        let codexProjection = CodexConsumerProjection.make(
            surface: .liveCard,
            context: CodexConsumerProjection.Context(
                snapshot: snapshot,
                rawUsageError: nil,
                liveCredits: nil,
                rawCreditsError: nil,
                liveDashboard: nil,
                rawDashboardError: nil,
                dashboardAttachmentAuthorized: false,
                dashboardRequiresLogin: false,
                now: now))

        let model = UsageMenuCardView.Model.make(.init(
            provider: .codex,
            metadata: metadata,
            snapshot: snapshot,
            codexProjection: codexProjection,
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
            showOptionalCreditsAndExtraUsage: false,
            hidePersonalInfo: false,
            quotaWarningThresholds: [.session: [50], .weekly: []],
            now: now))

        #expect(model.metrics.count == 2)
        #expect(model.metrics.first?.warningMarkerPercents == [50])
        #expect(model.metrics[1].warningMarkerPercents.isEmpty)
    }

    @Test
    func work_day_marker_percents_for_5_day_week() {
        #expect(workDayMarkerPercents(workDays: 5, windowMinutes: 10080) == [20.0, 40.0, 60.0, 80.0])
    }

    @Test
    func work_day_marker_percents_for_4_day_week() {
        #expect(workDayMarkerPercents(workDays: 4, windowMinutes: 10080) == [25.0, 50.0, 75.0])
    }

    @Test
    func work_day_marker_percents_for_7_day_week() {
        let markers = workDayMarkerPercents(workDays: 7, windowMinutes: 10080)
        #expect(markers.count == 6)
        #expect(abs(markers[0] - 14.2857) < 0.001)
        #expect(abs(markers[5] - 85.7143) < 0.001)
    }

    @Test
    func work_day_marker_percents_nil_work_days_returns_empty() {
        #expect(workDayMarkerPercents(workDays: nil, windowMinutes: 10080).isEmpty)
    }

    @Test
    func work_day_marker_percents_nil_window_minutes_returns_empty() {
        #expect(workDayMarkerPercents(workDays: 5, windowMinutes: nil).isEmpty)
    }

    @Test
    func work_day_marker_percents_non_weekly_window_returns_empty() {
        #expect(workDayMarkerPercents(workDays: 5, windowMinutes: 300).isEmpty)
        #expect(workDayMarkerPercents(workDays: 5, windowMinutes: 1440).isEmpty)
    }

    @Test
    func work_day_marker_percents_invalid_work_days_returns_empty() {
        #expect(workDayMarkerPercents(workDays: 1, windowMinutes: 10080).isEmpty)
        #expect(workDayMarkerPercents(workDays: 0, windowMinutes: 10080).isEmpty)
        #expect(workDayMarkerPercents(workDays: 8, windowMinutes: 10080).isEmpty)
        #expect(workDayMarkerPercents(workDays: -1, windowMinutes: 10080).isEmpty)
    }
}
