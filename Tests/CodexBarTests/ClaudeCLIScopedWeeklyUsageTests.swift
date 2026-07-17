import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct ClaudeCLIScopedWeeklyUsageTests {
    @Test
    func CLI_usage_surfaces_Fable_scoped_weekly_limit() async throws {
        let cliUsage = """
        Settings  Status  Config  Usage  Stats

        Current session
        9% used
        Resets 2:09pm (Europe/Prague)

        Current week (all models)
        67% used
        Resets Jul 10 t 2:59am (Europe/Prague)

        Current week (Fable)
        68% used
        Reset Jul 10 at 2:59am (Europe/Prague)

        Current week (Example Model)
        12% used
        """
        let status = try ClaudeStatusProbe.parse(text: cliUsage)
        let fetcher = ClaudeUsageFetcher(
            browserDetection: BrowserDetection(cacheTTL: 0),
            environment: [:],
            dataSource: .cli)
        let fetchOverride: ClaudeStatusProbe.FetchOverride = { _, _, _ in status }

        let snapshot = try await ClaudeCLIResolver.withResolvedBinaryPathOverrideForTesting("/usr/bin/true") {
            try await ClaudeStatusProbe.withFetchOverrideForTesting(fetchOverride) {
                try await fetcher.loadLatestUsage(model: "sonnet")
            }
        }

        let fable = try #require(snapshot.extraRateWindows.first { $0.id == "claude-weekly-scoped-fable" })
        #expect(fable.title == "Fable only")
        #expect(fable.window.usedPercent == 68)
        #expect(fable.window.resetDescription == "Reset Jul 10 at 2:59am (Europe/Prague)")
        let example = try #require(
            snapshot.extraRateWindows.first { $0.id == "claude-weekly-scoped-example-model" })
        #expect(example.title == "Example Model only")
        #expect(example.window.usedPercent == 12)
        #expect(example.window.resetDescription == "Resets Jul 10 at 2:59am (Europe/Prague)")
        #expect(snapshot.opus == nil)
    }

    @Test
    func scoped_weekly_panel_does_not_become_all_models_weekly_usage() throws {
        let cliUsage = """
        Current session
        9% used

        Current week (Fable)
        68% used
        """

        let snapshot = try ClaudeStatusProbe.parse(text: cliUsage)

        #expect(snapshot.weeklyPercentLeft == nil)
        #expect(snapshot.secondaryResetDescription == nil)
        #expect(snapshot.extraRateWindows.map(\.title) == ["Fable only"])
    }

    @Test
    func compact_scoped_weekly_label_is_parsed() throws {
        let snapshot = try ClaudeStatusProbe.parse(text: """
        Current session
        9% used

        Currentweek(Fable)
        68% used
        """)

        #expect(snapshot.extraRateWindows.map(\.title) == ["Fable only"])
        #expect(snapshot.extraRateWindows.first?.window.usedPercent == 68)
    }

    @Test
    func overlapping_scoped_model_names_do_not_cross_panel_boundaries() throws {
        let snapshot = try ClaudeStatusProbe.parse(text: """
        Current session
        9% used

        Current week (Example Model)
        rendering

        Current week (Example Model Plus)
        42% used
        """)

        #expect(snapshot.extraRateWindows.map(\.title) == ["Example Model Plus only"])
        #expect(snapshot.extraRateWindows.first?.window.usedPercent == 42)
    }

    @Test
    func informational_Sonnet_prose_does_not_duplicate_a_scoped_limit() throws {
        let snapshot = try ClaudeStatusProbe.parse(text: """
        Current session
        9% used

        Current week (all models)
        20% used

        Current week (Fable)
        42% used

        Sonnet now has its own limit.
        """)

        #expect(snapshot.opusPercentLeft == nil)
        #expect(snapshot.extraRateWindows.map(\.title) == ["Fable only"])
        #expect(snapshot.extraRateWindows.first?.window.usedPercent == 42)
    }

    @Test
    func Sonnet_prefixed_scoped_model_does_not_become_legacy_quota() throws {
        let snapshot = try ClaudeStatusProbe.parse(text: """
        Current session
        9% used

        Current week (all models)
        20% used

        Current week (Sonnet Test Variant)
        42% used
        """)

        #expect(snapshot.opusPercentLeft == nil)
        #expect(snapshot.extraRateWindows.map(\.title) == ["Sonnet Test Variant only"])
        #expect(snapshot.extraRateWindows.first?.window.usedPercent == 42)
    }

    @Test
    func later_complete_scoped_panel_replaces_partial_redraw() throws {
        let spacer = Array(repeating: "rendering", count: 14).joined(separator: "\n")
        let cliUsage = """
        Current session
        9% used

        Current week (all models)
        67% used

        Current week (Fable)
        \(spacer)

        Current week (Fable)
        70% used
        Reset Jul 10 at 2:59am (Europe/Prague)
        """

        let snapshot = try ClaudeStatusProbe.parse(text: cliUsage)
        let fable = try #require(snapshot.extraRateWindows.first)

        #expect(snapshot.extraRateWindows.count == 1)
        #expect(fable.window.usedPercent == 70)
        #expect(fable.window.resetDescription == "Reset Jul 10 at 2:59am (Europe/Prague)")
    }

    @Test
    func incomplete_scoped_panel_stops_at_session_redraw() throws {
        let cliUsage = """
        Current week (Fable)
        rendering

        Current session
        9% used

        Current week (all models)
        20% used
        """

        let snapshot = try ClaudeStatusProbe.parse(text: cliUsage)

        #expect(snapshot.sessionPercentLeft == 91)
        #expect(snapshot.weeklyPercentLeft == 80)
        #expect(snapshot.extraRateWindows.isEmpty)
    }

    @Test
    func incomplete_all_models_panel_does_not_consume_scoped_percentage() throws {
        let cliUsage = """
        Current session
        9% used

        Current week (all models)
        rendering

        Current week (Fable)
        42% used
        """

        let snapshot = try ClaudeStatusProbe.parse(text: cliUsage)

        #expect(snapshot.weeklyPercentLeft == nil)
        #expect(snapshot.extraRateWindows.map(\.title) == ["Fable only"])
        #expect(snapshot.extraRateWindows.first?.window.usedPercent == 42)
    }

    @Test
    func incomplete_Opus_panel_does_not_consume_prefixed_scoped_percentage() throws {
        let cliUsage = """
        Current session
        9% used

        Current week (all models)
        20% used

        Current week (Opus)
        rendering

        Current week (Opus Test Variant)
        42% used
        """

        let snapshot = try ClaudeStatusProbe.parse(text: cliUsage)

        #expect(snapshot.opusPercentLeft == nil)
        #expect(snapshot.extraRateWindows.map(\.title) == ["Opus Test Variant only"])
        #expect(snapshot.extraRateWindows.first?.window.usedPercent == 42)
    }

    @Test
    func later_complete_scoped_panel_replaces_earlier_complete_value() throws {
        let cliUsage = """
        Current session
        9% used

        Current week (all models)
        67% used

        Current week (Fable)
        20% used

        Current week (Fable)
        70% used
        """

        let snapshot = try ClaudeStatusProbe.parse(text: cliUsage)
        let fable = try #require(snapshot.extraRateWindows.first)

        #expect(snapshot.extraRateWindows.count == 1)
        #expect(fable.window.usedPercent == 70)
    }

    @Test
    func web_extra_windows_merge_with_CLI_scoped_weekly_limits() throws {
        let fable = NamedRateWindow(
            id: "claude-weekly-scoped-fable",
            title: "Fable only",
            window: RateWindow(
                usedPercent: 68,
                windowMinutes: 7 * 24 * 60,
                resetsAt: nil,
                resetDescription: "Resets Jul 10 at 2:59am (Europe/Prague)"))
        let webFable = try #require(ClaudeScopedWeeklyLimitMapper.extraRateWindows(from: [
            ClaudeScopedWeeklyLimitMapper.Limit(
                kind: "weekly_scoped",
                group: "weekly",
                percent: 70,
                resetsAt: nil,
                modelID: "test-only-fable-id",
                modelName: "Fable"),
        ]).first)
        let routines = NamedRateWindow(
            id: "claude-routines",
            title: "Daily Routines",
            window: RateWindow(
                usedPercent: 11,
                windowMinutes: 7 * 24 * 60,
                resetsAt: nil,
                resetDescription: nil))

        let merged = ClaudeUsageFetcher._mergeExtraRateWindowsForTesting(
            primary: [fable],
            web: [webFable, routines])

        #expect(merged.map(\.id) == ["claude-weekly-scoped-fable", "claude-routines"])
        #expect(webFable.id == "claude-weekly-scoped-test-only-fable-id")
        #expect(merged.first?.window.usedPercent == 68)
        #expect(merged.last?.title == "Daily Routines")
    }

    @Test
    func same_title_web_limits_keep_distinct_stable_IDs() {
        let webLimits = ["first-id", "second-id"].map { id in
            NamedRateWindow(
                id: "claude-weekly-scoped-\(id)",
                title: "Example Model only",
                window: RateWindow(
                    usedPercent: 25,
                    windowMinutes: 7 * 24 * 60,
                    resetsAt: nil,
                    resetDescription: nil))
        }

        let merged = ClaudeUsageFetcher._mergeExtraRateWindowsForTesting(
            primary: [],
            web: webLimits)

        #expect(merged.map(\.id) == [
            "claude-weekly-scoped-first-id",
            "claude-weekly-scoped-second-id",
        ])
    }

    @Test
    func ambiguous_same_title_web_limits_survive_CLI_merge() {
        let cli = NamedRateWindow(
            id: "claude-weekly-scoped-example-model",
            title: "Example Model only",
            window: RateWindow(
                usedPercent: 20,
                windowMinutes: 7 * 24 * 60,
                resetsAt: nil,
                resetDescription: nil))
        let webLimits = ["first-id", "second-id"].map { id in
            NamedRateWindow(
                id: "claude-weekly-scoped-\(id)",
                title: "Example Model only",
                window: RateWindow(
                    usedPercent: 25,
                    windowMinutes: 7 * 24 * 60,
                    resetsAt: nil,
                    resetDescription: nil))
        }

        let merged = ClaudeUsageFetcher._mergeExtraRateWindowsForTesting(
            primary: [cli],
            web: webLimits)

        #expect(merged.map(\.id) == [
            "claude-weekly-scoped-example-model",
            "claude-weekly-scoped-first-id",
            "claude-weekly-scoped-second-id",
        ])
    }
}
