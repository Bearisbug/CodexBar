import SwiftUI
import Testing
@testable import CodexBar

struct MenuCardHeightFingerprintTests {
    @Test
    func height_fingerprint_does_not_retain_raw_text_fields() {
        let model = Self.model()

        let fingerprint = model.heightFingerprint(section: "card")

        #expect(!fingerprint.contains("very-secret@example.com"))
        #expect(!fingerprint.contains("Secret Provider Name"))
        #expect(!fingerprint.contains("Secret Metric"))
        #expect(!fingerprint.contains("Secret note"))
    }

    @Test
    func height_fingerprint_field_distinguishes_nil_from_empty_string() {
        let nilField = UsageMenuCardView.Model.heightFingerprintField("storage", nil)
        let emptyField = UsageMenuCardView.Model.heightFingerprintField("storage", "")

        #expect(nilField != emptyField)
    }

    @Test
    func height_fingerprint_keeps_cheap_metric_percent_identity() {
        let left = Self.model(percent: 42, percentStyle: .left).heightFingerprint(section: "card")
        let used = Self.model(percent: 42, percentStyle: .used).heightFingerprint(section: "card")
        let changedPercent = Self.model(percent: 43, percentStyle: .left).heightFingerprint(section: "card")

        #expect(left != used)
        #expect(left != changedPercent)
    }

    @Test
    func height_fingerprint_tracks_reset_credit_inventory_shape() {
        let one = Self.model(resetCredits: CodexResetCreditsPresentation(
            text: "1 available",
            items: [.init(expiryText: "Expires in 1d", compactExpiryText: "1d")]))
        let two = Self.model(resetCredits: CodexResetCreditsPresentation(
            text: "2 available",
            items: [
                .init(expiryText: "Expires in 1d", compactExpiryText: "1d"),
                .init(expiryText: "No expiry", compactExpiryText: "No expiry"),
            ]))

        #expect(one.heightFingerprint(section: "card") != two.heightFingerprint(section: "card"))
    }

    private static func model(
        percent: Double = 42,
        percentStyle: UsageMenuCardView.Model.PercentStyle = .left,
        resetCredits: CodexResetCreditsPresentation? = nil) -> UsageMenuCardView.Model
    {
        UsageMenuCardView.Model(
            provider: .codex,
            providerName: "Secret Provider Name",
            email: "very-secret@example.com",
            subtitleText: "Signed in as very-secret@example.com",
            subtitleStyle: .info,
            planText: "Secret Plan",
            metrics: [
                .init(
                    id: "primary",
                    title: "Secret Metric",
                    percent: percent,
                    percentStyle: percentStyle,
                    statusText: "Secret status",
                    resetText: nil,
                    detailText: nil,
                    detailLeftText: nil,
                    detailRightText: nil,
                    pacePercent: nil,
                    paceOnTop: true),
            ],
            usageNotes: ["Secret note"],
            openAIAPIUsage: nil,
            inlineUsageDashboard: nil,
            creditsText: nil,
            creditsRemaining: nil,
            creditsProgressPercent: nil,
            creditsScaleText: nil,
            creditsHintText: nil,
            creditsHintCopyText: nil,
            codexResetCredits: resetCredits,
            providerCost: nil,
            tokenUsage: nil,
            placeholder: nil,
            progressColor: .blue)
    }
}
