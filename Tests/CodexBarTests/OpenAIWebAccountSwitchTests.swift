import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct OpenAIWebAccountSwitchTests {
    @Test
    func clears_dashboard_when_codex_email_changes() {
        let settings = SettingsStore(
            configStore: testConfigStore(suiteName: "OpenAIWebAccountSwitchTests-clears"),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.refreshFrequency = .manual

        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)

        store.handleOpenAIWebTargetEmailChangeIfNeeded(targetEmail: "a@example.com")
        store.openAIDashboard = OpenAIDashboardSnapshot(
            signedInEmail: "a@example.com",
            codeReviewRemainingPercent: 100,
            creditEvents: [],
            dailyBreakdown: [],
            usageBreakdown: [],
            creditsPurchaseURL: nil,
            updatedAt: Date())

        store.handleOpenAIWebTargetEmailChangeIfNeeded(targetEmail: "b@example.com")
        #expect(store.openAIDashboard == nil)
        #expect(store.openAIDashboardRequiresLogin == true)
        #expect(store.openAIDashboardCookieImportStatus?.contains("Codex account changed") == true)
    }

    @Test
    func keeps_dashboard_when_codex_email_stays_same() {
        let settings = SettingsStore(
            configStore: testConfigStore(suiteName: "OpenAIWebAccountSwitchTests-keeps"),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.refreshFrequency = .manual

        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)

        store.handleOpenAIWebTargetEmailChangeIfNeeded(targetEmail: "a@example.com")
        let dash = OpenAIDashboardSnapshot(
            signedInEmail: "a@example.com",
            codeReviewRemainingPercent: 100,
            creditEvents: [],
            dailyBreakdown: [],
            usageBreakdown: [],
            creditsPurchaseURL: nil,
            updatedAt: Date())
        store.openAIDashboard = dash

        store.handleOpenAIWebTargetEmailChangeIfNeeded(targetEmail: "a@example.com")
        #expect(store.openAIDashboard == dash)
    }

    @Test
    func clears_dashboard_when_profile_source_changes_with_the_same_email() {
        let settings = SettingsStore(
            configStore: testConfigStore(suiteName: "OpenAIWebAccountSwitchTests-profile-source"),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)

        store.handleOpenAIWebTargetEmailChangeIfNeeded(
            targetEmail: "shared@example.com",
            targetScope: .profileHome("/tmp/codex-profile-a"))
        store.openAIDashboard = OpenAIDashboardSnapshot(
            signedInEmail: "shared@example.com",
            codeReviewRemainingPercent: 100,
            creditEvents: [],
            dailyBreakdown: [],
            usageBreakdown: [],
            creditsPurchaseURL: nil,
            updatedAt: Date())

        store.handleOpenAIWebTargetEmailChangeIfNeeded(
            targetEmail: "shared@example.com",
            targetScope: .profileHome("/tmp/codex-profile-b"))

        #expect(store.openAIDashboard == nil)
        #expect(store.openAIWebAccountDidChange)
        #expect(store.openAIDashboardRequiresLogin)
    }
}
