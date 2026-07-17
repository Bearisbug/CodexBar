import Foundation
import Testing
@testable import CodexBarCore

struct AntigravityCompactFallbackTests {
    @Test
    func model_quota_reset_proximity_does_not_imply_window_duration() throws {
        let resetTime = Date().addingTimeInterval(2 * 60 * 60)
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Gemini 3.1 Pro (Low)",
                    modelId: "MODEL_PLACEHOLDER_M36",
                    remainingFraction: 0.5,
                    resetTime: resetTime,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil)

        let usage = try snapshot.toUsageSnapshot()

        #expect(usage.primary?.windowMinutes == nil)
        #expect(usage.primary?.resetsAt == resetTime)
    }

    @Test
    func local_unclassified_model_remains_available_as_compact_fallback() throws {
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Experimental Model",
                    modelId: "MODEL_PLACEHOLDER_NEW",
                    remainingFraction: 0.36,
                    resetTime: nil,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil,
            source: .local)

        let usage = try snapshot.toUsageSnapshot()

        #expect(usage.primary == nil)
        #expect(usage.secondary == nil)
        #expect(usage.tertiary == nil)
        #expect(usage.extraRateWindows?.map(\.id) == ["antigravity-compact-fallback-MODEL_PLACEHOLDER_NEW"])
        #expect(usage.extraRateWindows?.map(\.title) == ["Experimental Model"])
        #expect(usage.extraRateWindows?.map(\.window.usedPercent) == [64])
    }

    @Test
    func remote_unclassified_model_remains_detail_only() throws {
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Experimental Model",
                    modelId: "MODEL_PLACEHOLDER_NEW",
                    remainingFraction: 0.36,
                    resetTime: nil,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil,
            source: .remote)

        let usage = try snapshot.toUsageSnapshot()

        #expect(usage.primary == nil)
        #expect(usage.secondary == nil)
        #expect(usage.extraRateWindows?.map(\.id) == ["MODEL_PLACEHOLDER_NEW"])
    }

    @Test
    func fully_unused_local_model_remains_available_as_compact_fallback() throws {
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Experimental Model",
                    modelId: "MODEL_PLACEHOLDER_NEW",
                    remainingFraction: 1,
                    resetTime: nil,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil,
            source: .local)

        let usage = try snapshot.toUsageSnapshot()

        #expect(usage.extraRateWindows?.map(\.id) == ["antigravity-compact-fallback-MODEL_PLACEHOLDER_NEW"])
        #expect(usage.extraRateWindows?.map(\.window.usedPercent) == [0])
    }
}
