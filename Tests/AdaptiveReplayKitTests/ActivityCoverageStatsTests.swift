import AdaptiveReplayKit
import Foundation
import Testing

/// Purely informational trace-level stats surfaced by `AdaptiveReplayCLI` — computed directly from
/// raw `decision` records, independent of any `ReplayPolicy` or `ReplayEngine` simulation.
struct ActivityCoverageStatsTests {
    private static let referenceNow = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private static func decision(codex: TimeInterval?, claude: TimeInterval?) -> AdaptiveRefreshTraceRecord {
        .decision(
            timestamp: self.referenceNow,
            menuAgeSeconds: nil,
            lowPowerModeEnabled: false,
            thermalState: .nominal,
            reason: "warm",
            delaySeconds: 300,
            codexActivitySeconds: codex,
            claudeActivitySeconds: claude)
    }

    @Test
    func an_empty_trace_reports_zero_decisions_and_zero_fractions() {
        let stats = ActivityCoverageStats.compute(from: [])
        #expect(stats.decisionCount == 0)
        #expect(stats.sampledCount == 0)
        #expect(stats.activeCount == 0)
        #expect(stats.sampledFraction == 0)
        #expect(stats.activeFraction == 0)
    }

    @Test
    func non_decision_records_are_ignored_entirely() {
        let records: [AdaptiveRefreshTraceRecord] = [
            .menuOpen(timestamp: Self.referenceNow),
            .refreshCompleted(timestamp: Self.referenceNow),
        ]
        let stats = ActivityCoverageStats.compute(from: records)
        #expect(stats.decisionCount == 0)
    }

    @Test
    func a_decision_with_neither_activity_field_set_counts_toward_decisionCount_but_not_sampledCount() {
        let stats = ActivityCoverageStats.compute(from: [Self.decision(codex: nil, claude: nil)])
        #expect(stats.decisionCount == 1)
        #expect(stats.sampledCount == 0)
        #expect(stats.activeCount == 0)
    }

    @Test
    func a_decision_with_only_one_activity_field_set_still_counts_as_sampled() {
        let stats = ActivityCoverageStats.compute(from: [Self.decision(codex: 500, claude: nil)])
        #expect(stats.sampledCount == 1)
    }

    @Test
    func a_sampled_decision_under_the_active_threshold_on_either_CLI_counts_as_active() {
        let codexActive = ActivityCoverageStats.compute(from: [Self.decision(codex: 100, claude: nil)])
        #expect(codexActive.activeCount == 1)

        let claudeActive = ActivityCoverageStats.compute(from: [Self.decision(codex: nil, claude: 100)])
        #expect(claudeActive.activeCount == 1)
    }

    @Test
    func a_sampled_decision_at_or_above_the_active_threshold_on_both_CLIs_does_not_count_as_active() {
        let stats = ActivityCoverageStats.compute(from: [Self.decision(codex: 500, claude: 400)])
        #expect(stats.sampledCount == 1)
        #expect(stats.activeCount == 0)
    }

    @Test
    func fractions_are_computed_against_decisionCount_and_sampledCount_respectively() {
        let records: [AdaptiveRefreshTraceRecord] = [
            Self.decision(codex: 100, claude: nil), // sampled, active
            Self.decision(codex: 500, claude: 400), // sampled, not active
            Self.decision(codex: nil, claude: nil), // not sampled
            Self.decision(codex: nil, claude: nil), // not sampled
        ]
        let stats = ActivityCoverageStats.compute(from: records)
        #expect(stats.decisionCount == 4)
        #expect(stats.sampledCount == 2)
        #expect(stats.activeCount == 1)
        #expect(stats.sampledFraction == 0.5)
        #expect(stats.activeFraction == 0.5)
    }

    @Test
    func a_custom_active_threshold_changes_the_active_classification() {
        let stats = ActivityCoverageStats.compute(
            from: [Self.decision(codex: 250, claude: nil)],
            activeThresholdSeconds: 60)
        #expect(stats.sampledCount == 1)
        #expect(stats.activeCount == 0)
    }
}
