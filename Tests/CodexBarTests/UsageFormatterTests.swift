import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
struct UsageFormatterTests {
    private static let usageFormatterLocalizationKeys: [String] = [
        "%@ left",
        "Resets %@",
        "Resets in %@",
        "Resets now",
        "reset_tomorrow_format",
        "Updated %@",
        "Updated relative %@",
        "Updated absolute %@",
        "Updated %@h ago",
        "Updated %@m ago",
        "Updated just now",
        "usage_percent_suffix_left",
        "usage_percent_suffix_used",
        "byte_unit_byte",
        "byte_unit_bytes",
        "byte_unit_kilobyte",
        "byte_unit_kilobytes",
        "byte_unit_megabyte",
        "byte_unit_megabytes",
        "byte_unit_gigabyte",
        "byte_unit_gigabytes",
    ]

    @Test
    func formats_usage_line() {
        UsageFormatter.clearLocalizationProvider()
        UsageFormatter.clearLocaleProvider()
        let line = UsageFormatter.usageLine(remaining: 25, used: 75, showUsed: false)
        #expect(line == "25% left")
    }

    @Test
    func formats_usage_line_show_used() {
        UsageFormatter.clearLocalizationProvider()
        UsageFormatter.clearLocaleProvider()
        let line = UsageFormatter.usageLine(remaining: 25, used: 75, showUsed: true)
        #expect(line == "75% used")
    }

