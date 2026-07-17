import Testing
@testable import CodexBarCore

struct CopilotBudgetCookieRoutingTests {
    @Test
    func auto_budget_cookies_ignore_stale_manual_header() {
        let settings = ProviderSettingsSnapshot.CopilotProviderSettings(
            budgetExtrasEnabled: true,
            budgetCookieSource: .auto,
            manualBudgetCookieHeader: "user_session=stale")

        #expect(CopilotAPIFetchStrategy.budgetCookieHeaderOverride(from: settings) == nil)
    }

    @Test
    func manual_budget_cookies_use_trimmed_manual_header() {
        let settings = ProviderSettingsSnapshot.CopilotProviderSettings(
            budgetExtrasEnabled: true,
            budgetCookieSource: .manual,
            manualBudgetCookieHeader: "  user_session=manual  ")

        #expect(CopilotAPIFetchStrategy.budgetCookieHeaderOverride(from: settings) == "user_session=manual")
    }

    @Test
    func manual_budget_cookies_require_non_empty_header() {
        let settings = ProviderSettingsSnapshot.CopilotProviderSettings(
            budgetExtrasEnabled: true,
            budgetCookieSource: .manual,
            manualBudgetCookieHeader: "  ")

        #expect(CopilotAPIFetchStrategy.budgetCookieHeaderOverride(from: settings) == nil)
    }

    @Test
    func invalid_manual_budget_cookies_do_not_fall_back_to_browser_import() {
        let settings = ProviderSettingsSnapshot.CopilotProviderSettings(
            budgetExtrasEnabled: true,
            budgetCookieSource: .manual,
            manualBudgetCookieHeader: "Cookie:")

        #expect(CopilotAPIFetchStrategy.budgetCookieHeaderOverride(from: settings) == nil)
    }
}
