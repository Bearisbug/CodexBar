import CodexBarCore
import Testing
@testable import CodexBar

struct MenuOpenRefreshPlanTests {
    @Test
    func refresh_all_selects_every_enabled_provider_concurrently() {
        let plan = MenuOpenRefreshPlan.resolve(.init(
            refreshAllOnOpen: true,
            enabledProviders: [.codex, .claude, .factory],
            visibleProviders: [.codex],
            refreshingProviders: [],
            staleProviders: [],
            missingProviders: []))

        #expect(plan.providers == [.codex, .claude, .factory])
        #expect(plan.scheduling == .concurrent)
        #expect(plan.refreshCodexDashboard)
    }

    @Test
    func refresh_all_skips_dashboard_refresh_when_codex_is_disabled() {
        let plan = MenuOpenRefreshPlan.resolve(.init(
            refreshAllOnOpen: true,
            enabledProviders: [.claude, .factory],
            visibleProviders: [.claude],
            refreshingProviders: [],
            staleProviders: [],
            missingProviders: []))

        #expect(plan.providers == [.claude, .factory])
        #expect(!plan.refreshCodexDashboard)
    }

    @Test
    func ordinary_refresh_selects_only_visible_enabled_retries_sequentially() {
        let plan = MenuOpenRefreshPlan.resolve(.init(
            refreshAllOnOpen: false,
            enabledProviders: [.codex, .claude, .factory],
            visibleProviders: [.factory, .codex, .claude, .cursor],
            refreshingProviders: [.factory],
            staleProviders: [.codex],
            missingProviders: [.claude, .cursor]))

        #expect(plan.providers == [.factory, .codex, .claude])
        #expect(plan.scheduling == .sequential)
        #expect(!plan.refreshCodexDashboard)
    }

    @Test
    func ordinary_refresh_skips_fresh_providers() {
        let plan = MenuOpenRefreshPlan.resolve(.init(
            refreshAllOnOpen: false,
            enabledProviders: [.codex],
            visibleProviders: [.codex],
            refreshingProviders: [],
            staleProviders: [],
            missingProviders: []))

        #expect(plan.providers.isEmpty)
    }
}
