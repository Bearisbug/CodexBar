import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct CodexWeeklyResetConfirmationTests {
    private let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private let resetAt = Date(timeIntervalSince1970: 1_800_500_000)

    @Test
    func ordinary_observations_publish_while_stale_initial_observations_preserve() {
        let previous = self.snapshot(offset: 0, weeklyUsed: 70, weeklyReset: self.resetAt)
        let previousWithoutWeekly = self.snapshot(offset: 0, weeklyUsed: nil, weeklyReset: nil)
        let newer = self.snapshot(offset: 1, weeklyUsed: 71, weeklyReset: self.resetAt)
        let stale = self.snapshot(offset: 0, weeklyUsed: 72, weeklyReset: self.resetAt)

        #expect(CodexWeeklyResetConfirmation.initialDecision(previous: nil, initial: newer) == .publishInitial)
        #expect(
            CodexWeeklyResetConfirmation.initialDecision(previous: previousWithoutWeekly, initial: newer)
                == .publishInitial)
        #expect(
            CodexWeeklyResetConfirmation.initialDecision(previous: previous, initial: newer) == .publishInitial)
        #expect(
            CodexWeeklyResetConfirmation.initialDecision(previous: previous, initial: stale) == .preservePrevious)
    }

    @Test
    func first_low_observation_requires_matching_confirmation_without_prior_state() {
        let reset = self.resetAt.addingTimeInterval(7 * 24 * 60 * 60)
        let previousWithoutWeekly = self.snapshot(offset: 0, weeklyUsed: nil, weeklyReset: nil)
        let initial = self.snapshot(offset: 1, weeklyUsed: 0.2, weeklyReset: reset)
        let matching = self.snapshot(offset: 2, weeklyUsed: 0.7, weeklyReset: reset.addingTimeInterval(30))
        let rebound = self.snapshot(offset: 2, weeklyUsed: 42, weeklyReset: reset)

        #expect(
            CodexWeeklyResetConfirmation.initialDecision(previous: nil, initial: initial)
                == .requiresConfirmation)
        #expect(
            CodexWeeklyResetConfirmation.initialDecision(
                previous: previousWithoutWeekly,
                initial: initial)
                == .requiresConfirmation)
        #expect(
            CodexWeeklyResetConfirmation.initialDecision(
                previous: previousWithoutWeekly,
                initial: self.snapshot(offset: 1, weeklyUsed: 0.2, weeklyReset: nil))
                == .preservePrevious)
        #expect(
            CodexWeeklyResetConfirmation.confirmationDecision(
                previous: nil,
                initial: initial,
                confirmation: matching)
                == .publishConfirmation)
        #expect(
            CodexWeeklyResetConfirmation.confirmationDecision(
                previous: nil,
                initial: initial,
                confirmation: rebound)
                == .publishConfirmation)
    }

    @Test
    func reset_backfill_follows_semantic_lanes_when_cached_positions_are_swapped() {
        let sessionReset = self.resetAt.addingTimeInterval(60 * 60)
        let weeklyReset = self.resetAt.addingTimeInterval(7 * 24 * 60 * 60)
        let partial = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 9,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            updatedAt: self.capturedAt)
        let swappedCache = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 55,
                windowMinutes: 10080,
                resetsAt: weeklyReset,
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 44,
                windowMinutes: 300,
                resetsAt: sessionReset,
                resetDescription: nil),
            updatedAt: self.capturedAt.addingTimeInterval(-1))

        let backfilled = UsageStore.codexBackfillingResetWindows(partial, from: swappedCache)

        #expect(backfilled.primary?.usedPercent == 9)
        #expect(backfilled.primary?.windowMinutes == 300)
        #expect(backfilled.primary?.resetsAt == sessionReset)
        #expect(backfilled.secondary?.usedPercent == 55)
        #expect(backfilled.secondary?.windowMinutes == 10080)
        #expect(backfilled.secondary?.resetsAt == weeklyReset)
    }

    @Test
    func semantic_weekly_lookup_handles_swapped_snapshot_lanes() {
        let nextReset = self.resetAt.addingTimeInterval(7 * 24 * 60 * 60)
        let previous = self.snapshot(
            offset: 0,
            weeklyUsed: 50,
            weeklyReset: self.resetAt,
            weeklyInPrimary: true)
        let initial = self.snapshot(
            offset: 1,
            weeklyUsed: 0,
            weeklyReset: nextReset,
            weeklyInPrimary: true)
        let confirmation = self.snapshot(
            offset: 2,
            weeklyUsed: 0.5,
            weeklyReset: nextReset.addingTimeInterval(60),
            weeklyInPrimary: true)

        #expect(
            CodexWeeklyResetConfirmation.initialDecision(previous: previous, initial: initial)
                == .requiresConfirmation)
        #expect(
            CodexWeeklyResetConfirmation.confirmationDecision(
                previous: previous,
                initial: initial,
                confirmation: confirmation)
                == .publishConfirmation)
    }

    @Test
    func missing_candidate_weekly_data_and_reset_boundaries_fail_closed() {
        let previous = self.snapshot(offset: 0, weeklyUsed: 50, weeklyReset: self.resetAt)
        let missingWeekly = self.snapshot(offset: 1, weeklyUsed: nil, weeklyReset: nil)
        let initialWithoutBoundary = self.snapshot(offset: 1, weeklyUsed: 0, weeklyReset: nil)

        #expect(
            CodexWeeklyResetConfirmation.initialDecision(previous: previous, initial: missingWeekly)
                == .preservePrevious)
        #expect(
            CodexWeeklyResetConfirmation.initialDecision(previous: previous, initial: initialWithoutBoundary)
                == .preservePrevious)

        let initial = self.snapshot(
            offset: 1,
            weeklyUsed: 0,
            weeklyReset: self.resetAt.addingTimeInterval(7 * 24 * 60 * 60))
        #expect(
            CodexWeeklyResetConfirmation.confirmationDecision(
                previous: previous,
                initial: initial,
                confirmation: missingWeekly)
                == .preservePrevious)
    }

    @Test
    func two_valid_lows_establish_a_reset_when_the_previous_boundary_is_unavailable() {
        let nextReset = self.resetAt.addingTimeInterval(7 * 24 * 60 * 60)
        let initial = self.snapshot(offset: 1, weeklyUsed: 0.2, weeklyReset: nextReset)
        let confirmation = self.snapshot(
            offset: 2,
            weeklyUsed: 0.7,
            weeklyReset: nextReset.addingTimeInterval(30))
        let unavailablePreviousBoundaries: [Date?] = [
            nil,
            self.capturedAt.addingTimeInterval(-1),
            Date(timeIntervalSinceReferenceDate: .infinity),
        ]

        for previousBoundary in unavailablePreviousBoundaries {
            let previous = self.snapshot(offset: 0, weeklyUsed: 50, weeklyReset: previousBoundary)
            #expect(
                CodexWeeklyResetConfirmation.initialDecision(previous: previous, initial: initial)
                    == .requiresConfirmation)
            #expect(
                CodexWeeklyResetConfirmation.confirmationDecision(
                    previous: previous,
                    initial: initial,
                    confirmation: confirmation)
                    == .publishConfirmation)
        }
    }

    @Test
    func first_ordinary_high_accepts_a_missing_boundary_but_rejects_explicit_invalid_boundaries() {
        let missingBoundary = self.snapshot(offset: 1, weeklyUsed: 42, weeklyReset: nil)
        let elapsedBoundary = self.snapshot(
            offset: 1,
            weeklyUsed: 42,
            weeklyReset: self.capturedAt)
        let nonfiniteBoundary = self.snapshot(
            offset: 1,
            weeklyUsed: 42,
            weeklyReset: Date(timeIntervalSinceReferenceDate: .infinity))

        #expect(
            CodexWeeklyResetConfirmation.initialDecision(previous: nil, initial: missingBoundary)
                == .publishInitial)
        #expect(
            CodexWeeklyResetConfirmation.initialDecision(previous: nil, initial: elapsedBoundary)
                == .preservePrevious)
        #expect(
            CodexWeeklyResetConfirmation.initialDecision(previous: nil, initial: nonfiniteBoundary)
                == .preservePrevious)
    }

    @Test
    func newer_rebound_publishes_instead_of_accepting_the_transient_low() {
        let nextReset = self.resetAt.addingTimeInterval(7 * 24 * 60 * 60)
        let previous = self.snapshot(offset: 0, weeklyUsed: 50, weeklyReset: self.resetAt)
        let initial = self.snapshot(offset: 1, weeklyUsed: 0, weeklyReset: nextReset)
        let confirmation = self.snapshot(offset: 2, weeklyUsed: 49, weeklyReset: self.resetAt)

        #expect(
            CodexWeeklyResetConfirmation.confirmationDecision(
                previous: previous,
                initial: initial,
                confirmation: confirmation)
                == .publishConfirmation)
    }

    @Test
    func two_low_observations_publish_only_for_an_advanced_equivalent_boundary() {
        let nextReset = self.resetAt.addingTimeInterval(7 * 24 * 60 * 60)
        let previous = self.snapshot(offset: 0, weeklyUsed: 50, weeklyReset: self.resetAt)
        let initial = self.snapshot(offset: 1, weeklyUsed: 0, weeklyReset: nextReset)
        let confirmation = self.snapshot(
            offset: 2,
            weeklyUsed: 0.5,
            weeklyReset: nextReset.addingTimeInterval(119))

        #expect(
            CodexWeeklyResetConfirmation.confirmationDecision(
                previous: previous,
                initial: initial,
                confirmation: confirmation)
                == .publishConfirmation)
    }

    @Test
    func unchanged_regressed_and_mismatched_reset_boundaries_preserve_the_previous_snapshot() {
        let previous = self.snapshot(offset: 0, weeklyUsed: 50, weeklyReset: self.resetAt)
        let unchanged = self.snapshot(offset: 1, weeklyUsed: 0, weeklyReset: self.resetAt)
        let regressed = self.snapshot(
            offset: 1,
            weeklyUsed: 0,
            weeklyReset: self.resetAt.addingTimeInterval(-1))
        let advanced = self.resetAt.addingTimeInterval(7 * 24 * 60 * 60)
        let initial = self.snapshot(offset: 1, weeklyUsed: 0, weeklyReset: advanced)
        let mismatched = self.snapshot(
            offset: 2,
            weeklyUsed: 0,
            weeklyReset: advanced.addingTimeInterval(120))
        let jitteredInitial = self.snapshot(
            offset: 1,
            weeklyUsed: 0,
            weeklyReset: self.resetAt.addingTimeInterval(60))
        let jitteredConfirmation = self.snapshot(
            offset: 2,
            weeklyUsed: 0.5,
            weeklyReset: self.resetAt.addingTimeInterval(90))

        for candidate in [unchanged, regressed] {
            #expect(
                CodexWeeklyResetConfirmation.initialDecision(previous: previous, initial: candidate)
                    == .requiresConfirmation)
            #expect(
                CodexWeeklyResetConfirmation.confirmationDecision(
                    previous: previous,
                    initial: candidate,
                    confirmation: self.snapshot(offset: 2, weeklyUsed: 50, weeklyReset: self.resetAt))
                    == .publishConfirmation)
            #expect(
                CodexWeeklyResetConfirmation.confirmationDecision(
                    previous: previous,
                    initial: candidate,
                    confirmation: self.snapshot(
                        offset: 2,
                        weeklyUsed: 0,
                        weeklyReset: candidate.secondary?.resetsAt))
                    == .preservePrevious)
        }
        #expect(
            CodexWeeklyResetConfirmation.confirmationDecision(
                previous: previous,
                initial: initial,
                confirmation: mismatched)
                == .preservePrevious)
        #expect(
            CodexWeeklyResetConfirmation.confirmationDecision(
                previous: previous,
                initial: jitteredInitial,
                confirmation: jitteredConfirmation)
                == .preservePrevious)
    }

    @Test
    func stale_confirmations_preserve_the_previous_snapshot() {
        let nextReset = self.resetAt.addingTimeInterval(7 * 24 * 60 * 60)
        let previous = self.snapshot(offset: 0, weeklyUsed: 50, weeklyReset: self.resetAt)
        let initial = self.snapshot(offset: 2, weeklyUsed: 0, weeklyReset: nextReset)
        let stale = self.snapshot(offset: 2, weeklyUsed: 50, weeklyReset: self.resetAt)

        #expect(
            CodexWeeklyResetConfirmation.confirmationDecision(
                previous: previous,
                initial: initial,
                confirmation: stale)
                == .preservePrevious)
    }

    @Test
    func elapsed_and_materially_regressed_boundaries_preserve_the_previous_snapshot() {
        let nextReset = self.resetAt.addingTimeInterval(7 * 24 * 60 * 60)
        let high = self.snapshot(offset: 0, weeklyUsed: 50, weeklyReset: self.resetAt)
        let elapsedLow = self.snapshot(
            capturedAt: self.resetAt.addingTimeInterval(1),
            weeklyUsed: 0,
            weeklyReset: self.resetAt)
        let confirmedReset = self.snapshot(offset: 2, weeklyUsed: 0, weeklyReset: nextReset)
        let stalePreReset = self.snapshot(offset: 3, weeklyUsed: 50, weeklyReset: self.resetAt)
        let elapsedConfirmation = self.snapshot(
            capturedAt: nextReset.addingTimeInterval(1),
            weeklyUsed: 0,
            weeklyReset: nextReset)

        #expect(
            CodexWeeklyResetConfirmation.initialDecision(previous: high, initial: elapsedLow)
                == .preservePrevious)
        #expect(
            CodexWeeklyResetConfirmation.initialDecision(previous: confirmedReset, initial: stalePreReset)
                == .preservePrevious)
        #expect(
            CodexWeeklyResetConfirmation.confirmationDecision(
                previous: high,
                initial: self.snapshot(offset: 1, weeklyUsed: 0, weeklyReset: nextReset),
                confirmation: elapsedConfirmation)
                == .preservePrevious)
    }

    @Test
    func nonfinite_percentages_timestamps_and_boundaries_fail_closed() {
        let previous = self.snapshot(offset: 0, weeklyUsed: 50, weeklyReset: self.resetAt)
        let initial = self.snapshot(offset: 1, weeklyUsed: 0, weeklyReset: self.resetAt.addingTimeInterval(100))
        let nonfiniteBoundary = Date(timeIntervalSinceReferenceDate: .infinity)

        #expect(
            CodexWeeklyResetConfirmation.initialDecision(
                previous: previous,
                initial: self.snapshot(offset: 1, weeklyUsed: .nan, weeklyReset: self.resetAt))
                == .preservePrevious)
        #expect(
            CodexWeeklyResetConfirmation.initialDecision(
                previous: previous,
                initial: self.snapshot(offset: 1, weeklyUsed: 0, weeklyReset: nonfiniteBoundary))
                == .preservePrevious)
        #expect(
            CodexWeeklyResetConfirmation.initialDecision(
                previous: previous,
                initial: self.snapshot(
                    capturedAt: Date(timeIntervalSinceReferenceDate: .infinity),
                    weeklyUsed: 0,
                    weeklyReset: self.resetAt))
                == .preservePrevious)
        #expect(
            CodexWeeklyResetConfirmation.confirmationDecision(
                previous: previous,
                initial: initial,
                confirmation: self.snapshot(offset: 2, weeklyUsed: .infinity, weeklyReset: self.resetAt))
                == .preservePrevious)
    }

    private func snapshot(
        offset: TimeInterval,
        weeklyUsed: Double?,
        weeklyReset: Date?,
        weeklyInPrimary: Bool = false) -> UsageSnapshot
    {
        self.snapshot(
            capturedAt: self.capturedAt.addingTimeInterval(offset),
            weeklyUsed: weeklyUsed,
            weeklyReset: weeklyReset,
            weeklyInPrimary: weeklyInPrimary)
    }

    private func snapshot(
        capturedAt: Date,
        weeklyUsed: Double?,
        weeklyReset: Date?,
        weeklyInPrimary: Bool = false) -> UsageSnapshot
    {
        let weekly = weeklyUsed.map {
            RateWindow(
                usedPercent: $0,
                windowMinutes: 10080,
                resetsAt: weeklyReset,
                resetDescription: nil)
        }
        let session = RateWindow(
            usedPercent: 25,
            windowMinutes: 300,
            resetsAt: self.resetAt,
            resetDescription: nil)
        return UsageSnapshot(
            primary: weeklyInPrimary ? weekly : session,
            secondary: weeklyInPrimary ? session : weekly,
            updatedAt: capturedAt)
    }
}