    @Test
    func positive_sub_percent_usage_stays_visible() {
        #expect(UsageFormatter.percentString(-1) == "0%")
        #expect(UsageFormatter.percentString(0) == "0%")
        #expect(UsageFormatter.percentString(0.1) == "<1%")
        #expect(UsageFormatter.percentString(0.96) == "<1%")
        #expect(UsageFormatter.percentString(1) == "1%")
        #expect(UsageFormatter.percentString(101) == "100%")
        #expect(UsageFormatter.usageLine(remaining: 99.9, used: 0.1, showUsed: true) == "<1% used")
        // Values in (0.5, 1) round up to "1%" under %.0f, so the old post-format
        // "0%" -> "<1%" replacement missed them. percentText must show "<1%"
        // across the whole sub-1% range, matching percentString above.
        #expect(UsageFormatter.usageLine(remaining: 99.4, used: 0.6, showUsed: true) == "<1% used")
        #expect(UsageFormatter.usageLine(remaining: 99.25, used: 0.75, showUsed: true) == "<1% used")
        #expect(UsageFormatter.usageLine(remaining: 0.75, used: 99.25, showUsed: false) == "<1% left")

        let usedWindow = RateWindow(usedPercent: 0.1, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let leftWindow = RateWindow(usedPercent: 99.9, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        #expect(MenuBarDisplayText.percentText(window: usedWindow, showUsed: true) == "<1%")
        #expect(MenuBarDisplayText.percentText(window: leftWindow, showUsed: false) == "<1%")
    }

    @Test
    func usage_line_respects_injected_localization_provider() {
        UsageFormatter.setLocalizationProvider { key in
            switch key {
            case "%.0f%% %@": "%2$@ %1$.0f%%"
            case "<1%% %@": "%1$@ <1%%"
            case "usage_percent_suffix_left": "剩余"
            case "usage_percent_suffix_used": "已使用"
            default: key
            }
        }
        defer { UsageFormatter.clearLocalizationProvider() }

        #expect(UsageFormatter.usageLine(remaining: 22, used: 78, showUsed: false) == "剩余 22%")
        #expect(UsageFormatter.usageLine(remaining: 22, used: 78, showUsed: true) == "已使用 78%")
        #expect(UsageFormatter.usageLine(remaining: 0.75, used: 99.25, showUsed: false) == "剩余 <1%")
        #expect(UsageFormatter.usageLine(remaining: 99.4, used: 0.6, showUsed: true) == "已使用 <1%")
    }

    @Test
    func default_locale_fallback_matches_stable_en_US_POSIX_behavior() {
        UsageFormatter.clearLocalizationProvider()
        UsageFormatter.clearLocaleProvider()

        let now = Date(timeIntervalSince1970: 1_710_048_000)
        let old = now.addingTimeInterval(-(26 * 3600))

        let defaultOutput = UsageFormatter.updatedString(from: old, now: now)
        UsageFormatter.setLocaleProvider { Locale(identifier: "en_US_POSIX") }
        let injectedStableOutput = UsageFormatter.updatedString(from: old, now: now)
        UsageFormatter.clearLocaleProvider()

        #expect(defaultOutput == injectedStableOutput)
    }

    @Test
    func injected_zh_Hans_locale_applies_app_language_formatting() {
        UsageFormatter.setLocalizationProvider { key in
            switch key {
            case "Updated absolute %@":
                "更新于 %@"
            default:
                key
            }
        }
        UsageFormatter.setLocaleProvider { Locale(identifier: "zh-Hans") }
        defer {
            UsageFormatter.clearLocalizationProvider()
            UsageFormatter.clearLocaleProvider()
        }

        let now = Date(timeIntervalSince1970: 1_710_048_000)
        let old = now.addingTimeInterval(-(26 * 3600))
        let output = UsageFormatter.updatedString(from: old, now: now)

        #expect(output.hasPrefix("更新于 "))
    }

    @Test
    func injected_zh_Hant_relative_updated_string_can_place_updated_after_relative_time() {
        UsageFormatter.setLocalizationProvider { key in
            switch key {
            case "Updated relative %@":
                "%@已更新"
            default:
                key
            }
        }
        UsageFormatter.setLocaleProvider { Locale(identifier: "zh-Hant") }
        defer {
            UsageFormatter.clearLocalizationProvider()
            UsageFormatter.clearLocaleProvider()
        }

        let now = Date(timeIntervalSince1970: 1_710_048_000)
        let old = now.addingTimeInterval(-(5 * 3600))
        let output = UsageFormatter.updatedString(from: old, now: now)

        #expect(output.hasSuffix("已更新"))
        #expect(!output.hasPrefix("已更新"))
    }

    @Test
    func clearing_locale_provider_returns_to_stable_default_behavior() {
        UsageFormatter.clearLocalizationProvider()
        UsageFormatter.clearLocaleProvider()

        let now = Date(timeIntervalSince1970: 1_710_048_000)
        let old = now.addingTimeInterval(-(26 * 3600))
        let baseline = UsageFormatter.updatedString(from: old, now: now)

        UsageFormatter.setLocaleProvider { Locale(identifier: "fr_FR") }
        _ = UsageFormatter.updatedString(from: old, now: now)
        UsageFormatter.clearLocaleProvider()

        let restored = UsageFormatter.updatedString(from: old, now: now)
        #expect(restored == baseline)
    }

    @Test
    func tomorrow_reset_description_uses_localized_format() throws {
        UsageFormatter.setLocalizationProvider { key in
            key == "reset_tomorrow_format" ? "明日 %@" : key
        }
        UsageFormatter.setLocaleProvider { Locale(identifier: "ja_JP") }
        defer {
            UsageFormatter.clearLocalizationProvider()
            UsageFormatter.clearLocaleProvider()
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
        let now = try #require(calendar.date(byAdding: .hour, value: 12, to: today))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: today))
        let reset = try #require(calendar.date(byAdding: .minute, value: 10 * 60 + 50, to: tomorrow))

        let output = UsageFormatter.resetDescription(from: reset, now: now)
        #expect(output.hasPrefix("明日 "))
        #expect(!output.contains("tomorrow"))
        #expect(!output.contains("%@"))
    }

    @Test
    func relative_updated_recent() {
        let now = Date()
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)
        let text = UsageFormatter.updatedString(from: fiveHoursAgo, now: now)
        #expect(text.hasPrefix("Updated ") || text.hasPrefix("更新"))
        #expect(text.contains("5"))
        #expect(text.lowercased().contains("ago") || text.contains("前"))
    }

    @Test
    func absolute_updated_old() {
        let now = Date()
        let dayAgo = now.addingTimeInterval(-26 * 3600)
        let text = UsageFormatter.updatedString(from: dayAgo, now: now)
        #expect(text.contains("Updated"))
        #expect(!text.contains("ago"))
    }

    @Test
    func reset_countdown_minutes() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(10 * 60 + 1)
        #expect(UsageFormatter.resetCountdownDescription(from: reset, now: now) == "in 11m")
    }

    @Test
    func reset_countdown_hours_and_minutes() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(3 * 3600 + 31 * 60)
        #expect(UsageFormatter.resetCountdownDescription(from: reset, now: now) == "in 3h 31m")
    }

