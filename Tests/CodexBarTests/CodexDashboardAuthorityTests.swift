import CodexBarCore
import Testing

struct CodexDashboardAuthorityTests {
    @Test
    func email_only_wrong_email_returns_fail_closed() {
        let input = CodexDashboardAuthorityInput(
            sourceKind: .liveWeb,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .emailOnly(normalizedEmail: "owner@example.com"),
                expectedScopedEmail: nil,
                trustedCurrentUsageEmail: nil,
                dashboardSignedInEmail: "other@example.com",
                knownOwners: [
                    CodexDashboardKnownOwnerCandidate(
                        identity: .emailOnly(normalizedEmail: "owner@example.com"),
                        normalizedEmail: "owner@example.com"),
                ]),
            routing: CodexDashboardRoutingHints(
                targetEmail: "owner@example.com",
                lastKnownDashboardRoutingEmail: nil))

        let decision = CodexDashboardAuthority.evaluate(input)

        #expect(decision.disposition == .failClosed)
        #expect(decision.reason == .wrongEmail(expected: "owner@example.com", actual: "other@example.com"))
    }

    @Test
    func provider_account_wrong_email_returns_fail_closed() {
        let input = CodexDashboardAuthorityInput(
            sourceKind: .liveWeb,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .providerAccount(id: "acct-owner"),
                expectedScopedEmail: "owner@example.com",
                trustedCurrentUsageEmail: nil,
                dashboardSignedInEmail: "other@example.com",
                knownOwners: [
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-owner"),
                        normalizedEmail: "owner@example.com"),
                ]),
            routing: CodexDashboardRoutingHints(
                targetEmail: "owner@example.com",
                lastKnownDashboardRoutingEmail: "stale@example.com"))

        let decision = CodexDashboardAuthority.evaluate(input)

        #expect(decision.disposition == .failClosed)
        #expect(decision.reason == .wrongEmail(expected: "owner@example.com", actual: "other@example.com"))
    }

    @Test
    func email_only_same_email_ambiguity_returns_display_only() {
        let input = CodexDashboardAuthorityInput(
            sourceKind: .liveWeb,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .emailOnly(normalizedEmail: "shared@example.com"),
                expectedScopedEmail: nil,
                trustedCurrentUsageEmail: nil,
                dashboardSignedInEmail: "shared@example.com",
                knownOwners: [
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-alpha"),
                        normalizedEmail: "shared@example.com"),
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-beta"),
                        normalizedEmail: "shared@example.com"),
                ]),
            routing: CodexDashboardRoutingHints(
                targetEmail: "shared@example.com",
                lastKnownDashboardRoutingEmail: "shared@example.com"))

        let decision = CodexDashboardAuthority.evaluate(input)

        #expect(decision.disposition == .displayOnly)
        #expect(decision.reason == .sameEmailAmbiguity(email: "shared@example.com"))
    }

    @Test
    func provider_account_exact_owner_match_returns_attach() {
        let input = CodexDashboardAuthorityInput(
            sourceKind: .liveWeb,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .providerAccount(id: "acct-owner"),
                expectedScopedEmail: "OWNER@example.com",
                trustedCurrentUsageEmail: nil,
                dashboardSignedInEmail: "owner@example.com",
                knownOwners: [
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-owner"),
                        normalizedEmail: "OWNER@example.com"),
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-other"),
                        normalizedEmail: "other@example.com"),
                ]),
            routing: CodexDashboardRoutingHints(
                targetEmail: "route@example.com",
                lastKnownDashboardRoutingEmail: "stale@example.com"))

        let decision = CodexDashboardAuthority.evaluate(input)

        #expect(decision.disposition == .attach)
        #expect(decision.reason == .exactProviderAccountMatch)
    }

    @Test
    func provider_account_exact_owner_ignores_duplicate_profile_isolation() {
        let input = CodexDashboardAuthorityInput(
            sourceKind: .liveWeb,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .providerAccount(id: "acct-owner"),
                expectedScopedEmail: "owner@example.com",
                trustedCurrentUsageEmail: nil,
                dashboardSignedInEmail: "owner@example.com",
                knownOwners: [
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-owner"),
                        normalizedEmail: "owner@example.com",
                        sourceIsolationIdentifier: "profile-a"),
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-owner"),
                        normalizedEmail: "owner@example.com",
                        sourceIsolationIdentifier: "profile-b"),
                ]),
            routing: CodexDashboardRoutingHints(
                targetEmail: "owner@example.com",
                lastKnownDashboardRoutingEmail: nil))

        let decision = CodexDashboardAuthority.evaluate(input)

        #expect(decision.disposition == .attach)
        #expect(decision.reason == .exactProviderAccountMatch)
    }

    @Test
    func email_only_owners_retain_profile_isolation_ambiguity() {
        let input = CodexDashboardAuthorityInput(
            sourceKind: .liveWeb,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .emailOnly(normalizedEmail: "shared@example.com"),
                expectedScopedEmail: "shared@example.com",
                trustedCurrentUsageEmail: nil,
                dashboardSignedInEmail: "shared@example.com",
                knownOwners: [
                    CodexDashboardKnownOwnerCandidate(
                        identity: .emailOnly(normalizedEmail: "shared@example.com"),
                        normalizedEmail: "shared@example.com",
                        sourceIsolationIdentifier: "profile-a"),
                    CodexDashboardKnownOwnerCandidate(
                        identity: .emailOnly(normalizedEmail: "shared@example.com"),
                        normalizedEmail: "shared@example.com",
                        sourceIsolationIdentifier: "profile-b"),
                ]),
            routing: CodexDashboardRoutingHints(
                targetEmail: "shared@example.com",
                lastKnownDashboardRoutingEmail: nil))

        let decision = CodexDashboardAuthority.evaluate(input)

        #expect(decision.disposition == .displayOnly)
        #expect(decision.reason == .sameEmailAmbiguity(email: "shared@example.com"))
    }

    @Test
    func provider_account_exact_owner_stays_display_only_when_email_has_another_owner() {
        let input = CodexDashboardAuthorityInput(
            sourceKind: .liveWeb,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .providerAccount(id: "acct-current"),
                expectedScopedEmail: "shared@example.com",
                trustedCurrentUsageEmail: nil,
                dashboardSignedInEmail: "shared@example.com",
                knownOwners: [
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-current"),
                        normalizedEmail: "shared@example.com"),
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-other"),
                        normalizedEmail: "shared@example.com"),
                ]),
            routing: CodexDashboardRoutingHints(
                targetEmail: "shared@example.com",
                lastKnownDashboardRoutingEmail: nil))

        let decision = CodexDashboardAuthority.evaluate(input)

        #expect(decision.disposition == .displayOnly)
        #expect(decision.reason == .sameEmailAmbiguity(email: "shared@example.com"))
    }

    @Test
    func provider_account_same_email_ambiguity_without_exact_match_returns_display_only() {
        let input = CodexDashboardAuthorityInput(
            sourceKind: .liveWeb,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .providerAccount(id: "acct-current"),
                expectedScopedEmail: "shared@example.com",
                trustedCurrentUsageEmail: nil,
                dashboardSignedInEmail: "shared@example.com",
                knownOwners: [
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-alpha"),
                        normalizedEmail: "shared@example.com"),
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-beta"),
                        normalizedEmail: "shared@example.com"),
                ]),
            routing: CodexDashboardRoutingHints(
                targetEmail: "shared@example.com",
                lastKnownDashboardRoutingEmail: nil))

        let decision = CodexDashboardAuthority.evaluate(input)

        #expect(decision.disposition == .displayOnly)
        #expect(decision.reason == .sameEmailAmbiguity(email: "shared@example.com"))
    }

    @Test
    func provider_account_nil_scoped_email_with_dashboard_collision_returns_fail_closed() {
        let input = CodexDashboardAuthorityInput(
            sourceKind: .liveWeb,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .providerAccount(id: "acct-current"),
                expectedScopedEmail: nil,
                trustedCurrentUsageEmail: "shared@example.com",
                dashboardSignedInEmail: "shared@example.com",
                knownOwners: [
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-alpha"),
                        normalizedEmail: "shared@example.com"),
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-beta"),
                        normalizedEmail: "shared@example.com"),
                ]),
            routing: CodexDashboardRoutingHints(
                targetEmail: "shared@example.com",
                lastKnownDashboardRoutingEmail: nil))

        let decision = CodexDashboardAuthority.evaluate(input)

        #expect(decision.disposition == .failClosed)
        #expect(decision.reason == .providerAccountMissingScopedEmail)
    }

    @Test
    func unresolved_trusted_continuity_without_competing_owner_returns_attach() {
        let input = CodexDashboardAuthorityInput(
            sourceKind: .liveWeb,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .unresolved,
                expectedScopedEmail: nil,
                trustedCurrentUsageEmail: "owner@example.com",
                dashboardSignedInEmail: "owner@example.com",
                knownOwners: [
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-owner"),
                        normalizedEmail: "owner@example.com"),
                ]),
            routing: CodexDashboardRoutingHints(
                targetEmail: "owner@example.com",
                lastKnownDashboardRoutingEmail: "route@example.com"))

        let decision = CodexDashboardAuthority.evaluate(input)

        #expect(decision.disposition == .attach)
        #expect(decision.reason == .trustedContinuityNoCompetingOwner)
    }

    @Test
    func unresolved_trusted_continuity_with_competing_owner_returns_display_only() {
        let input = CodexDashboardAuthorityInput(
            sourceKind: .liveWeb,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .unresolved,
                expectedScopedEmail: nil,
                trustedCurrentUsageEmail: "shared@example.com",
                dashboardSignedInEmail: "shared@example.com",
                knownOwners: [
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-alpha"),
                        normalizedEmail: "shared@example.com"),
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-beta"),
                        normalizedEmail: "shared@example.com"),
                ]),
            routing: CodexDashboardRoutingHints(
                targetEmail: "shared@example.com",
                lastKnownDashboardRoutingEmail: "route@example.com"))

        let decision = CodexDashboardAuthority.evaluate(input)

        #expect(decision.disposition == .displayOnly)
        #expect(decision.reason == .sameEmailAmbiguity(email: "shared@example.com"))
    }

    @Test
    func unresolved_without_trusted_evidence_returns_fail_closed() {
        let input = CodexDashboardAuthorityInput(
            sourceKind: .liveWeb,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .unresolved,
                expectedScopedEmail: nil,
                trustedCurrentUsageEmail: nil,
                dashboardSignedInEmail: "owner@example.com",
                knownOwners: []),
            routing: CodexDashboardRoutingHints(
                targetEmail: "owner@example.com",
                lastKnownDashboardRoutingEmail: nil))

        let decision = CodexDashboardAuthority.evaluate(input)

        #expect(decision.disposition == .failClosed)
        #expect(decision.reason == .unresolvedWithoutTrustedEvidence)
    }

    @Test
    func missing_dashboard_signed_in_email_returns_fail_closed() {
        let input = CodexDashboardAuthorityInput(
            sourceKind: .liveWeb,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .providerAccount(id: "acct-owner"),
                expectedScopedEmail: "owner@example.com",
                trustedCurrentUsageEmail: "owner@example.com",
                dashboardSignedInEmail: nil,
                knownOwners: [
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-owner"),
                        normalizedEmail: "owner@example.com"),
                ]),
            routing: CodexDashboardRoutingHints(
                targetEmail: "owner@example.com",
                lastKnownDashboardRoutingEmail: nil))

        let decision = CodexDashboardAuthority.evaluate(input)

        #expect(decision.disposition == .failClosed)
        #expect(decision.reason == .missingDashboardSignedInEmail)
    }

    @Test
    func live_web_attach_exposes_usage_credits_guard_and_history_effects() {
        let input = CodexDashboardAuthorityInput(
            sourceKind: .liveWeb,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .providerAccount(id: "acct-owner"),
                expectedScopedEmail: "owner@example.com",
                trustedCurrentUsageEmail: nil,
                dashboardSignedInEmail: "owner@example.com",
                knownOwners: [
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-owner"),
                        normalizedEmail: "owner@example.com"),
                ]),
            routing: CodexDashboardRoutingHints(
                targetEmail: nil,
                lastKnownDashboardRoutingEmail: nil))

        let decision = CodexDashboardAuthority.evaluate(input)

        #expect(decision.disposition == .attach)
        #expect(decision.allowedEffects == Set([
            .usageBackfill,
            .creditsAttachment,
            .refreshGuardSeed,
            .historicalBackfill,
        ]))
        #expect(decision.cleanup.isEmpty)
    }

    @Test
    func cached_dashboard_attach_exposes_cached_reuse_only() {
        let input = CodexDashboardAuthorityInput(
            sourceKind: .cachedDashboard,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .emailOnly(normalizedEmail: "owner@example.com"),
                expectedScopedEmail: nil,
                trustedCurrentUsageEmail: nil,
                dashboardSignedInEmail: "owner@example.com",
                knownOwners: [
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-owner"),
                        normalizedEmail: "owner@example.com"),
                ]),
            routing: CodexDashboardRoutingHints(
                targetEmail: "owner@example.com",
                lastKnownDashboardRoutingEmail: nil))

        let decision = CodexDashboardAuthority.evaluate(input)

        #expect(decision.disposition == .attach)
        #expect(decision.allowedEffects == Set([.cachedDashboardReuse]))
        #expect(decision.cleanup.isEmpty)
    }

    @Test
    func display_only_emits_full_cleanup_set() {
        let input = CodexDashboardAuthorityInput(
            sourceKind: .liveWeb,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .emailOnly(normalizedEmail: "shared@example.com"),
                expectedScopedEmail: nil,
                trustedCurrentUsageEmail: nil,
                dashboardSignedInEmail: "shared@example.com",
                knownOwners: [
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-alpha"),
                        normalizedEmail: "shared@example.com"),
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct-beta"),
                        normalizedEmail: "shared@example.com"),
                ]),
            routing: CodexDashboardRoutingHints(
                targetEmail: nil,
                lastKnownDashboardRoutingEmail: nil))

        let decision = CodexDashboardAuthority.evaluate(input)

        #expect(decision.disposition == .displayOnly)
        #expect(decision.allowedEffects.isEmpty)
        #expect(decision.cleanup == Set(CodexDashboardCleanup.allCases))
    }

    @Test
    func fail_closed_emits_full_cleanup_set() {
        let input = CodexDashboardAuthorityInput(
            sourceKind: .liveWeb,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .unresolved,
                expectedScopedEmail: nil,
                trustedCurrentUsageEmail: nil,
                dashboardSignedInEmail: "owner@example.com",
                knownOwners: []),
            routing: CodexDashboardRoutingHints(
                targetEmail: nil,
                lastKnownDashboardRoutingEmail: nil))

        let decision = CodexDashboardAuthority.evaluate(input)

        #expect(decision.disposition == .failClosed)
        #expect(decision.allowedEffects.isEmpty)
        #expect(decision.cleanup == Set(CodexDashboardCleanup.allCases))
    }

    @Test
    func routing_hints_do_not_change_evaluation_result() {
        let proof = CodexDashboardOwnershipProofContext(
            currentIdentity: .providerAccount(id: "acct-owner"),
            expectedScopedEmail: "owner@example.com",
            trustedCurrentUsageEmail: nil,
            dashboardSignedInEmail: "owner@example.com",
            knownOwners: [
                CodexDashboardKnownOwnerCandidate(
                    identity: .providerAccount(id: "acct-owner"),
                    normalizedEmail: "owner@example.com"),
            ])
        let baseInput = CodexDashboardAuthorityInput(
            sourceKind: .liveWeb,
            proof: proof,
            routing: CodexDashboardRoutingHints(
                targetEmail: "owner@example.com",
                lastKnownDashboardRoutingEmail: "owner@example.com"))
        let conflictingRoutingInput = CodexDashboardAuthorityInput(
            sourceKind: .liveWeb,
            proof: proof,
            routing: CodexDashboardRoutingHints(
                targetEmail: "wrong@example.com",
                lastKnownDashboardRoutingEmail: "stale@example.com"))

        let baseDecision = CodexDashboardAuthority.evaluate(baseInput)
        let conflictingDecision = CodexDashboardAuthority.evaluate(conflictingRoutingInput)

        #expect(baseDecision == conflictingDecision)
    }
}
