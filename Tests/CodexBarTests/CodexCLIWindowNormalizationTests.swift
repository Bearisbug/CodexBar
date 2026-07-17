import Foundation
import Testing
@testable import CodexBarCore

struct CodexCLIWindowNormalizationTests {
    @Test
    func normalizer_maps_lone_weekly_window_into_secondary() {
        let weekly = RateWindow(
            usedPercent: 5,
            windowMinutes: 10080,
            resetsAt: nil,
            resetDescription: nil)

        let normalized = CodexRateWindowNormalizer._normalizeForTesting(primary: weekly, secondary: nil)
        #expect(normalized.primary == nil)
        #expect(normalized.secondary?.usedPercent == 5)
        #expect(normalized.secondary?.windowMinutes == 10080)
    }

    @Test
    func normalizer_keeps_lone_session_window_in_primary() {
        let session = RateWindow(
            usedPercent: 31,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: nil)

        let normalized = CodexRateWindowNormalizer._normalizeForTesting(primary: session, secondary: nil)
        #expect(normalized.primary?.usedPercent == 31)
        #expect(normalized.primary?.windowMinutes == 300)
        #expect(normalized.secondary == nil)
    }

    @Test
    func normalizer_keeps_session_and_weekly_ordering_unchanged() {
        let session = RateWindow(
            usedPercent: 31,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: nil)
        let weekly = RateWindow(
            usedPercent: 26,
            windowMinutes: 10080,
            resetsAt: nil,
            resetDescription: nil)

        let normalized = CodexRateWindowNormalizer._normalizeForTesting(primary: session, secondary: weekly)
        #expect(normalized.primary?.usedPercent == 31)
        #expect(normalized.primary?.windowMinutes == 300)
        #expect(normalized.secondary?.usedPercent == 26)
        #expect(normalized.secondary?.windowMinutes == 10080)
    }

    @Test
    func normalizer_swaps_reversed_weekly_and_unknown_windows() {
        let weekly = RateWindow(
            usedPercent: 43,
            windowMinutes: 10080,
            resetsAt: nil,
            resetDescription: nil)
        let unknown = RateWindow(
            usedPercent: 17,
            windowMinutes: 540,
            resetsAt: nil,
            resetDescription: nil)

        let normalized = CodexRateWindowNormalizer._normalizeForTesting(primary: weekly, secondary: unknown)
        #expect(normalized.primary?.usedPercent == 17)
        #expect(normalized.primary?.windowMinutes == 540)
        #expect(normalized.secondary?.usedPercent == 43)
        #expect(normalized.secondary?.windowMinutes == 10080)
    }

    @Test
    func maps_weekly_only_RPC_limits_into_secondary() throws {
        let snapshot = try UsageFetcher._mapCodexRPCLimitsForTesting(
            primary: (usedPercent: 5, windowMinutes: 10080, resetsAt: nil),
            secondary: nil)

        #expect(snapshot.primary == nil)
        #expect(snapshot.secondary?.usedPercent == 5)
        #expect(snapshot.secondary?.windowMinutes == 10080)
    }

    @Test
    func maps_session_only_RPC_limits_into_primary() throws {
        let snapshot = try UsageFetcher._mapCodexRPCLimitsForTesting(
            primary: (usedPercent: 31, windowMinutes: 300, resetsAt: nil),
            secondary: nil)

        #expect(snapshot.primary?.usedPercent == 31)
        #expect(snapshot.primary?.windowMinutes == 300)
        #expect(snapshot.secondary == nil)
    }

    @Test
    func maps_reversed_weekly_and_unknown_RPC_limits() throws {
        let snapshot = try UsageFetcher._mapCodexRPCLimitsForTesting(
            primary: (usedPercent: 43, windowMinutes: 10080, resetsAt: nil),
            secondary: (usedPercent: 17, windowMinutes: 540, resetsAt: nil))

        #expect(snapshot.primary?.usedPercent == 17)
        #expect(snapshot.primary?.windowMinutes == 540)
        #expect(snapshot.secondary?.usedPercent == 43)
        #expect(snapshot.secondary?.windowMinutes == 10080)
    }

