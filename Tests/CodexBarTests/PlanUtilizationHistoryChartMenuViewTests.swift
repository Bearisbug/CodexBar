import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct PlanUtilizationHistoryChartMenuViewTests {
    @Test
    func merged_entries_preserve_first_occurrence_order_while_removing_duplicates() {
        let first = PlanUtilizationHistoryEntry(
            capturedAt: Date(timeIntervalSince1970: 100),
            usedPercent: 10,
            resetsAt: Date(timeIntervalSince1970: 200))
        let second = PlanUtilizationHistoryEntry(
            capturedAt: Date(timeIntervalSince1970: 300),
            usedPercent: 20,
            resetsAt: nil)

        let merged = PlanUtilizationHistoryChartMenuView.mergedEntries([
            first,
            second,
            first,
            second,
        ])

        #expect(merged == [first, second])
    }

    @Test
    func generic_primary_weekly_window_keeps_weekly_history_visible() {
        let history = PlanUtilizationSeriesHistory(
            name: .weekly,
            windowMinutes: 10080,
            entries: [
                PlanUtilizationHistoryEntry(
                    capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    usedPercent: 42,
                    resetsAt: nil),
            ])
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 42, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let model = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            histories: [history],
            provider: .zai,
            snapshot: snapshot)

        #expect(model.visibleSeries == ["weekly:10080"])
        #expect(model.selectedSeries == "weekly:10080")
    }

    @Test
    func generic_unknown_weekly_extra_window_does_not_filter_saved_history() {
        let history = PlanUtilizationSeriesHistory(
            name: .weekly,
            windowMinutes: 10080,
            entries: [
                PlanUtilizationHistoryEntry(
                    capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    usedPercent: 42,
                    resetsAt: nil),
            ])
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            extraRateWindows: [
                NamedRateWindow(
                    id: "weekly-reset-only",
                    title: "Weekly reset",
                    window: RateWindow(
                        usedPercent: 0,
                        windowMinutes: 10080,
                        resetsAt: Date(timeIntervalSince1970: 1_700_003_600),
                        resetDescription: nil),
                    usageKnown: false),
            ],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let model = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            histories: [history],
            provider: .zed,
            snapshot: snapshot)

        #expect(model.visibleSeries == ["weekly:10080"])
        #expect(model.selectedSeries == "weekly:10080")
    }
}
