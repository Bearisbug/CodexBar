import Foundation
import Testing
@testable import CodexBar

struct SubscriptionDetectionTests {
    // MARK: - Subscription plans should be detected

    @Test
    func detects_max_plan() {
        #expect(UsageStore.isSubscriptionPlan("Claude Max") == true)
        #expect(UsageStore.isSubscriptionPlan("Max") == true)
        #expect(UsageStore.isSubscriptionPlan("claude max") == true)
        #expect(UsageStore.isSubscriptionPlan("MAX") == true)
    }

    @Test
    func detects_pro_plan() {
        #expect(UsageStore.isSubscriptionPlan("Claude Pro") == true)
        #expect(UsageStore.isSubscriptionPlan("Pro") == true)
        #expect(UsageStore.isSubscriptionPlan("pro") == true)
    }

    @Test
    func detects_ultra_plan() {
        #expect(UsageStore.isSubscriptionPlan("Claude Ultra") == true)
        #expect(UsageStore.isSubscriptionPlan("Ultra") == true)
        #expect(UsageStore.isSubscriptionPlan("ultra") == true)
    }

    @Test
    func detects_team_plan() {
        #expect(UsageStore.isSubscriptionPlan("Claude Team") == true)
        #expect(UsageStore.isSubscriptionPlan("Team") == true)
        #expect(UsageStore.isSubscriptionPlan("team") == true)
    }

    @Test
    func enterprise_plan_does_not_count_as_subscription() {
        #expect(UsageStore.isSubscriptionPlan("Claude Enterprise") == false)
        #expect(UsageStore.isSubscriptionPlan("Enterprise") == false)
    }

    // MARK: - Non-subscription plans should return false

    @Test
    func nil_login_method_returns_false() {
        #expect(UsageStore.isSubscriptionPlan(nil) == false)
    }

    @Test
    func empty_login_method_returns_false() {
        #expect(UsageStore.isSubscriptionPlan("") == false)
        #expect(UsageStore.isSubscriptionPlan("   ") == false)
    }

    @Test
    func unknown_plan_returns_false() {
        #expect(UsageStore.isSubscriptionPlan("API") == false)
        #expect(UsageStore.isSubscriptionPlan("Free") == false)
        #expect(UsageStore.isSubscriptionPlan("Unknown") == false)
        #expect(UsageStore.isSubscriptionPlan("Claude") == false)
    }

    @Test
    func api_key_users_return_false() {
        // API users typically don't have a login method or have non-subscription identifiers
        #expect(UsageStore.isSubscriptionPlan("api_key") == false)
        #expect(UsageStore.isSubscriptionPlan("console") == false)
    }
}
