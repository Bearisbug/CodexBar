import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct GeminiPrimaryWindowTests {
    @Test
    func flash_only_account_does_not_fabricate_a_phantom_0_primary_window() {
        let snapshot = GeminiStatusSnapshot(
            modelQuotas: [
                GeminiModelQuota(modelId: "gemini-2.5-flash", percentLeft: 5, resetTime: nil, resetDescription: nil),
                GeminiModelQuota(
                    modelId: "gemini-2.5-flash-lite", percentLeft: 60, resetTime: nil, resetDescription: nil),
            ],
            rawText: "",
            accountEmail: nil,
            accountPlan: nil)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary == nil)
        #expect(usage.secondary?.usedPercent == 95)
        #expect(usage.tertiary?.usedPercent == 40)
    }

    @Test
    func pro_quota_still_populates_the_primary_window() {
        let snapshot = GeminiStatusSnapshot(
            modelQuotas: [
                GeminiModelQuota(modelId: "gemini-2.5-pro", percentLeft: 30, resetTime: nil, resetDescription: nil),
                GeminiModelQuota(modelId: "gemini-2.5-flash", percentLeft: 70, resetTime: nil, resetDescription: nil),
            ],
            rawText: "",
            accountEmail: nil,
            accountPlan: nil)

        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.usedPercent == 70)
        #expect(usage.secondary?.usedPercent == 30)
    }
}
