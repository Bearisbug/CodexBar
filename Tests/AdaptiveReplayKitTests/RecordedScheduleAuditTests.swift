import AdaptiveReplayKit
import Foundation
import Testing

struct RecordedScheduleAuditTests {
    private static let epoch = Date(timeIntervalSinceReferenceDate: 0)

    private func at(_ seconds: TimeInterval) -> Date {
        Self.epoch.addingTimeInterval(seconds)
    }

    @Test
    func legacy_recorded_advance_validates_without_evaluation_records() {
        let menu = self.at(50)
        let trace: [AdaptiveRefreshTraceRecord] = [
            .menuOpen(timestamp: menu),
            .timerAdvanced(
                timestamp: menu,
                previousScheduledAt: self.at(1800),
                candidateScheduledAt: self.at(170),
                reason: "recentInteraction",
                delaySeconds: 120),
        ]

        let audit = RecordedScheduleAuditor.audit(trace)

        #expect(audit.isValid)
        #expect(audit.recordedAdvanceCount == 1)
        #expect(audit.evaluatedCount == 0)
    }

    @Test
    func accepted_and_rejected_live_evaluations_audit_independently_of_replay() {
        let accepted = AdaptiveRefreshTraceRecord.timerAdvanceEvaluated(
            timestamp: self.at(50),
            previousScheduledAt: self.at(1800),
            candidateScheduledAt: self.at(170),
            reason: "recentInteraction",
            delaySeconds: 120,
            accepted: true,
            refreshInFlight: false)
        let rejected = AdaptiveRefreshTraceRecord.timerAdvanceEvaluated(
            timestamp: self.at(100),
            previousScheduledAt: self.at(170),
            candidateScheduledAt: self.at(220),
            reason: "recentInteraction",
            delaySeconds: 120,
            accepted: false,
            refreshInFlight: true)
        let trace: [AdaptiveRefreshTraceRecord] = [
            .menuOpen(timestamp: self.at(50)),
            accepted,
            .timerAdvanced(
                timestamp: self.at(50),
                previousScheduledAt: self.at(1800),
                candidateScheduledAt: self.at(170),
                reason: "recentInteraction",
                delaySeconds: 120),
            .menuOpen(timestamp: self.at(100)),
            rejected,
        ]

        let audit = RecordedScheduleAuditor.audit(trace)

        #expect(audit.isValid)
        #expect(audit.evaluatedCount == 2)
        #expect(audit.acceptedEvaluationCount == 1)
        #expect(audit.rejectedEvaluationCount == 1)
        #expect(audit.ambiguousComparisonCount == 0)
    }

    @Test
    func evaluation_whose_accepted_flag_disagrees_with_schedule_comparison_fails() {
        let trace: [AdaptiveRefreshTraceRecord] = [
            .timerAdvanceEvaluated(
                timestamp: self.at(100),
                previousScheduledAt: self.at(170),
                candidateScheduledAt: self.at(220),
                reason: "recentInteraction",
                delaySeconds: 120,
                accepted: true,
                refreshInFlight: false),
        ]

        let audit = RecordedScheduleAuditor.audit(trace)

        #expect(!audit.isValid)
        #expect(audit.decisionMismatchCount == 1)
        #expect(audit.payloadMismatchCount == 1)
    }

    @Test
    func unequal_schedule_dates_override_a_contradictory_exact_lead() {
        let event = AdaptiveRefreshTraceRecord(
            kind: .timerAdvanceEvaluated,
            timestamp: self.at(50),
            reason: "recentInteraction",
            delaySeconds: 120,
            previousScheduledAt: self.at(180),
            candidateScheduledAt: self.at(170),
            timerAdvanceAccepted: false,
            scheduleLeadSeconds: -10,
            refreshInFlight: false)

        let audit = RecordedScheduleAuditor.audit([.menuOpen(timestamp: self.at(50)), event])

        #expect(audit.decisionMismatchCount == 1)
        #expect(!audit.isValid)
    }

    @Test
    func accepted_evaluation_without_a_previous_schedule_remains_valid() {
        let event = AdaptiveRefreshTraceRecord.timerAdvanceEvaluated(
            timestamp: self.at(50),
            previousScheduledAt: nil,
            candidateScheduledAt: self.at(170),
            reason: "recentInteraction",
            delaySeconds: 120,
            accepted: true,
            refreshInFlight: false)

        let advanced = AdaptiveRefreshTraceRecord.timerAdvanced(
            timestamp: self.at(50),
            previousScheduledAt: nil,
            candidateScheduledAt: self.at(170),
            reason: "recentInteraction",
            delaySeconds: 120)
        let audit = RecordedScheduleAuditor.audit([.menuOpen(timestamp: self.at(50)), event, advanced])

        #expect(audit.isValid)
    }

