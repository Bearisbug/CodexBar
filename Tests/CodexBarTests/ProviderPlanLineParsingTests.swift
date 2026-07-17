import Testing
@testable import CodexBarCore

struct ProviderPlanLineParsingTests {
    @Test
    func Claude_plan_matching_does_not_bridge_usage_lines() {
        let usageText = """
        Skills, subagents, plugins, and MCP servers
        Noattributiondatayet·accumulatesasyouuseClaude

        dtoday·wtoweek

        Usagecredits
        Usagecreditsareoff·/usage-creditstoturnthemon
        """

        let identity = ClaudeStatusProbe.parseIdentity(usageText: usageText, statusText: nil)

        #expect(identity.loginMethod == nil)
    }

    @Test
    func Claude_plan_matching_keeps_single_line_phrases() {
        let identity = ClaudeStatusProbe.parseIdentity(
            usageText: nil,
            statusText: "Sonnet 4.6 · Claude Max · you@example.com")

        #expect(identity.loginMethod == "Max")
    }

    @Test
    func Kiro_legacy_plan_matching_does_not_bridge_lines() throws {
        let output = """
        |
        KIRO FREE
        ████████████████████████████████████████████████████ 25%
        (12.50 of 50 covered in plan), resets on 01/15
        """

        let snapshot = try KiroStatusProbe().parse(output: output)

        #expect(snapshot.planName == "Kiro")
    }

    @Test
    func Kiro_estimated_usage_plan_matching_does_not_bridge_lines() throws {
        let output = """
        Estimated Usage | resets on 2026-06-01 |
        KIRO FREE
        ████████████████████████████████████████████████████ 25%
        (12.50 of 50 covered in plan), resets on 01/15
        """

        let snapshot = try KiroStatusProbe().parse(output: output)

        #expect(snapshot.planName == "Kiro")
    }

    @Test
    func Kiro_labeled_plan_matching_does_not_bridge_lines() throws {
        let output = """
        Plan:
        Q Developer Pro
        ████████████████████████████████████████████████████ 25%
        (12.50 of 50 covered in plan), resets on 01/15
        """

        let snapshot = try KiroStatusProbe().parse(output: output)

        #expect(snapshot.planName == "Kiro")
    }
}
