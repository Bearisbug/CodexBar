import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct UsagePaceTextTests {
    private static let localizedKeys: [String] = [
        "Pace: %@",
        "Pace: %@ · %@",
        "On pace",
        "%d%% in deficit",
        "%d%% in reserve",
        "Lasts until reset",
        "Projected empty now",
        "Projected empty in %@",
        "Runs out now",
        "Runs out in %@",
        "1.5× headroom",
        "≈ %d%% run-out risk",
        "%@ · %@",
    ]

    @Test
    func weekly_pace_detail_provides_left_right_labels() throws {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 50,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(4 * 24 * 3600),
            resetDescription: nil)
        let pace = try #require(UsagePace.weekly(window: window, now: now))

        let detail = UsagePaceText.weeklyDetail(provider: .codex, pace: pace, now: now)

        #expect(detail.leftLabel == "7% in deficit")
        #expect(detail.rightLabel == "Runs out in 3d")
    }

    @Test
    func weekly_pace_detail_treats_rounded_zero_delta_as_on_pace() {
        let now = Date(timeIntervalSince1970: 0)
        let pace = UsagePace(
            stage: .slightlyBehind,
            deltaPercent: -0.4,
            expectedUsedPercent: 50.4,
            actualUsedPercent: 50,
            etaSeconds: nil,
            willLastToReset: true)

        let detail = UsagePaceText.weeklyDetail(provider: .codex, pace: pace, now: now)

        #expect(detail.leftLabel == "On pace")
    }

    @Test
    func weekly_pace_detail_reports_lasts_until_reset() throws {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 10,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(4 * 24 * 3600),
            resetDescription: nil)
        let pace = try #require(UsagePace.weekly(window: window, now: now))

        let detail = UsagePaceText.weeklyDetail(provider: .codex, pace: pace, now: now)

        #expect(detail.leftLabel == "33% in reserve")
        #expect(detail.rightLabel == "Lasts until reset · 1.5× headroom")
    }

    @Test
    func weekly_pace_summary_formats_single_line_text() throws {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 50,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(4 * 24 * 3600),
            resetDescription: nil)
        let pace = try #require(UsagePace.weekly(window: window, now: now))

        let summary = UsagePaceText.weeklySummary(provider: .codex, pace: pace, now: now)

        #expect(summary == "Pace: 7% in deficit · Runs out in 3d")
    }

    @Test
    func weekly_pace_detail_reports_capped_speed_headroom_when_under_pace() throws {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 20,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(3 * 24 * 3600),
            resetDescription: nil)
        let pace = try #require(UsagePace.weekly(window: window, now: now))

        let detail = UsagePaceText.weeklyDetail(provider: .codex, pace: pace, now: now)

        #expect(detail.leftLabel == "37% in reserve")
        #expect(detail.rightLabel == "Lasts until reset · 1.5× headroom")
    }

    @Test
    func weekly_pace_detail_limits_headroom_hint_to_Codex() throws {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 20,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(3 * 24 * 3600),
            resetDescription: nil)
        let pace = try #require(UsagePace.weekly(window: window, now: now))

        let detail = UsagePaceText.weeklyDetail(provider: .claude, pace: pace, now: now)

        #expect(detail.rightLabel == "Lasts until reset")
    }

    @Test
    func weekly_pace_detail_reports_remaining_headroom_late_in_window() throws {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 70,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(0.7 * 24 * 3600),
            resetDescription: nil)
        let pace = try #require(UsagePace.weekly(window: window, now: now))

        let detail = UsagePaceText.weeklyDetail(provider: .codex, pace: pace, now: now)

        #expect(detail.leftLabel == "20% in reserve")
        #expect(detail.rightLabel == "Lasts until reset · 1.5× headroom")
    }

    @Test
    func reported_weekly_state_renders_deficit_and_run_out_headline() throws {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 88,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval((2 * 24 + 19) * 3600),
            resetDescription: nil)
        let pace = try #require(UsagePace.weekly(window: window, now: now, workDays: nil))

        let detail = UsagePaceText.weeklyDetail(provider: .codex, pace: pace, now: now)

        #expect(detail.leftLabel == "28% in deficit")
        #expect(detail.rightLabel == "Runs out in 13h 47m")
        #expect(detail.rightLabel?.contains("Lasts until reset") == false)
    }

    @Test
    func weekly_pace_detail_formats_rounded_risk_when_available() {
        let now = Date(timeIntervalSince1970: 0)
        let pace = UsagePace(
            stage: .ahead,
            deltaPercent: 8,
            expectedUsedPercent: 42,
            actualUsedPercent: 50,
            etaSeconds: 2 * 24 * 3600,
            willLastToReset: false,
            runOutProbability: 0.683)

        let detail = UsagePaceText.weeklyDetail(provider: .codex, pace: pace, now: now)

        #expect(detail.rightLabel == "Runs out in 2d · ≈ 70% run-out risk")
    }

    @Test
    func weekly_pace_detail_does_not_combine_lasts_until_reset_with_run_out_risk() {
        let now = Date(timeIntervalSince1970: 0)
        let pace = UsagePace(
            stage: .slightlyBehind,
            deltaPercent: -9,
            expectedUsedPercent: 21,
            actualUsedPercent: 12,
            etaSeconds: nil,
            willLastToReset: true,
            runOutProbability: 0.45)

        let detail = UsagePaceText.weeklyDetail(provider: .codex, pace: pace, now: now)

        #expect(detail.leftLabel == "9% in reserve")
        #expect(detail.rightLabel == "≈ 45% run-out risk")
    }

    @Test
    func weekly_pace_detail_keeps_lasts_until_reset_only_when_rounded_risk_is_zero() {
        let now = Date(timeIntervalSince1970: 0)
        let pace = UsagePace(
            stage: .farBehind,
            deltaPercent: -30,
            expectedUsedPercent: 40,
            actualUsedPercent: 10,
            etaSeconds: nil,
            willLastToReset: true,
            runOutProbability: 0.02,
            speedMultiplierToReset: 4)

        let detail = UsagePaceText.weeklyDetail(provider: .codex, pace: pace, now: now)

        #expect(detail.rightLabel == "Lasts until reset · 1.5× headroom · ≈ 0% run-out risk")
    }

    @Test
    func weekly_pace_detail_prefers_risk_over_lasts_until_reset_when_rounded_risk_is_material() {
        let now = Date(timeIntervalSince1970: 0)
        let pace = UsagePace(
            stage: .slightlyBehind,
            deltaPercent: -9,
            expectedUsedPercent: 21,
            actualUsedPercent: 12,
            etaSeconds: nil,
            willLastToReset: true,
            runOutProbability: 0.03)

        let detail = UsagePaceText.weeklyDetail(provider: .codex, pace: pace, now: now)

        #expect(detail.rightLabel == "≈ 5% run-out risk")
    }

    // MARK: - Session pace (5-hour window)

    @Test
    func session_pace_detail_provides_left_right_labels() {
        let now = Date(timeIntervalSince1970: 0)
        // 300-minute window, 2h remaining => 3h elapsed out of 5h
        // expected = 60%, actual = 80% => 20% ahead (in deficit)
        let window = RateWindow(
            usedPercent: 80,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(2 * 3600),
            resetDescription: nil)

        let detail = UsagePaceText.sessionDetail(provider: .claude, window: window, now: now)

        #expect(detail != nil)
        #expect(detail?.leftLabel == "20% in deficit")
        #expect(detail?.rightLabel == "Projected empty in 45m")
        #expect(detail?.stage == .farAhead)
    }

    @Test
    func Claude_session_pace_does_not_show_Codex_headroom() {
        let now = Date(timeIntervalSince1970: 0)
        // 300-minute window, 2h remaining => 3h elapsed
        // expected = 60%, actual = 10% => far behind (in reserve)
        let window = RateWindow(
            usedPercent: 10,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(2 * 3600),
            resetDescription: nil)

        let detail = UsagePaceText.sessionDetail(provider: .claude, window: window, now: now)

        #expect(detail != nil)
        #expect(detail?.leftLabel == "50% in reserve")
        #expect(detail?.rightLabel == "Lasts until reset")
    }

    @Test
    func Codex_session_pace_shows_conservative_headroom() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 10,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(2 * 3600),
            resetDescription: nil)

        let detail = UsagePaceText.sessionDetail(provider: .codex, window: window, now: now)

        #expect(detail?.rightLabel == "Lasts until reset · 1.5× headroom")
    }

    @Test
    func session_pace_summary_formats_single_line_text() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 80,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(2 * 3600),
            resetDescription: nil)

        let summary = UsagePaceText.sessionSummary(provider: .claude, window: window, now: now)

        #expect(summary == "Pace: 20% in deficit · Projected empty in 45m")
    }

    @Test
    func session_pace_detail_supports_Ollama_five_hour_window() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 80,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(2 * 3600),
            resetDescription: nil)

        let detail = UsagePaceText.sessionDetail(provider: .ollama, window: window, now: now)

        #expect(detail?.leftLabel == "20% in deficit")
        #expect(detail?.rightLabel == "Projected empty in 45m")
    }

    @Test
    func session_pace_detail_supports_Antigravity_five_hour_window() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 80,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(2 * 3600),
            resetDescription: nil)

        let detail = UsagePaceText.sessionDetail(provider: .antigravity, window: window, now: now)

        #expect(detail?.leftLabel == "20% in deficit")
        #expect(detail?.rightLabel == "Projected empty in 45m")
    }

    @Test
    func session_pace_detail_hides_Antigravity_weekly_window() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 80,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(2 * 24 * 3600),
            resetDescription: nil)

        let detail = UsagePaceText.sessionDetail(provider: .antigravity, window: window, now: now)

        #expect(detail == nil)
    }

    @Test
    func session_pace_detail_hides_Ollama_window_without_explicit_duration() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 80,
            windowMinutes: nil,
            resetsAt: now.addingTimeInterval(2 * 3600),
            resetDescription: nil)

        let detail = UsagePaceText.sessionDetail(provider: .ollama, window: window, now: now)

        #expect(detail == nil)
    }

    @Test
    func session_pace_detail_hides_for_unsupported_provider() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 50,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(2 * 3600),
            resetDescription: nil)

        let detail = UsagePaceText.sessionDetail(provider: .zai, window: window, now: now)

        #expect(detail == nil)
    }

    @Test
    func session_pace_detail_hides_when_reset_is_missing() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 50,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: nil)

        let detail = UsagePaceText.sessionDetail(provider: .claude, window: window, now: now)

        #expect(detail == nil)
    }

    @Test
    func usage_pace_text_localization_keys_exist_in_en_and_zh_Hans_with_matching_placeholders() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let enURL = root.appendingPathComponent("Sources/CodexBar/Resources/en.lproj/Localizable.strings")
        let zhURL = root.appendingPathComponent("Sources/CodexBar/Resources/zh-Hans.lproj/Localizable.strings")

        let en = try Self.readStringsTable(at: enURL)
        let zh = try Self.readStringsTable(at: zhURL)

        for key in Self.localizedKeys {
            let enValue = try #require(en[key], "Missing en key: \(key)")
            let zhValue = try #require(zh[key], "Missing zh-Hans key: \(key)")
            #expect(
                Self.placeholderTokens(in: enValue) == Self.placeholderTokens(in: zhValue),
                "Placeholder mismatch for key '\(key)': en='\(enValue)' zh='\(zhValue)'")
        }
    }

    private static func readStringsTable(at url: URL) throws -> [String: String] {
        guard let dict = NSDictionary(contentsOf: url) as? [String: String] else {
            throw NSError(
                domain: "UsagePaceTextTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse strings file at \(url.path)"])
        }
        return dict
    }

    private static func placeholderTokens(in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "%(?:\\d+\\$)?[@dDuUxXfFeEgGcCsSpaA]") else {
            return []
        }
        let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex
            .matches(in: value, options: [], range: nsRange)
            .compactMap { Range($0.range, in: value).map { String(value[$0]) } }
    }
}
