import Testing
@testable import CodexBar

@Suite("Usage breakdown chart menu")
@MainActor
struct UsageBreakdownChartMenuViewTests {
    @Test
    func valid_totals_remain_visible_when_service_rows_are_absent() {
        #expect(
            UsageBreakdownChartMenuView.presentationState(
                hasSummary: true,
                hasChartPoints: false) == .totalsOnly)
    }

    @Test
    func service_rows_select_the_chart_presentation() {
        #expect(
            UsageBreakdownChartMenuView.presentationState(
                hasSummary: true,
                hasChartPoints: true) == .chart)
    }

    @Test
    func missing_totals_and_service_rows_select_the_empty_presentation() {
        #expect(
            UsageBreakdownChartMenuView.presentationState(
                hasSummary: false,
                hasChartPoints: false) == .empty)
    }
}
