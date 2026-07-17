import Foundation
import Testing
@testable import CodexBarCore

struct ClaudeScopedWeeklyLimitMapperTests {
    @Test
    func model_id_provides_a_stable_safe_identifier_and_duplicate_limits_collapse() throws {
        let reset = Date(timeIntervalSince1970: 1_783_507_200)
        let limits = [
            Self.limit(modelID: "claude/fable.5:promo", modelName: "Fable", resetsAt: reset),
            Self.limit(modelID: "claude/fable.5:promo", modelName: "Fable renamed", resetsAt: reset),
        ]

        let windows = ClaudeScopedWeeklyLimitMapper.extraRateWindows(
            from: limits,
            resetDescription: { _ in "Jul 8" })
        let window = try #require(windows.first)

        #expect(windows.count == 1)
        #expect(window.id == "claude-weekly-scoped-claude-fable-5-promo")
        #expect(window.title == "Fable only")
        #expect(window.window.resetsAt == reset)
        #expect(window.window.resetDescription == "Jul 8")
    }

    @Test
    func display_name_supplies_the_identifier_when_the_API_omits_a_model_id() throws {
        let windows = ClaudeScopedWeeklyLimitMapper.extraRateWindows(from: [
            Self.limit(modelID: "  ", modelName: " Team / Research "),
        ])

        let window = try #require(windows.first)
        #expect(window.id == "claude-weekly-scoped-team-research")
        #expect(window.title == "Team / Research only")
    }

    @Test
    func unrelated_malformed_and_unnamed_limits_are_ignored() {
        let limits = [
            Self.limit(kind: "session", modelName: "Fable"),
            Self.limit(group: "monthly", modelName: "Fable"),
            Self.limit(percent: .nan, modelName: "Fable"),
            Self.limit(modelName: "  "),
        ]

        #expect(ClaudeScopedWeeklyLimitMapper.extraRateWindows(from: limits).isEmpty)
    }

    @Test
    func all_models_scope_stays_in_the_primary_weekly_lane() {
        let limits = [
            Self.limit(modelID: nil, modelName: "All models"),
            Self.limit(modelID: "claude/all_models", modelName: "Weekly"),
            Self.limit(modelID: nil, modelName: "Fable"),
        ]

        let windows = ClaudeScopedWeeklyLimitMapper.extraRateWindows(from: limits)

        #expect(windows.map(\.title) == ["Fable only"])
    }

    private static func limit(
        kind: String = "weekly_scoped",
        group: String = "weekly",
        percent: Double = 5,
        modelID: String? = nil,
        modelName: String?,
        resetsAt: Date? = nil) -> ClaudeScopedWeeklyLimitMapper.Limit
    {
        ClaudeScopedWeeklyLimitMapper.Limit(
            kind: kind,
            group: group,
            percent: percent,
            resetsAt: resetsAt,
            modelID: modelID,
            modelName: modelName)
    }
}
