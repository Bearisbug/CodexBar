import Testing
@testable import CodexBar

struct CursorLoginAccountSelectorTests {
    @Test
    func labels_include_available_identity_metadata_and_always_include_the_source() {
        let choices = CursorLoginAccountSelector.choices(for: [
            .init(
                selectionID: "name-and-email",
                name: "Example Team",
                email: "team@example.com",
                sourceLabel: "Comet · Work"),
            .init(
                selectionID: "email-only",
                name: nil,
                email: "personal@example.com",
                sourceLabel: "Safari"),
            .init(
                selectionID: "source-only",
                name: nil,
                email: nil,
                sourceLabel: "Chrome · Profile 2"),
        ])

        #expect(Set(choices.map(\.displayLabel)) == [
            "Example Team · team@example.com · Comet · Work",
            "personal@example.com · Safari",
            "\(L("Account")) · Chrome · Profile 2",
        ])
    }

    @Test
    func same_email_candidates_from_different_sources_remain_separate_choices() {
        let candidates: [CursorLoginAccountSelector.Candidate] = [
            .init(
                selectionID: "account-comet",
                name: nil,
                email: "same@example.com",
                sourceLabel: "Comet"),
            .init(
                selectionID: "account-safari",
                name: nil,
                email: "same@example.com",
                sourceLabel: "Safari"),
        ]

        let choices = CursorLoginAccountSelector.choices(for: candidates)

        #expect(choices.map(\.selectionID) == ["account-comet", "account-safari"])
        #expect(choices.map(\.displayLabel) == [
            "same@example.com · Comet",
            "same@example.com · Safari",
        ])
    }

    @Test
    func identical_account_labels_use_human_ordinals_while_stable_IDs_remain_mapping_only() {
        let choices = CursorLoginAccountSelector.choices(for: [
            .init(
                selectionID: "stable-b",
                name: nil,
                email: "same@example.com",
                sourceLabel: "Comet"),
            .init(
                selectionID: "stable-a",
                name: nil,
                email: "same@example.com",
                sourceLabel: "Comet"),
        ])

        #expect(choices == [
            .init(selectionID: "stable-a", displayLabel: "same@example.com · Comet · 1"),
            .init(selectionID: "stable-b", displayLabel: "same@example.com · Comet · 2"),
        ])
        #expect(choices.allSatisfy { !$0.displayLabel.contains("stable-") })
    }

    @Test
    func choice_ordering_is_deterministic_regardless_of_candidate_order() {
        let candidates: [CursorLoginAccountSelector.Candidate] = [
            .init(selectionID: "z", name: "Zed", email: nil, sourceLabel: "Safari"),
            .init(selectionID: "a", name: "Alpha", email: nil, sourceLabel: "Comet"),
        ]

        #expect(CursorLoginAccountSelector.choices(for: candidates) ==
            CursorLoginAccountSelector.choices(for: Array(candidates.reversed())))
    }

    @Test
    func non_UI_selection_helper_maps_confirmation_and_cancellation() {
        let choices: [CursorLoginAccountSelector.Choice] = [
            .init(selectionID: "first", displayLabel: "First · Safari"),
            .init(selectionID: "second", displayLabel: "Second · Comet"),
        ]

        #expect(CursorLoginAccountSelector.selectedCandidateID(
            from: choices,
            selectedIndex: 1,
            confirmed: true) == "second")
        #expect(CursorLoginAccountSelector.selectedCandidateID(
            from: choices,
            selectedIndex: 1,
            confirmed: false) == nil)
        #expect(CursorLoginAccountSelector.selectedCandidateID(
            from: choices,
            selectedIndex: nil,
            confirmed: true) == nil)
        #expect(CursorLoginAccountSelector.selectedCandidateID(
            from: choices,
            selectedIndex: 2,
            confirmed: true) == nil)
    }

    @Test
    @MainActor
    func injected_chooser_maps_only_a_presented_stable_selection_ID() {
        let candidates: [CursorLoginAccountSelector.Candidate] = [
            .init(selectionID: "first", name: nil, email: "a@example.com", sourceLabel: "Safari"),
            .init(selectionID: "second", name: nil, email: "b@example.com", sourceLabel: "Comet"),
        ]
        var presentedChoices: [CursorLoginAccountSelector.Choice] = []

        let selectedID = CursorLoginAccountSelector.selectCandidateID(from: candidates) {
            presentedChoices = $0
            return "second"
        }
        let cancelledID = CursorLoginAccountSelector.selectCandidateID(from: candidates) { _ in nil }
        let unknownID = CursorLoginAccountSelector.selectCandidateID(from: candidates) { _ in "unknown" }

        #expect(presentedChoices == CursorLoginAccountSelector.choices(for: candidates))
        #expect(selectedID == "second")
        #expect(cancelledID == nil)
        #expect(unknownID == nil)
    }
}
