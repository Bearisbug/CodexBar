import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct CodexHistoryOwnershipTests {
    private let normalizedEmail = "user@example.com"
    private let legacyEmailHash = "b4c9a289323b21a01c3e940f150eb9b8c542587f1abfd8f0e1cc1ffc5e475514"

    @Test
    func serializes_canonical_provider_account_key() {
        let key = CodexHistoryOwnership.canonicalKey(for: .providerAccount(id: "acct-123"))

        #expect(key == "codex:v1:provider-account:acct-123")
    }

    @Test
    func serializes_canonical_email_hash_key() {
        let key = CodexHistoryOwnership.canonicalKey(for: .emailOnly(normalizedEmail: self.normalizedEmail))

        #expect(key == "codex:v1:email-hash:\(self.legacyEmailHash)")
    }

    @Test
    func unresolved_identity_has_no_canonical_key() {
        let key = CodexHistoryOwnership.canonicalKey(for: .unresolved)

        #expect(key == nil)
    }

    @Test
    func classifies_canonical_and_legacy_persisted_keys() {
        let canonical = "codex:v1:provider-account:acct-123"
        let legacy = CodexHistoryOwnership.classifyPersistedKey(
            self.legacyEmailHash,
            legacyEmailHash: self.legacyEmailHash)
        let opaque = CodexHistoryOwnership.classifyPersistedKey(
            "92a40b0d62f5f4f1b3dbd3f9ecb6c7700dd540d2d866e59d1c110f6b4d7f1abc",
            legacyEmailHash: self.legacyEmailHash)

        #expect(CodexHistoryOwnership.classifyPersistedKey(nil) == .legacyUnscoped)
        #expect(CodexHistoryOwnership.classifyPersistedKey("") == .legacyUnscoped)
        #expect(CodexHistoryOwnership.classifyPersistedKey(canonical) == .canonical(canonical))
        #expect(legacy == .legacyEmailHash(self.legacyEmailHash))
        #expect(opaque == .legacyOpaqueScoped("92a40b0d62f5f4f1b3dbd3f9ecb6c7700dd540d2d866e59d1c110f6b4d7f1abc"))
    }

    @Test
    func strict_continuity_passes_for_a_single_aliased_email_hash_owner() {
        let canonicalEmailHashKey = "codex:v1:email-hash:\(self.legacyEmailHash)"

        let result = CodexHistoryOwnership.hasStrictSingleAccountContinuity(
            scopedRawKeys: [self.legacyEmailHash],
            targetCanonicalKey: canonicalEmailHashKey,
            canonicalEmailHashKey: canonicalEmailHashKey,
            legacyEmailHash: self.legacyEmailHash,
            hasAdjacentMultiAccountVeto: false)

        #expect(result)
    }

    @Test
    func strict_continuity_fails_with_ambiguous_owners() {
        let canonicalEmailHashKey = "codex:v1:email-hash:\(self.legacyEmailHash)"

        let result = CodexHistoryOwnership.hasStrictSingleAccountContinuity(
            scopedRawKeys: [
                canonicalEmailHashKey,
                "codex:v1:provider-account:acct-123",
            ],
            targetCanonicalKey: canonicalEmailHashKey,
            canonicalEmailHashKey: canonicalEmailHashKey,
            legacyEmailHash: self.legacyEmailHash,
            hasAdjacentMultiAccountVeto: false)

        #expect(!result)
    }

    @Test
    func strict_continuity_fails_when_adjacent_persisted_evidence_vetoes_migration() {
        let canonicalEmailHashKey = "codex:v1:email-hash:\(self.legacyEmailHash)"

        let result = CodexHistoryOwnership.hasStrictSingleAccountContinuity(
            scopedRawKeys: [canonicalEmailHashKey],
            targetCanonicalKey: canonicalEmailHashKey,
            canonicalEmailHashKey: canonicalEmailHashKey,
            legacyEmailHash: self.legacyEmailHash,
            hasAdjacentMultiAccountVeto: true)

        #expect(!result)
    }

    @Test
    func provider_account_target_inherits_email_continuity() {
        let providerAccountKey = "codex:v1:provider-account:acct-123"
        let canonicalEmailHashKey = "codex:v1:email-hash:\(self.legacyEmailHash)"

        let legacyMatchesProvider = CodexHistoryOwnership.belongsToTargetContinuity(
            .legacyEmailHash(self.legacyEmailHash),
            targetCanonicalKey: providerAccountKey,
            canonicalEmailHashKey: canonicalEmailHashKey)
        let canonicalMatchesProvider = CodexHistoryOwnership.belongsToTargetContinuity(
            .canonical(canonicalEmailHashKey),
            targetCanonicalKey: providerAccountKey,
            canonicalEmailHashKey: canonicalEmailHashKey)

        #expect(legacyMatchesProvider)
        #expect(canonicalMatchesProvider)
    }
}