    @Test
    func throws_when_RPC_limits_contain_no_windows() {
        #expect(throws: UsageError.noRateLimitsFound) {
            try UsageFetcher._mapCodexRPCLimitsForTesting(primary: nil, secondary: nil)
        }
    }

    @Test
    func maps_plan_only_RPC_limits_into_empty_identified_snapshot() throws {
        let snapshot = try UsageFetcher._mapCodexRPCLimitsForTesting(
            primary: nil,
            secondary: nil,
            planType: "pro")

        #expect(snapshot.primary == nil)
        #expect(snapshot.secondary == nil)
        #expect(snapshot.loginMethod(for: .codex) == "pro")
        #expect(snapshot.rateLimitsUnavailable(for: .codex))
    }

    @Test
    func codex_no_rate_limit_error_means_limits_unavailable_without_snapshot() {
        let availability = UsageLimitsAvailability.resolve(
            provider: .codex,
            snapshot: nil,
            account: AccountInfo(email: "user@example.com", plan: nil),
            lastErrorDescription: UsageError.noRateLimitsFound.errorDescription)

        #expect(availability == .unavailable)
    }

    @Test
    func codex_no_rate_limit_error_stays_available_without_account_context() {
        let availability = UsageLimitsAvailability.resolve(
            provider: .codex,
            snapshot: nil,
            account: AccountInfo(email: nil, plan: nil),
            lastErrorDescription: UsageError.noRateLimitsFound.errorDescription)

        #expect(availability == .available)
    }

    @Test
    func codex_windowed_snapshot_wins_over_stale_no_rate_limit_error() {
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: "user@example.com",
            accountOrganization: nil,
            loginMethod: "pro")
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 25,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            updatedAt: Date(),
            identity: identity)
        let availability = UsageLimitsAvailability.resolve(
            provider: .codex,
            snapshot: snapshot,
            lastErrorDescription: UsageError.noRateLimitsFound.errorDescription)

        #expect(availability == .available)
    }

    @Test
    func maps_weekly_only_status_snapshot_into_secondary() throws {
        let status = CodexStatusSnapshot(
            credits: nil,
            fiveHourPercentLeft: nil,
            weeklyPercentLeft: 95,
            fiveHourResetDescription: nil,
            weeklyResetDescription: "resets next week",
            fiveHourResetsAt: nil,
            weeklyResetsAt: nil,
            rawText: "Weekly limit: 95% left")

        let snapshot = try UsageFetcher._mapCodexStatusForTesting(status)
        #expect(snapshot.primary == nil)
        #expect(snapshot.secondary?.usedPercent == 5)
        #expect(snapshot.secondary?.windowMinutes == 10080)
    }

    @Test
    func maps_five_hour_only_status_snapshot_into_primary() throws {
        let status = CodexStatusSnapshot(
            credits: nil,
            fiveHourPercentLeft: 69,
            weeklyPercentLeft: nil,
            fiveHourResetDescription: "resets soon",
            weeklyResetDescription: nil,
            fiveHourResetsAt: nil,
            weeklyResetsAt: nil,
            rawText: "5h limit: 69% left")

        let snapshot = try UsageFetcher._mapCodexStatusForTesting(status)
        #expect(snapshot.primary?.usedPercent == 31)
        #expect(snapshot.primary?.windowMinutes == 300)
        #expect(snapshot.secondary == nil)
    }

    @Test
    func throws_when_status_snapshot_contains_no_windows() {
        let status = CodexStatusSnapshot(
            credits: nil,
            fiveHourPercentLeft: nil,
            weeklyPercentLeft: nil,
            fiveHourResetDescription: nil,
            weeklyResetDescription: nil,
            fiveHourResetsAt: nil,
            weeklyResetsAt: nil,
            rawText: "")

        #expect(throws: UsageError.noRateLimitsFound) {
            try UsageFetcher._mapCodexStatusForTesting(status)
        }
    }
}
