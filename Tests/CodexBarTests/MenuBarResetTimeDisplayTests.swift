import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct MenuBarResetTimeDisplayTests {
    @Test
    func reset_time_mode_formats_the_selected_window_reset() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let resetsAt = now.addingTimeInterval(2 * 3600)
        let window = RateWindow(
            usedPercent: 42,
            windowMinutes: 300,
            resetsAt: resetsAt,
            resetDescription: nil)

        let text = MenuBarDisplayText.displayText(
            mode: .resetTime,
            percentWindow: window,
            showUsed: true,
            resetTimeDisplayStyle: .absolute,
            now: now)

        #expect(text == "↻ \(UsageFormatter.resetDescription(from: resetsAt, now: now))")
    }

    @Test
    func reset_time_mode_uses_countdown_preference() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let resetsAt = now.addingTimeInterval(2 * 3600 + 15 * 60)
        let window = RateWindow(
            usedPercent: 42,
            windowMinutes: 300,
            resetsAt: resetsAt,
            resetDescription: nil)

        let text = MenuBarDisplayText.displayText(
            mode: .resetTime,
            percentWindow: window,
            showUsed: true,
            resetTimeDisplayStyle: .countdown,
            now: now)

        #expect(text == "↻ in 2h 15m")
    }

    @Test
    func reset_time_mode_falls_back_to_used_percent_without_reset_metadata() {
        let window = RateWindow(
            usedPercent: 42,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: nil)

        let text = MenuBarDisplayText.displayText(
            mode: .resetTime,
            percentWindow: window,
            showUsed: true)

        #expect(text == "42%")
    }

    @Test
    func reset_time_mode_uses_text_reset_metadata() {
        let window = RateWindow(
            usedPercent: 42,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: "in 2h 15m")

        let text = MenuBarDisplayText.displayText(
            mode: .resetTime,
            percentWindow: window,
            showUsed: true)

        #expect(text == "↻ in 2h 15m")
    }

    @Test
    func reset_time_mode_surfaces_daily_reset_metadata() {
        let window = RateWindow(
            usedPercent: 39,
            windowMinutes: 1440,
            resetsAt: nil,
            resetDescription: "resets daily")

        let text = MenuBarDisplayText.displayText(
            mode: .resetTime,
            percentWindow: window,
            showUsed: true)

        #expect(text == "↻ resets daily")
    }

    @Test(arguments: [
        "Resets in 2h",
        "tomorrow, 3:00 PM",
        "next week",
        "expires in 4d",
    ])
    func reset_time_mode_accepts_reset_timing_phrases(_ description: String) {
        let window = RateWindow(
            usedPercent: 42,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: description)

        let text = MenuBarDisplayText.displayText(
            mode: .resetTime,
            percentWindow: window,
            showUsed: true)

        #expect(text == "↻ \(description)")
    }

    @Test(arguments: [
        "250/1000 requests",
        "160 requests",
        "5 hours window",
        "$10.00 available",
    ])
    func reset_time_mode_rejects_non_reset_provider_summaries(_ description: String) {
        let window = RateWindow(
            usedPercent: 42,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: description)

        let text = MenuBarDisplayText.displayText(
            mode: .resetTime,
            percentWindow: window,
            showUsed: true)

        #expect(text == "42%")
    }

    @Test
    func reset_time_mode_falls_back_to_remaining_percent_without_reset_metadata() {
        let window = RateWindow(
            usedPercent: 42,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: nil)

        let text = MenuBarDisplayText.displayText(
            mode: .resetTime,
            percentWindow: window,
            showUsed: false)

        #expect(text == "58%")
    }

    @Test(arguments: [MenuBarDisplayMode.percent, .pace, .both])
    func smart_reset_shows_countdown_when_the_quota_is_exhausted(_ mode: MenuBarDisplayMode) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let window = RateWindow(
            usedPercent: 100,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(2 * 3600 + 15 * 60),
            resetDescription: nil)

        let text = MenuBarDisplayText.displayText(
            mode: mode,
            percentWindow: window,
            showUsed: false,
            resetTimeDisplayStyle: .countdown,
            showsResetTimeWhenExhausted: true,
            now: now)

        #expect(text == "↻ in 2h 15m")
    }

    @Test
    func smart_reset_honors_the_absolute_clock_preference() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let resetsAt = now.addingTimeInterval(2 * 3600)
        let window = RateWindow(
            usedPercent: 100,
            windowMinutes: 300,
            resetsAt: resetsAt,
            resetDescription: nil)

        let text = MenuBarDisplayText.displayText(
            mode: .percent,
            percentWindow: window,
            showUsed: false,
            resetTimeDisplayStyle: .absolute,
            showsResetTimeWhenExhausted: true,
            now: now)

        #expect(text == "↻ \(UsageFormatter.resetDescription(from: resetsAt, now: now))")
    }

    @Test
    func smart_reset_leaves_a_non_exhausted_quota_untouched() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let window = RateWindow(
            usedPercent: 42,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(3600),
            resetDescription: nil)

        let text = MenuBarDisplayText.displayText(
            mode: .percent,
            percentWindow: window,
            showUsed: false,
            showsResetTimeWhenExhausted: true,
            now: now)

        #expect(text == "58%")
    }

    @Test
    func smart_reset_disabled_keeps_the_exhausted_percent() {
        let window = RateWindow(
            usedPercent: 100,
            windowMinutes: 300,
            resetsAt: Date(timeIntervalSince1970: 1_800_000_000),
            resetDescription: nil)

        let text = MenuBarDisplayText.displayText(
            mode: .percent,
            percentWindow: window,
            showUsed: false)

        #expect(text == "0%")
    }

    @Test
    func smart_reset_falls_back_to_percent_once_the_reset_has_elapsed() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // Exhausted window whose reset moment is already in the past (e.g. snapshot lingering at 100%
        // before the next provider refresh). Showing "↻ now" here would be stale and could stick.
        let window = RateWindow(
            usedPercent: 100,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(-60),
            resetDescription: nil)

        let text = MenuBarDisplayText.displayText(
            mode: .percent,
            percentWindow: window,
            showUsed: false,
            resetTimeDisplayStyle: .countdown,
            showsResetTimeWhenExhausted: true,
            now: now)

        #expect(text == "0%")
    }

    @Test
    func smart_reset_ignores_textual_reset_metadata_without_a_concrete_reset_time() {
        // Provider supplies only a textual resetDescription (no resetsAt). The smart option can't hand
        // that to the refresh scheduler, so it keeps the percent rather than freezing on "↻ in 2h".
        let window = RateWindow(
            usedPercent: 100,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: "in 2h")

        let text = MenuBarDisplayText.displayText(
            mode: .percent,
            percentWindow: window,
            showUsed: false,
            showsResetTimeWhenExhausted: true)

        #expect(text == "0%")
        // Reset-time mode still surfaces the textual metadata (unchanged behavior).
        let resetTimeText = MenuBarDisplayText.displayText(
            mode: .resetTime,
            percentWindow: window,
            showUsed: false)
        #expect(resetTimeText == "↻ in 2h")
    }

    @Test
    func smart_reset_falls_back_to_percent_without_reset_metadata() {
        let window = RateWindow(
            usedPercent: 100,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: nil)

        let text = MenuBarDisplayText.displayText(
            mode: .percent,
            percentWindow: window,
            showUsed: false,
            showsResetTimeWhenExhausted: true)

        #expect(text == "0%")
    }

    @Test(arguments: [MenuBarDisplayMode.pace, .both])
    func smart_reset_keeps_exhausted_percent_when_pace_exists_but_reset_is_unusable(_ mode: MenuBarDisplayMode) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let window = RateWindow(
            usedPercent: 100,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(-60),
            resetDescription: nil)
        let pace = UsagePace(
            stage: .ahead,
            deltaPercent: 12,
            expectedUsedPercent: 40,
            actualUsedPercent: 52,
            etaSeconds: nil,
            willLastToReset: true)

        let text = MenuBarDisplayText.displayText(
            mode: mode,
            percentWindow: window,
            pace: pace,
            showUsed: false,
            showsResetTimeWhenExhausted: true,
            now: now)

        #expect(text == "0%")
    }

    @Test
    func smart_reset_does_not_alter_reset_time_mode() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let resetsAt = now.addingTimeInterval(3600)
        let window = RateWindow(
            usedPercent: 42,
            windowMinutes: 300,
            resetsAt: resetsAt,
            resetDescription: nil)

        let text = MenuBarDisplayText.displayText(
            mode: .resetTime,
            percentWindow: window,
            showUsed: false,
            resetTimeDisplayStyle: .countdown,
            showsResetTimeWhenExhausted: true,
            now: now)

        #expect(text == "↻ in 1h")
    }

    @Test
    func smart_reset_replaces_only_the_exhausted_lane_in_combined_text() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = RateWindow(
            usedPercent: 100,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(2 * 3600 + 15 * 60),
            resetDescription: nil)
        let weekly = RateWindow(
            usedPercent: 55,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(3 * 86400),
            resetDescription: nil)

        let text = MenuBarDisplayText.combinedSessionWeeklyPercentText(
            sessionWindow: session,
            weeklyWindow: weekly,
            showUsed: false,
            resetTimeDisplayStyle: .countdown,
            showsResetTimeWhenExhausted: true,
            now: now)

        #expect(text == "5h ↻ in 2h 15m · W 45%")
    }
}
