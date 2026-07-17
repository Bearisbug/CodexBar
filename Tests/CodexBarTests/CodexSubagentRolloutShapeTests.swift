import Testing
@testable import CodexBarCore

struct CodexSubagentRolloutShapeTests {
    @Test
    func single_leaf_metadata_means_an_independent_counter() {
        let shape = CostUsageScanner.CodexSubagentRolloutShape.classify(
            leafSessionID: "leaf",
            observedSessionIDs: ["leaf"])

        #expect(shape.counterSemantics == .independent)
    }

    @Test
    func embedded_ancestor_metadata_means_a_copied_prefix() {
        let shape = CostUsageScanner.CodexSubagentRolloutShape.classify(
            leafSessionID: "leaf",
            observedSessionIDs: ["leaf", "parent"])

        #expect(shape.counterSemantics == .copiedPrefix)
        #expect(shape.inferredParentSessionID == "parent")
    }

    @Test
    func multiple_ancestors_do_not_infer_an_ambiguous_parent() {
        let shape = CostUsageScanner.CodexSubagentRolloutShape.classify(
            leafSessionID: "leaf",
            observedSessionIDs: ["leaf", "parent", "grandparent"])

        #expect(shape.counterSemantics == .copiedPrefix)
        #expect(shape.inferredParentSessionID == nil)
    }

    @Test
    func repeated_leaf_metadata_does_not_invent_an_ancestor() {
        let shape = CostUsageScanner.CodexSubagentRolloutShape.classify(
            leafSessionID: "leaf",
            observedSessionIDs: ["leaf", "leaf"])

        #expect(shape.counterSemantics == .independent)
    }

    @Test
    func unknown_leaf_followed_by_a_concrete_metadata_id_is_copied() {
        let shape = CostUsageScanner.CodexSubagentRolloutShape.classify(
            leafSessionID: nil,
            observedSessionIDs: [nil, "parent"])

        #expect(shape.counterSemantics == .copiedPrefix)
        #expect(shape.inferredParentSessionID == "parent")
    }

    @Test
    func idless_metadata_after_a_known_leaf_is_conservatively_copied() {
        let shape = CostUsageScanner.CodexSubagentRolloutShape.classify(
            leafSessionID: "leaf",
            observedSessionIDs: ["leaf", nil])

        #expect(shape.counterSemantics == .copiedPrefix)
        #expect(shape.inferredParentSessionID == nil)
    }

    @Test
    func only_concrete_normalized_ids_identify_the_same_leaf() {
        #expect(CostUsageScanner.CodexSubagentRolloutShape.sameConcreteSessionID(" leaf ", "leaf"))
        #expect(!CostUsageScanner.CodexSubagentRolloutShape.sameConcreteSessionID(nil, nil))
        #expect(!CostUsageScanner.CodexSubagentRolloutShape.sameConcreteSessionID("", ""))
    }

    @Test
    func adjacent_trigger_after_the_final_ancestor_opens_an_owned_suffix() throws {
        let baseline = CostUsageCodexTotals(input: 1000, cached: 900, output: 100)
        let shape = CostUsageScanner.CodexSubagentRolloutShape.classify(
            leafSessionID: "leaf",
            observations: [
                .init(lineIndex: 0, kind: .sessionMetadata(id: "leaf")),
                .init(lineIndex: 4, kind: .tokenCount(total: baseline, last: nil)),
                .init(lineIndex: 5, kind: .sessionMetadata(id: "parent")),
                .init(lineIndex: 8, kind: .turnContext),
                .init(lineIndex: 9, kind: .interAgentCommunication(triggerTurn: true)),
            ])

        let suffix = try #require(shape.ownedSuffix)
        #expect(shape.counterSemantics == .copiedPrefix)
        #expect(suffix.startLineIndex == 8)
        #expect(suffix.rawTotalsBaseline.input == 1000)
        #expect(suffix.rawTotalsBaseline.cached == 900)
        #expect(suffix.rawTotalsBaseline.output == 100)
    }

