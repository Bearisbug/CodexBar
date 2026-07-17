import Foundation
import Testing
@testable import CodexBar

struct OpenAIWebRefreshGateTests {
    @Test
    func Battery_saver_keeps_background_OpenAI_web_refreshes_off() {
        let shouldRun = UsageStore.shouldRunOpenAIWebRefresh(.init(
            accessEnabled: true,
            batterySaverEnabled: true,
            force: false,
            refreshPhase: .regular))

        #expect(shouldRun == false)
    }

    @Test
    func Disabling_battery_saver_restores_normal_OpenAI_web_refreshes() {
        let shouldRun = UsageStore.shouldRunOpenAIWebRefresh(.init(
            accessEnabled: true,
            batterySaverEnabled: false,
            force: false,
            refreshPhase: .regular))

        #expect(shouldRun == true)
    }

    @Test
    func Manual_refresh_still_forces_OpenAI_web_refreshes_with_battery_saver_enabled() {
        let shouldRun = UsageStore.shouldRunOpenAIWebRefresh(.init(
            accessEnabled: true,
            batterySaverEnabled: true,
            force: true,
            refreshPhase: .regular))

        #expect(shouldRun == true)
    }

    @Test
    func Startup_skips_automatic_OpenAI_web_refreshes() {
        let shouldRun = UsageStore.shouldRunOpenAIWebRefresh(.init(
            accessEnabled: true,
            batterySaverEnabled: false,
            force: false,
            refreshPhase: .startup))

        #expect(shouldRun == false)
    }

    @Test
    func Startup_connectivity_retry_remains_startup_only_for_OpenAI_web_refresh_gate() {
        let providerPhase = UsageStore.refreshPhase(
            hasCompletedInitialRefresh: true)
        let openAIWebPhase = UsageStore.openAIWebRefreshPhase(
            providerRefreshPhase: providerPhase,
            startupConnectivityRetryAttempt: 1)
        let shouldRun = UsageStore.shouldRunOpenAIWebRefresh(.init(
            accessEnabled: true,
            batterySaverEnabled: false,
            force: false,
            refreshPhase: openAIWebPhase))

        #expect(providerPhase == .regular)
        #expect(openAIWebPhase == .startup)
        #expect(shouldRun == false)
    }

    @Test
    func Manual_startup_refresh_still_forces_OpenAI_web_refreshes() {
        let shouldRun = UsageStore.shouldRunOpenAIWebRefresh(.init(
            accessEnabled: true,
            batterySaverEnabled: true,
            force: true,
            refreshPhase: .startup))

        #expect(shouldRun == true)
    }

    @Test
    func Battery_saver_stale_submenu_refresh_respects_the_cooldown() {
        let shouldForce = UsageStore.forceOpenAIWebRefreshForStaleRequest(batterySaverEnabled: true)

        #expect(shouldForce == false)
    }

    @Test
    func Normal_stale_submenu_refresh_still_forces_when_battery_saver_is_off() {
        let shouldForce = UsageStore.forceOpenAIWebRefreshForStaleRequest(batterySaverEnabled: false)

        #expect(shouldForce == true)
    }

    @Test
    func Recent_successful_dashboard_refresh_stays_throttled() {
        let now = Date()

        let shouldSkip = UsageStore.shouldSkipOpenAIWebRefresh(.init(
            force: false,
            accountDidChange: false,
            lastError: nil,
            lastSnapshotAt: now.addingTimeInterval(-60),
            lastAttemptAt: now.addingTimeInterval(-60),
            now: now,
            refreshInterval: 300))

        #expect(shouldSkip == true)
    }

    @Test
    func Recent_failed_dashboard_refresh_also_stays_throttled() {
        let now = Date()

        let shouldSkip = UsageStore.shouldSkipOpenAIWebRefresh(.init(
            force: false,
            accountDidChange: false,
            lastError: "login required",
            lastSnapshotAt: nil,
            lastAttemptAt: now.addingTimeInterval(-60),
            now: now,
            refreshInterval: 300))

        #expect(shouldSkip == true)
    }

    @Test
    func Force_refresh_bypasses_throttle_after_failures() {
        let now = Date()

        let shouldSkip = UsageStore.shouldSkipOpenAIWebRefresh(.init(
            force: true,
            accountDidChange: false,
            lastError: "login required",
            lastSnapshotAt: nil,
            lastAttemptAt: now.addingTimeInterval(-60),
            now: now,
            refreshInterval: 300))

        #expect(shouldSkip == false)
    }

    @Test
    func Account_switches_bypass_the_prior_attempt_cooldown() {
        let now = Date()

        let shouldSkip = UsageStore.shouldSkipOpenAIWebRefresh(.init(
            force: false,
            accountDidChange: true,
            lastError: "mismatch",
            lastSnapshotAt: nil,
            lastAttemptAt: now.addingTimeInterval(-60),
            now: now,
            refreshInterval: 300))

        #expect(shouldSkip == false)
    }

    @Test
    func Empty_dashboard_history_retry_is_throttled_after_a_recent_attempt() {
        let now = Date()

        let shouldSkip = UsageStore.shouldSkipOpenAIWebEmptyHistoryRetry(.init(
            force: false,
            accountDidChange: false,
            lastError: nil,
            lastSnapshotAt: now.addingTimeInterval(-120),
            lastAttemptAt: now.addingTimeInterval(-60),
            now: now,
            refreshInterval: 300))

        #expect(shouldSkip == true)
    }

    @Test
    func Empty_dashboard_history_retry_runs_once_for_a_newer_empty_snapshot() {
        let now = Date()

        let shouldSkip = UsageStore.shouldSkipOpenAIWebEmptyHistoryRetry(.init(
            force: false,
            accountDidChange: false,
            lastError: nil,
            lastSnapshotAt: now.addingTimeInterval(-60),
            lastAttemptAt: now.addingTimeInterval(-120),
            now: now,
            refreshInterval: 300))

        #expect(shouldSkip == false)
    }
}