    @Test
    func fractional_live_lead_survives_whole_second_date_serialization() throws {
        let timestamp = self.at(50.2)
        let candidate = self.at(170.2)
        let previous = self.at(170.8)
        let record = AdaptiveRefreshTraceRecord.timerAdvanceEvaluated(
            timestamp: timestamp,
            previousScheduledAt: previous,
            candidateScheduledAt: candidate,
            reason: "recentInteraction",
            delaySeconds: 120,
            accepted: true,
            refreshInFlight: false)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let line = try #require(String(data: encoder.encode(record), encoding: .utf8))
        let parsed = try #require(AdaptiveRefreshTraceParser.parse(line).first)

        #expect(parsed.previousScheduledAt == parsed.candidateScheduledAt)
        #expect(try abs(#require(parsed.scheduleLeadSeconds) - 0.6) < 0.001)
        let advanced = try AdaptiveRefreshTraceRecord.timerAdvanced(
            timestamp: parsed.timestamp,
            previousScheduledAt: parsed.previousScheduledAt,
            candidateScheduledAt: #require(parsed.candidateScheduledAt),
            reason: #require(parsed.reason),
            delaySeconds: #require(parsed.delaySeconds))
        #expect(RecordedScheduleAuditor.audit([.menuOpen(timestamp: parsed.timestamp), parsed, advanced]).isValid)
    }

    @Test
    func legacy_equal_timestamps_are_reported_as_ambiguous_instead_of_mismatched() {
        let event = AdaptiveRefreshTraceRecord(
            kind: .timerAdvanceEvaluated,
            timestamp: self.at(50),
            reason: "recentInteraction",
            delaySeconds: 120,
            previousScheduledAt: self.at(170),
            candidateScheduledAt: self.at(170),
            timerAdvanceAccepted: true,
            refreshInFlight: false)

        let audit = RecordedScheduleAuditor.audit([.menuOpen(timestamp: self.at(50)), event])

        #expect(audit.decisionMismatchCount == 0)
        #expect(audit.ambiguousComparisonCount == 1)
        #expect(!audit.isValid)
    }

    @Test
    func evaluation_without_a_menu_open_source_fails_linkage_audit() {
        let event = AdaptiveRefreshTraceRecord.timerAdvanceEvaluated(
            timestamp: self.at(50),
            previousScheduledAt: self.at(1800),
            candidateScheduledAt: self.at(170),
            reason: "recentInteraction",
            delaySeconds: 120,
            accepted: true,
            refreshInFlight: false)

        let audit = RecordedScheduleAuditor.audit([event])

        #expect(audit.menuLinkMismatchCount == 1)
        #expect(!audit.isValid)
    }

    @Test
    func duplicate_accepted_evaluations_require_matching_advance_multiplicity() {
        let evaluation = AdaptiveRefreshTraceRecord.timerAdvanceEvaluated(
            timestamp: self.at(50),
            previousScheduledAt: self.at(1800),
            candidateScheduledAt: self.at(170),
            reason: "recentInteraction",
            delaySeconds: 120,
            accepted: true,
            refreshInFlight: false)
        let advance = AdaptiveRefreshTraceRecord.timerAdvanced(
            timestamp: self.at(50),
            previousScheduledAt: self.at(1800),
            candidateScheduledAt: self.at(170),
            reason: "recentInteraction",
            delaySeconds: 120)

        let audit = RecordedScheduleAuditor.audit([
            .menuOpen(timestamp: self.at(50)),
            evaluation,
            evaluation,
            advance,
        ])

        #expect(audit.payloadMismatchCount == 1)
        #expect(!audit.isValid)
    }

    @Test
    func duplicate_rejected_evaluations_require_distinct_menu_opens() {
        let evaluation = AdaptiveRefreshTraceRecord.timerAdvanceEvaluated(
            timestamp: self.at(50),
            previousScheduledAt: self.at(170),
            candidateScheduledAt: self.at(220),
            reason: "recentInteraction",
            delaySeconds: 170,
            accepted: false,
            refreshInFlight: true)

        let audit = RecordedScheduleAuditor.audit([
            .menuOpen(timestamp: self.at(50)),
            evaluation,
            evaluation,
        ])

        #expect(audit.menuLinkMismatchCount == 1)
        #expect(!audit.isValid)
    }
}