    @Test
    func reset_countdown_caps_days_with_hours_at_two_units() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval((26 * 3600) + (1 * 60))
        #expect(UsageFormatter.resetCountdownDescription(from: reset, now: now) == "in 1d 2h")
    }

    @Test
    func reset_countdown_days_and_exact_hours() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(26 * 3600)
        #expect(UsageFormatter.resetCountdownDescription(from: reset, now: now) == "in 1d 2h")
    }

    @Test
    func reset_countdown_days_and_minutes_without_whole_hours() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval((24 * 3600) + (5 * 60))
        #expect(UsageFormatter.resetCountdownDescription(from: reset, now: now) == "in 1d 5m")
    }

    @Test
    func reset_countdown_exact_days() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(2 * 24 * 3600)
        #expect(UsageFormatter.resetCountdownDescription(from: reset, now: now) == "in 2d")
    }

    @Test
    func reset_countdown_rounds_the_last_minute_into_a_day() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval((24 * 3600) - 59)
        #expect(UsageFormatter.resetCountdownDescription(from: reset, now: now) == "in 1d")
    }

    @Test
    func reset_countdown_exact_hour() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(60 * 60)
        #expect(UsageFormatter.resetCountdownDescription(from: reset, now: now) == "in 1h")
    }

    @Test
    func reset_countdown_past_date() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(-10)
        #expect(UsageFormatter.resetCountdownDescription(from: reset, now: now) == "now")
    }

    @Test
    func reset_line_uses_countdown_when_resets_at_is_available() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(10 * 60 + 1)
        let window = RateWindow(usedPercent: 0, windowMinutes: nil, resetsAt: reset, resetDescription: "Resets soon")
        let text = UsageFormatter.resetLine(for: window, style: .countdown, now: now)
        #expect(text == "Resets in 11m")
    }

    @Test
    func reset_line_falls_back_to_provided_description() {
        let window = RateWindow(
            usedPercent: 0,
            windowMinutes: nil,
            resetsAt: nil,
            resetDescription: "Resets at 23:30 (UTC)")
        let countdown = UsageFormatter.resetLine(for: window, style: .countdown)
        let absolute = UsageFormatter.resetLine(for: window, style: .absolute)
        #expect(countdown == "Resets at 23:30 (UTC)")
        #expect(absolute == "Resets at 23:30 (UTC)")
    }

    @Test
    func model_display_name_strips_trailing_dates() {
        #expect(UsageFormatter.modelDisplayName("claude-opus-4-5-20251101") == "claude-opus-4-5")
        #expect(UsageFormatter.modelDisplayName("gpt-4o-2024-08-06") == "gpt-4o")
        #expect(UsageFormatter.modelDisplayName("Claude Opus 4.5 2025 1101") == "Claude Opus 4.5")
        #expect(UsageFormatter.modelDisplayName("claude-sonnet-4-5") == "claude-sonnet-4-5")
        #expect(UsageFormatter.modelDisplayName("gpt-5.3-codex-spark") == "gpt-5.3-codex-spark")
        #expect(UsageFormatter.modelDisplayName("unknown") == "Unknown model")
    }

    @Test
    func model_cost_detail_uses_research_preview_label() {
        #expect(
            UsageFormatter.modelCostDetail("gpt-5.3-codex-spark", costUSD: 0, totalTokens: nil) == "Research Preview")
        #expect(UsageFormatter.modelCostDetail("gpt-5.2-codex", costUSD: 0.42, totalTokens: nil) == "$0.42")
    }

    @Test
    func model_cost_detail_includes_token_counts_when_present() {
        #expect(UsageFormatter.modelCostDetail("gpt-5.2-codex", costUSD: 0.42, totalTokens: 1200) == "$0.42 · 1.2K")
        #expect(
            UsageFormatter.modelCostDetail("gpt-5.3-codex-spark", costUSD: 0, totalTokens: 1500)
                == "Research Preview · 1.5K")
        #expect(UsageFormatter.modelCostDetail("custom-model", costUSD: nil, totalTokens: 987) == "987")
    }

    @Test
    func token_count_string_formats_small_values_without_grouping() {
        #expect(UsageFormatter.tokenCountString(0) == "0")
        #expect(UsageFormatter.tokenCountString(987) == "987")
        #expect(UsageFormatter.tokenCountString(-42) == "-42")
    }

    @Test
    func clean_plan_maps_O_auth_to_ollama() {
        #expect(UsageFormatter.cleanPlanName("oauth") == "Ollama")
    }

    // MARK: - Currency Formatting

    @Test
    func currency_string_formats_USD_correctly() {
        // Should produce "$54.72" without space after symbol
        let result = UsageFormatter.currencyString(54.72, currencyCode: "USD")
        #expect(result == "$54.72")
        #expect(!result.contains("$ ")) // No space after symbol
    }

    @Test
    func currency_string_handles_large_values() {
        let result = UsageFormatter.currencyString(1234.56, currencyCode: "USD")
        // For USD, we use direct string formatting with thousand separators
        #expect(result == "$1,234.56")
        #expect(!result.contains("$ ")) // No space after symbol
    }

    @Test
    func currency_string_handles_very_large_values() {
        let result = UsageFormatter.currencyString(1_234_567.89, currencyCode: "USD")
        #expect(result == "$1,234,567.89")
    }

    @Test
    func currency_string_handles_negative_values() {
        // Negative sign should come before the dollar sign: -$54.72 (not $-54.72)
        let result = UsageFormatter.currencyString(-54.72, currencyCode: "USD")
        #expect(result == "-$54.72")
    }

    @Test
    func currency_string_handles_negative_large_values() {
        let result = UsageFormatter.currencyString(-1234.56, currencyCode: "USD")
        #expect(result == "-$1,234.56")
    }

    @Test
    func usd_string_matches_currency_string() {
        // usdString should produce identical output to currencyString for USD
        #expect(UsageFormatter.usdString(54.72) == UsageFormatter.currencyString(54.72, currencyCode: "USD"))
        #expect(UsageFormatter.usdString(-1234.56) == UsageFormatter.currencyString(-1234.56, currencyCode: "USD"))
        #expect(UsageFormatter.usdString(0) == UsageFormatter.currencyString(0, currencyCode: "USD"))
    }

    @Test
    func currency_string_handles_zero() {
        let result = UsageFormatter.currencyString(0, currencyCode: "USD")
        #expect(result == "$0.00")
    }

    @Test(arguments: [
        (0.0, "$0"),
        (0.50, "$0.50"),
        (12.56, "$13"),
        (1515.0, "$1,515"),
    ])
    func compact_currency_keeps_cents_only_below_one_unit(value: Double, expected: String) {
        #expect(UsageFormatter.compactCurrencyString(value, currencyCode: "USD") == expected)
    }

    @Test
    func currency_string_handles_non_USD_currencies() {
        // FormatStyle handles all currencies with proper symbols
        let eur = UsageFormatter.currencyString(54.72, currencyCode: "EUR")
        #expect(eur == "€54.72")

        let gbp = UsageFormatter.currencyString(54.72, currencyCode: "GBP")
        #expect(gbp == "£54.72")

        // Negative non-USD
        let negEur = UsageFormatter.currencyString(-1234.56, currencyCode: "EUR")
        #expect(negEur == "-€1,234.56")
    }

    @Test
    func currency_string_handles_small_values() {
        // Values smaller than 0.01 should round to $0.00
        let tiny = UsageFormatter.currencyString(0.001, currencyCode: "USD")
        #expect(tiny == "$0.00")

        // Values at 0.005 should round to $0.01 (banker's rounding)
        let halfCent = UsageFormatter.currencyString(0.005, currencyCode: "USD")
        #expect(halfCent == "$0.00" || halfCent == "$0.01") // Rounding behavior may vary

        // One cent
        let oneCent = UsageFormatter.currencyString(0.01, currencyCode: "USD")
        #expect(oneCent == "$0.01")
    }

    @Test
    func currency_string_handles_boundary_values() {
        // Just under 1000 (no comma)
        let under1k = UsageFormatter.currencyString(999.99, currencyCode: "USD")
        #expect(under1k == "$999.99")

        // Exactly 1000 (first comma)
        let exact1k = UsageFormatter.currencyString(1000.00, currencyCode: "USD")
        #expect(exact1k == "$1,000.00")

        // Just over 1000
        let over1k = UsageFormatter.currencyString(1000.01, currencyCode: "USD")
        #expect(over1k == "$1,000.01")
    }

    @Test
    func credits_string_formats_correctly() {
        let result = UsageFormatter.creditsString(from: 42.5)
        #expect(result == "42.5 left")
    }

    @Test
    func byte_count_string_formats_binary_units() {
        #expect(UsageFormatter.byteCountString(0) == "0 B")
        #expect(UsageFormatter.byteCountString(512) == "512 B")
        #expect(UsageFormatter.byteCountString(1536) == "1.5 KB")
        #expect(UsageFormatter.byteCountString(10 * 1024) == "10 KB")
        #expect(UsageFormatter.byteCountString(5 * 1024 * 1024) == "5 MB")
        #expect(UsageFormatter.byteCountString(Int64(1536 * 1024 * 1024)) == "1.5 GB")
        #expect(UsageFormatter.byteCountString(.min) == "-8589934592 GB")
    }

    @Test
    func long_byte_count_string_localizes_units_and_handles_boundaries() {
        UsageFormatter.clearLocalizationProvider()
        #expect(UsageFormatter.byteCountStringLong(1024 * 1024) == "1 megabyte")

        UsageFormatter.setLocalizationProvider { "[\($0)]" }
        defer { UsageFormatter.clearLocalizationProvider() }

        #expect(UsageFormatter.byteCountStringLong(1) == "1 [byte_unit_byte]")
        #expect(UsageFormatter.byteCountStringLong(2) == "2 [byte_unit_bytes]")
        #expect(UsageFormatter.byteCountStringLong(1536) == "1.5 [byte_unit_kilobytes]")
        #expect(UsageFormatter.byteCountStringLong(1024 * 1024) == "1 [byte_unit_megabyte]")
        #expect(UsageFormatter.byteCountStringLong(1024 * 1024 + 1) == "1.0 [byte_unit_megabyte]")
        #expect(UsageFormatter.byteCountStringLong(.min) == "-8589934592 [byte_unit_gigabytes]")
    }

    @Test
    func usage_formatter_localization_keys_exist_in_en_and_zh_Hans_with_matching_placeholders() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let enURL = root.appendingPathComponent("Sources/CodexBar/Resources/en.lproj/Localizable.strings")
        let zhURL = root.appendingPathComponent("Sources/CodexBar/Resources/zh-Hans.lproj/Localizable.strings")

        let en = try Self.readStringsTable(at: enURL)
        let zh = try Self.readStringsTable(at: zhURL)

        for key in Self.usageFormatterLocalizationKeys {
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
                domain: "UsageFormatterTests",
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
