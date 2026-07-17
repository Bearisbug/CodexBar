import CodexBarCore
import Foundation
import Testing

struct CodexPlanFormattingTests {
    @Test
    func maps_Codex_pro_plans_to_usage_multiplier_names() {
        #expect(CodexPlanFormatting.displayName("pro") == "Pro 20x")
        #expect(CodexPlanFormatting.displayName("Pro") == "Pro 20x")
        #expect(CodexPlanFormatting.displayName("Codex Pro") == "Pro 20x")
        #expect(CodexPlanFormatting.displayName("prolite") == "Pro 5x")
        #expect(CodexPlanFormatting.displayName("pro_lite") == "Pro 5x")
        #expect(CodexPlanFormatting.displayName("pro-lite") == "Pro 5x")
        #expect(CodexPlanFormatting.displayName("Pro Lite") == "Pro 5x")
        #expect(CodexPlanFormatting.displayName("Codex Pro Lite") == "Pro 5x")
    }

    @Test
    func returns_nil_for_empty_plan_values() {
        #expect(CodexPlanFormatting.displayName(nil) == nil)
        #expect(CodexPlanFormatting.displayName("") == nil)
        #expect(CodexPlanFormatting.displayName("   ") == nil)
    }

    @Test
    func humanizes_machine_style_plan_identifiers() {
        #expect(
            CodexPlanFormatting.displayName("enterprise_cbp_usage_based")
                == "Enterprise CBP Usage Based")
        #expect(
            CodexPlanFormatting.displayName("self_serve_business_usage_based")
                == "Self Serve Business Usage Based")
        #expect(CodexPlanFormatting.displayName("k12") == "K12")
    }

    @Test
    func preserves_unrelated_already_readable_plan_text() {
        #expect(CodexPlanFormatting.displayName("Enterprise") == "Enterprise")
    }
}
