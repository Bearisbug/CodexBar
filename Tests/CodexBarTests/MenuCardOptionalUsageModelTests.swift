import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct MenuCardOptionalUsageModelTests {
    @Test
    func hides_codex_credits_when_disabled() throws {
        let now = Date()
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: "codex@example.com",
            accountOrganization: nil,
            loginMethod: nil)
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 0, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: now,
            identity: identity)
        let metadata = try #require(ProviderDefaults.metadata[.codex])
        let credits = CreditsSnapshot(remaining: 12, events: [], updatedAt: now)
        let codexProjection = CodexConsumerProjection.make(
            surface: .liveCard,
            context: CodexConsumerProjection.Context(
                snapshot: snapshot,
                rawUsageError: nil,
                liveCredits: credits,
                rawCreditsError: nil,
                liveDashboard: nil,
                rawDashboardError: nil,
                dashboardAttachmentAuthorized: true,
                dashboardRequiresLogin: false,
                now: now))

        let model = UsageMenuCardView.Model.make(.init(
            provider: .codex,
            metadata: metadata,
            snapshot: snapshot,
            codexProjection: codexProjection,
            credits: credits,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: "codex@example.com", plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: false,
            hidePersonalInfo: false,
            now: now))

        #expect(model.creditsText == nil)
    }

    @Test
    func claude_model_does_not_show_obsolete_peak_hours_note() throws {
        let now = Date()
        let identity = ProviderIdentitySnapshot(
            providerID: .claude,
            accountEmail: "claude@example.com",
            accountOrganization: nil,
            loginMethod: nil)
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 30, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: now,
            identity: identity)
        let metadata = try #require(ProviderDefaults.metadata[.claude])

        let model = UsageMenuCardView.Model.make(.init(
            provider: .claude,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        #expect(model.usageNotes.isEmpty)
    }
}
