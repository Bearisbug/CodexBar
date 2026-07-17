import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct UsageStorePlanUtilizationExactFitResetTests {
    @MainActor
    @Test
    func weekly_chart_uses_reset_date_as_bar_date() {
        let firstBoundary = Date(timeIntervalSince1970: 1_710_000_000)
        let secondBoundary = firstBoundary.addingTimeInterval(7 * 24 * 60 * 60)
        let thirdBoundary = secondBoundary.addingTimeInterval(7 * 24 * 60 * 60)
        let histories = [
            planSeries(name: .weekly, windowMinutes: 10080, entries: [
                planEntry(at: firstBoundary.addingTimeInterval(-30 * 60), usedPercent: 62, resetsAt: firstBoundary),
                planEntry(at: secondBoundary.addingTimeInterval(-30 * 60), usedPercent: 48, resetsAt: secondBoundary),
                planEntry(at: thirdBoundary.addingTimeInterval(-30 * 60), usedPercent: 20, resetsAt: thirdBoundary),
            ]),
        ]

        let model = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            selectedSeriesRawValue: "weekly:10080",
            histories: histories,
            provider: .codex,
            referenceDate: thirdBoundary)

        #expect(model.usedPercents == [62, 48, 20])
        #expect(model.pointDates == [
            formattedBoundary(firstBoundary),
            formattedBoundary(secondBoundary),
            formattedBoundary(thirdBoundary),
        ])
    }

    @MainActor
    @Test
    func chart_keeps_maximum_usage_for_each_effective_period() {
        let firstBoundary = Date(timeIntervalSince1970: 1_710_000_000)
        let secondBoundary = firstBoundary.addingTimeInterval(5 * 60 * 60)
        let histories = [
            planSeries(name: .session, windowMinutes: 300, entries: [
                planEntry(at: firstBoundary.addingTimeInterval(-50 * 60), usedPercent: 22, resetsAt: firstBoundary),
                planEntry(
                    at: firstBoundary.addingTimeInterval(-20 * 60),
                    usedPercent: 61,
                    resetsAt: firstBoundary.addingTimeInterval(75)),
                planEntry(at: secondBoundary.addingTimeInterval(-30 * 60), usedPercent: 18, resetsAt: secondBoundary),
            ]),
        ]

        let model = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            selectedSeriesRawValue: "session:300",
            histories: histories,
            provider: .codex,
            referenceDate: secondBoundary)

        #expect(model.usedPercents == [61, 18])
        #expect(model.pointDates == [
            formattedBoundary(firstBoundary.addingTimeInterval(75)),
            formattedBoundary(secondBoundary),
        ])
    }

    @MainActor
    @Test
    func chart_prefers_reset_backed_entry_when_usage_ties_within_period() {
        let boundary = Date(timeIntervalSince1970: 1_710_000_000)
        let histories = [
            planSeries(name: .session, windowMinutes: 300, entries: [
                planEntry(at: boundary.addingTimeInterval(-55 * 60), usedPercent: 48),
                planEntry(at: boundary.addingTimeInterval(-20 * 60), usedPercent: 48, resetsAt: boundary),
            ]),
        ]

        let model = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            selectedSeriesRawValue: "session:300",
            histories: histories,
            provider: .codex,
            referenceDate: boundary)

        #expect(model.usedPercents == [48])
        #expect(model.pointDates == [formattedBoundary(boundary)])
    }

    @MainActor
    @Test
    func chart_adds_synthetic_current_bar_when_current_period_has_no_observation() {
        let firstBoundary = Date(timeIntervalSince1970: 1_710_000_000)
        let currentBoundary = firstBoundary.addingTimeInterval(10 * 60 * 60)
        let referenceDate = currentBoundary.addingTimeInterval(-30 * 60)
        let histories = [
            planSeries(name: .session, windowMinutes: 300, entries: [
                planEntry(at: firstBoundary.addingTimeInterval(-30 * 60), usedPercent: 62, resetsAt: firstBoundary),
            ]),
        ]

        let model = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            selectedSeriesRawValue: "session:300",
            histories: histories,
            provider: .codex,
            referenceDate: referenceDate)

        #expect(model.usedPercents == [62, 0, 0])
        #expect(model.pointDates == [
            formattedBoundary(firstBoundary),
            formattedBoundary(firstBoundary.addingTimeInterval(5 * 60 * 60)),
            formattedBoundary(currentBoundary),
        ])
    }

    @MainActor
    @Test
    func weekly_chart_shows_zero_bars_for_missing_reset_periods() {
        let firstBoundary = Date(timeIntervalSince1970: 1_710_000_000)
        let secondBoundary = firstBoundary.addingTimeInterval(7 * 24 * 60 * 60)
        let fourthBoundary = secondBoundary.addingTimeInterval(14 * 24 * 60 * 60)
        let histories = [
            planSeries(name: .weekly, windowMinutes: 10080, entries: [
                planEntry(at: firstBoundary.addingTimeInterval(-30 * 60), usedPercent: 62, resetsAt: firstBoundary),
                planEntry(at: secondBoundary.addingTimeInterval(-30 * 60), usedPercent: 48, resetsAt: secondBoundary),
                planEntry(at: fourthBoundary.addingTimeInterval(-30 * 60), usedPercent: 20, resetsAt: fourthBoundary),
            ]),
        ]

        let model = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            selectedSeriesRawValue: "weekly:10080",
            histories: histories,
            provider: .codex,
            referenceDate: fourthBoundary)

        #expect(model.usedPercents == [62, 48, 0, 20])
    }

    @MainActor
    @Test
    func weekly_chart_starts_axis_labels_from_first_bar() {
        let firstBoundary = Date(timeIntervalSince1970: 1_710_000_000)
        let secondBoundary = firstBoundary.addingTimeInterval(7 * 24 * 60 * 60)
        let thirdBoundary = secondBoundary.addingTimeInterval(7 * 24 * 60 * 60)
        let fourthBoundary = thirdBoundary.addingTimeInterval(7 * 24 * 60 * 60)
        let histories = [
            planSeries(name: .weekly, windowMinutes: 10080, entries: [
                planEntry(at: firstBoundary.addingTimeInterval(-30 * 60), usedPercent: 62, resetsAt: firstBoundary),
                planEntry(at: secondBoundary.addingTimeInterval(-30 * 60), usedPercent: 48, resetsAt: secondBoundary),
                planEntry(at: thirdBoundary.addingTimeInterval(-30 * 60), usedPercent: 20, resetsAt: thirdBoundary),
                planEntry(at: fourthBoundary.addingTimeInterval(-30 * 60), usedPercent: 15, resetsAt: fourthBoundary),
            ]),
        ]

        let model = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            selectedSeriesRawValue: "weekly:10080",
            histories: histories,
            provider: .codex,
            referenceDate: fourthBoundary)

        #expect(model.axisIndexes == [0])
    }

    @MainActor
    @Test
    func weekly_chart_keeps_observed_current_boundary_when_reset_times_drift_slightly() {
        let firstBoundary = Date(timeIntervalSince1970: 1_710_000_055)
        let secondBoundary = firstBoundary.addingTimeInterval(7 * 24 * 60 * 60 + 88)
        let histories = [
            planSeries(name: .weekly, windowMinutes: 10080, entries: [
                planEntry(at: firstBoundary.addingTimeInterval(-30 * 60), usedPercent: 62, resetsAt: firstBoundary),
                planEntry(at: secondBoundary.addingTimeInterval(-30 * 60), usedPercent: 33, resetsAt: secondBoundary),
            ]),
        ]

        let model = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            selectedSeriesRawValue: "weekly:10080",
            histories: histories,
            provider: .codex,
            referenceDate: secondBoundary.addingTimeInterval(-60))

        #expect(model.usedPercents == [62, 33])
    }

    @MainActor
    @Test
    func weekly_chart_prefers_reset_backed_history_over_legacy_synthetic_points() {
        let legacyCapturedAt = Date(timeIntervalSince1970: 1_742_100_000)
        let firstBoundary = Date(timeIntervalSince1970: 1_742_356_855) // 2026-03-18T17:00:55Z
        let secondBoundary = Date(timeIntervalSince1970: 1_742_961_343) // 2026-03-25T17:02:23Z
        let histories = [
            planSeries(name: .weekly, windowMinutes: 10080, entries: [
                planEntry(at: legacyCapturedAt, usedPercent: 57),
                planEntry(at: firstBoundary.addingTimeInterval(-60 * 60), usedPercent: 73, resetsAt: firstBoundary),
                planEntry(at: secondBoundary.addingTimeInterval(-60 * 60), usedPercent: 35, resetsAt: secondBoundary),
            ]),
        ]

        let model = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            selectedSeriesRawValue: "weekly:10080",
            histories: histories,
            provider: .codex,
            referenceDate: secondBoundary.addingTimeInterval(-60))

        #expect(model.usedPercents == [73, 35])
    }

    @MainActor
    @Test
    func chart_keeps_legacy_history_before_first_reset_backed_boundary() {
        let firstLegacyCapturedAt = Date(timeIntervalSince1970: 1_739_692_800) // 2026-02-23T07:00:00Z
        let secondLegacyCapturedAt = firstLegacyCapturedAt.addingTimeInterval(7 * 24 * 60 * 60)
        let firstBoundary = secondLegacyCapturedAt.addingTimeInterval(7 * 24 * 60 * 60 + 55)
        let secondBoundary = firstBoundary.addingTimeInterval(7 * 24 * 60 * 60)
        let histories = [
            planSeries(name: .weekly, windowMinutes: 10080, entries: [
                planEntry(at: firstLegacyCapturedAt, usedPercent: 20),
                planEntry(at: secondLegacyCapturedAt, usedPercent: 40),
                planEntry(at: firstBoundary.addingTimeInterval(-60 * 60), usedPercent: 73, resetsAt: firstBoundary),
                planEntry(at: secondBoundary.addingTimeInterval(-60 * 60), usedPercent: 35, resetsAt: secondBoundary),
            ]),
        ]

        let model = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            selectedSeriesRawValue: "weekly:10080",
            histories: histories,
            provider: .claude,
            referenceDate: secondBoundary.addingTimeInterval(-60))

        #expect(model.usedPercents == [20, 40, 73, 35])
    }
}
