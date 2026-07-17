import AdaptiveReplayKit
import Testing
@testable import AdaptiveReplayCLI

struct CLIArgumentsTests {
    @Test(arguments: [
        "fixed-0m",
        "fixed--1m",
        "fixed-3m",
        "fixed-9223372036854775807m",
    ])
    func rejects_invalid_fixed_interval_names_before_policy_construction(rawPolicyName: String) {
        let arguments = CLIArguments.parse(["trace.jsonl", "--policy", rawPolicyName])

        guard case let .invalid(message) = arguments else {
            Issue.record("Expected \(rawPolicyName) to be rejected")
            return
        }
        #expect(message.contains(rawPolicyName))
        #expect(message.contains(ReplayPolicyName.expectedValues))
    }

    @Test(arguments: ReplayPolicyName.allCases)
    func accepts_every_documented_policy_name(policyName: ReplayPolicyName) {
        let arguments = CLIArguments.parse(["trace.jsonl", "--policy", policyName.rawValue])

        guard case let .run(tracePath, policyNames, jsonOutput, _) = arguments else {
            Issue.record("Expected \(policyName.rawValue) to be accepted")
            return
        }
        #expect(tracePath == "trace.jsonl")
        #expect(policyNames == [policyName])
        #expect(policyNames.map(\.policy.name) == [policyName.rawValue])
        #expect(!jsonOutput)
    }

    @Test
    func omitting_policy_selects_every_documented_policy() {
        let arguments = CLIArguments.parse(["trace.jsonl"])

        guard case let .run(_, policyNames, _, _) = arguments else {
            Issue.record("Expected the default policy set")
            return
        }
        #expect(policyNames == ReplayPolicyName.allCases)
    }
}
