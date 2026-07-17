import Foundation
import Testing
@testable import CodexBarCore

struct ClaudePlanResolverTests {
    @Test
    func oauth_rate_limit_tier_maps_to_branded_plan() {
        #expect(ClaudePlan.oauthLoginMethod(rateLimitTier: "claude_pro") == "Claude Pro")
        #expect(ClaudePlan.oauthLoginMethod(rateLimitTier: "claude_team") == "Claude Team")
        #expect(ClaudePlan.oauthLoginMethod(rateLimitTier: "claude_enterprise") == "Claude Enterprise")
    }

    @Test
    func oauth_rate_limit_tier_preserves_the_Max_usage_multiplier() {
        #expect(ClaudePlan.oauthLoginMethod(rateLimitTier: "default_claude_max_5x") == "Claude Max 5x")
        #expect(ClaudePlan.oauthLoginMethod(rateLimitTier: "default_claude_max_20x") == "Claude Max 20x")
        #expect(ClaudePlan.oauthLoginMethod(rateLimitTier: "v2_default_claude_max_20x") == "Claude Max 20x")
        // A bare Max tier without a multiplier keeps the plain label.
        #expect(ClaudePlan.oauthLoginMethod(rateLimitTier: "claude_max") == "Claude Max")
        #expect(ClaudePlan.oauthLoginMethod(rateLimitTier: "default_claude_team_5x") == "Claude Team")
        // A resolved non-Max plan never inherits a Max multiplier from a disagreeing tier.
        #expect(
            ClaudePlan.oauthLoginMethod(subscriptionType: "team", rateLimitTier: "default_claude_max_5x")
                == "Claude Team")
        #expect(
            ClaudePlan.webLoginMethod(rateLimitTier: "default_claude_max_20x", billingType: nil)
                == "Claude Max 20x")
    }

    @Test
    func oauth_subscription_type_overrides_generic_rate_limit_tier() {
        #expect(
            ClaudePlan.oauthLoginMethod(subscriptionType: "pro", rateLimitTier: "default_claude_ai")
                == "Claude Pro")
        #expect(
            ClaudePlan.oauthLoginMethod(subscriptionType: "team", rateLimitTier: "default_claude_max_5x")
                == "Claude Team")
        #expect(ClaudePlan.oauthLoginMethod(subscriptionType: nil, rateLimitTier: "default_claude_ai") == nil)
    }

    @Test
    func web_fallback_preserves_stripe_Claude_compatibility() {
        #expect(
            ClaudePlan.webLoginMethod(
                rateLimitTier: "default_claude",
                billingType: "stripe_subscription")
                == "Claude Pro")
    }

    @Test
    func web_team_seat_tiers_map_to_specific_labels() {
        #expect(
            ClaudePlan.webLoginMethod(
                rateLimitTier: "claude_team",
                billingType: "stripe_subscription",
                seatTier: "team_standard")
                == "Claude Team Standard")
        #expect(
            ClaudePlan.webLoginMethod(
                rateLimitTier: "claude_team",
                billingType: "stripe_subscription",
                seatTier: "team_tier_1")
                == "Claude Team Premium")
        #expect(
            ClaudePlan.webLoginMethod(
                rateLimitTier: nil,
                billingType: nil,
                seatTier: "team_standard")
                == "Claude Team Standard")
    }

    @Test
    func web_team_seat_tier_near_misses_use_existing_plan_inference() {
        #expect(
            ClaudePlan.webLoginMethod(
                rateLimitTier: "claude_team",
                billingType: "stripe_subscription",
                seatTier: "team_premium")
                == "Claude Team")
        #expect(
            ClaudePlan.webLoginMethod(
                rateLimitTier: "claude_team",
                billingType: "stripe_subscription",
                seatTier: "team_standard_plus")
                == "Claude Team")
    }

    @Test
    func web_enterprise_seat_tiers_preserve_the_enterprise_label() {
        #expect(
            ClaudePlan.webLoginMethod(
                rateLimitTier: "claude_enterprise",
                billingType: "stripe_subscription",
                seatTier: "team_standard")
                == "Claude Enterprise")
        #expect(
            ClaudePlan.webLoginMethod(
                rateLimitTier: "claude_enterprise",
                billingType: "stripe_subscription",
                seatTier: "team_tier_1")
                == "Claude Enterprise")
    }

    @Test
    func missing_web_seat_tier_preserves_existing_plan_labels() {
        #expect(
            ClaudePlan.webLoginMethod(
                rateLimitTier: "default_claude_max_20x",
                billingType: nil,
                seatTier: nil)
                == "Claude Max 20x")
        #expect(
            ClaudePlan.webLoginMethod(
                rateLimitTier: "claude_pro",
                billingType: "stripe_subscription",
                seatTier: nil)
                == "Claude Pro")
        #expect(
            ClaudePlan.webLoginMethod(
                rateLimitTier: "claude_team",
                billingType: "stripe_subscription",
                seatTier: nil)
                == "Claude Team")
    }

    @Test
    func compatibility_parser_understands_current_labels() {
        #expect(ClaudePlan.fromCompatibilityLoginMethod("Claude Max") == .max)
        #expect(ClaudePlan.fromCompatibilityLoginMethod("Max") == .max)
        #expect(ClaudePlan.fromCompatibilityLoginMethod("Claude Pro") == .pro)
        #expect(ClaudePlan.fromCompatibilityLoginMethod("Ultra") == .ultra)
        #expect(ClaudePlan.fromCompatibilityLoginMethod("Claude Team") == .team)
        #expect(ClaudePlan.fromCompatibilityLoginMethod("Claude Enterprise") == .enterprise)
    }

    @Test
    func CLI_projection_keeps_compact_compatibility_and_unknown_fallback() {
        #expect(ClaudePlan.cliCompatibilityLoginMethod("Claude Max Account") == "Max")
        #expect(ClaudePlan.cliCompatibilityLoginMethod("Team") == "Team")
        #expect(ClaudePlan.cliCompatibilityLoginMethod("Claude Enterprise Account") == "Enterprise")
        #expect(ClaudePlan.cliCompatibilityLoginMethod("Claude Ultra Account") == "Ultra")
        #expect(ClaudePlan.cliCompatibilityLoginMethod("Experimental") == "Experimental")
        #expect(ClaudePlan.cliCompatibilityLoginMethod("Profile") == "Profile")
        #expect(ClaudePlan.cliCompatibilityLoginMethod("Browser profile") == "Browser profile")
    }

    @Test
    func subscription_compatibility_preserves_ultra_and_excludes_enterprise() {
        #expect(ClaudePlan.isSubscriptionLoginMethod("Claude Max"))
        #expect(ClaudePlan.isSubscriptionLoginMethod("Pro"))
        #expect(ClaudePlan.isSubscriptionLoginMethod("Ultra"))
        #expect(ClaudePlan.isSubscriptionLoginMethod("Team"))
        #expect(!ClaudePlan.isSubscriptionLoginMethod("Claude Enterprise"))
        #expect(!ClaudePlan.isSubscriptionLoginMethod("Profile"))
        #expect(!ClaudePlan.isSubscriptionLoginMethod("Browser profile"))
        #expect(!ClaudePlan.isSubscriptionLoginMethod("API"))
    }
}