    @Test
    func nonadjacent_trigger_does_not_invent_an_owned_suffix() {
        let shape = CostUsageScanner.CodexSubagentRolloutShape.classify(
            leafSessionID: "leaf",
            observations: [
                .init(
                    lineIndex: 0,
                    kind: .tokenCount(
                        total: .init(input: 1000, cached: 900, output: 100),
                        last: nil)),
                .init(lineIndex: 1, kind: .sessionMetadata(id: "parent")),
                .init(lineIndex: 3, kind: .turnContext),
                .init(lineIndex: 5, kind: .interAgentCommunication(triggerTurn: true)),
            ])

        #expect(shape.counterSemantics == .copiedPrefix)
        #expect(shape.ownedSuffix == nil)
    }

    @Test
    func copied_prefix_can_restart_only_with_strong_reset_evidence() throws {
        let shape = CostUsageScanner.CodexSubagentRolloutShape.classify(
            leafSessionID: "leaf",
            observations: [
                .init(lineIndex: 0, kind: .sessionMetadata(id: "leaf")),
                .init(
                    lineIndex: 2,
                    kind: .tokenCount(
                        total: .init(input: 1000, cached: 900, output: 100),
                        last: nil)),
                .init(lineIndex: 3, kind: .sessionMetadata(id: "parent")),
                .init(lineIndex: 5, kind: .turnContext),
                .init(lineIndex: 6, kind: .interAgentCommunication(triggerTurn: true)),
                .init(
                    lineIndex: 7,
                    kind: .tokenCount(
                        total: .init(input: 50, cached: 10, output: 5),
                        last: .init(input: 50, cached: 10, output: 5))),
            ])

        let suffix = try #require(shape.ownedSuffix)
        #expect(suffix.rawTotalsBaseline.input == 0)
        #expect(suffix.rawTotalsBaseline.cached == 0)
        #expect(suffix.rawTotalsBaseline.output == 0)
    }

    @Test
    func first_valid_leaf_marker_owns_later_leaf_turns() throws {
        let firstBaseline = CostUsageCodexTotals(input: 1000, cached: 900, output: 100)
        let shape = CostUsageScanner.CodexSubagentRolloutShape.classify(
            leafSessionID: "leaf",
            observations: [
                .init(lineIndex: 0, kind: .sessionMetadata(id: "leaf")),
                .init(lineIndex: 1, kind: .sessionMetadata(id: "parent")),
                .init(lineIndex: 2, kind: .tokenCount(total: firstBaseline, last: nil)),
                .init(lineIndex: 4, kind: .turnContext),
                .init(lineIndex: 5, kind: .interAgentCommunication(triggerTurn: true)),
                .init(
                    lineIndex: 6,
                    kind: .tokenCount(
                        total: .init(input: 1050, cached: 910, output: 105),
                        last: nil)),
                .init(lineIndex: 8, kind: .turnContext),
                .init(lineIndex: 9, kind: .interAgentCommunication(triggerTurn: true)),
            ])

        let suffix = try #require(shape.ownedSuffix)
        #expect(suffix.startLineIndex == 4)
        #expect(suffix.rawTotalsBaseline.input == firstBaseline.input)
    }

    @Test
    func later_ancestor_invalidates_a_tentative_marker() throws {
        let shape = CostUsageScanner.CodexSubagentRolloutShape.classify(
            leafSessionID: "leaf",
            observations: [
                .init(lineIndex: 0, kind: .sessionMetadata(id: "leaf")),
                .init(lineIndex: 1, kind: .sessionMetadata(id: "parent")),
                .init(
                    lineIndex: 2,
                    kind: .tokenCount(
                        total: .init(input: 1000, cached: 900, output: 100),
                        last: nil)),
                .init(lineIndex: 3, kind: .turnContext),
                .init(lineIndex: 4, kind: .interAgentCommunication(triggerTurn: true)),
                .init(lineIndex: 5, kind: .sessionMetadata(id: "grandparent")),
                .init(
                    lineIndex: 6,
                    kind: .tokenCount(
                        total: .init(input: 2000, cached: 1800, output: 200),
                        last: nil)),
                .init(lineIndex: 8, kind: .turnContext),
                .init(lineIndex: 9, kind: .interAgentCommunication(triggerTurn: true)),
            ])

        let suffix = try #require(shape.ownedSuffix)
        #expect(suffix.startLineIndex == 8)
        #expect(suffix.rawTotalsBaseline.input == 2000)
    }
}
