import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CookieHeaderCacheConditionalMutationTests {
    #if os(macOS)
    @Test
    func temporary_keychain_read_permits_fresh_replacement_when_legacy_state_is_unchanged() {
        self.withIsolatedCookieCache {
            let legacy = CookieHeaderCache.Entry(
                cookieHeader: "sessionKey=sk-ant-legacy",
                storedAt: Date(timeIntervalSince1970: 1),
                sourceLabel: "Legacy")
            CookieHeaderCache.store(legacy, to: CookieHeaderCache.legacyURLForTesting(provider: .claude))

            let observation = KeychainCacheStore.withLoadFailureStatusOverrideForTesting(errSecInteractionNotAllowed) {
                CookieHeaderCache.observeForConditionalMutation(provider: .claude)
            }
            let replaced = CookieHeaderCache.storeIfObservationCurrent(
                provider: .claude,
                expected: observation,
                cookieHeader: "sessionKey=sk-ant-fresh",
                sourceLabel: "Safari")

            #expect(observation.entry == nil)
            #expect(replaced)
            #expect(CookieHeaderCache.load(provider: .claude)?.cookieHeader == "sessionKey=sk-ant-fresh")
            #expect(!CookieHeaderCache.hasLegacyEntryForTesting(provider: .claude))
        }
    }

    @Test
    func temporary_keychain_read_does_not_overwrite_a_concurrent_keychain_entry() {
        self.withIsolatedCookieCache {
            let observation = KeychainCacheStore.withLoadFailureStatusOverrideForTesting(errSecInteractionNotAllowed) {
                CookieHeaderCache.observeForConditionalMutation(provider: .claude)
            }
            CookieHeaderCache.store(
                provider: .claude,
                cookieHeader: "sessionKey=sk-ant-concurrent",
                sourceLabel: "Chrome")

            let replaced = CookieHeaderCache.storeIfObservationCurrent(
                provider: .claude,
                expected: observation,
                cookieHeader: "sessionKey=sk-ant-fresh",
                sourceLabel: "Safari")

            #expect(!replaced)
            #expect(CookieHeaderCache.load(provider: .claude)?.cookieHeader == "sessionKey=sk-ant-concurrent")
        }
    }

    @Test
    func observable_store_failure_preserves_the_current_cookie_entry() {
        self.withIsolatedCookieCache {
            let initiallyStored = CookieHeaderCache.storeResult(
                provider: .cursor,
                cookieHeader: "WorkosCursorSessionToken=existing",
                sourceLabel: "Chrome")

            let replaced = KeychainCacheStore.withStoreFailureStatusOverrideForTesting(errSecInteractionNotAllowed) {
                CookieHeaderCache.storeResult(
                    provider: .cursor,
                    cookieHeader: "WorkosCursorSessionToken=replacement",
                    sourceLabel: "Comet")
            }

            #expect(initiallyStored)
            #expect(!replaced)
            #expect(CookieHeaderCache.load(provider: .cursor)?.cookieHeader ==
                "WorkosCursorSessionToken=existing")
        }
    }
    #endif

    @Test
    func legacy_clear_failure_still_permits_replacing_the_keychain_entry() {
        self.withIsolatedCookieCache {
            CookieHeaderCache.store(
                provider: .claude,
                cookieHeader: "sessionKey=sk-ant-stale",
                sourceLabel: "Chrome")
            let stale = CookieHeaderCache.load(provider: .claude)
            #expect(stale != nil)
            guard let stale else { return }

            CookieHeaderCache.store(
                CookieHeaderCache.Entry(
                    cookieHeader: "sessionKey=sk-ant-legacy",
                    storedAt: Date(timeIntervalSince1970: 1),
                    sourceLabel: "Legacy"),
                to: CookieHeaderCache.legacyURLForTesting(provider: .claude))

            let cleared = CookieHeaderCache.withLegacyRemovalFailureForTesting {
                CookieHeaderCache.clearIfCurrent(provider: .claude, expected: stale)
            }
            let replaced = CookieHeaderCache.storeIfCurrent(
                provider: .claude,
                expected: stale,
                cookieHeader: "sessionKey=sk-ant-fresh",
                sourceLabel: "Safari")

            #expect(!cleared)
            #expect(replaced)
            #expect(CookieHeaderCache.load(provider: .claude)?.cookieHeader == "sessionKey=sk-ant-fresh")
            #expect(!CookieHeaderCache.hasLegacyEntryForTesting(provider: .claude))
        }
    }

    @Test
    func interactive_mutation_gate_invalidates_an_earlier_background_observation() {
        self.withIsolatedCookieCache {
            let scope = CookieHeaderCache.Scope.providerVariant(UUID().uuidString)
            CookieHeaderCache.store(
                provider: .cursor,
                scope: scope,
                cookieHeader: "fixtureSession=original",
                sourceLabel: "Original")
            let observation = CookieHeaderCache.observeForConditionalMutation(provider: .cursor, scope: scope)
            let gate = CookieHeaderCache.beginConditionalMutationGate(provider: .cursor, scope: scope)

            #expect(!CookieHeaderCache.storeIfObservationCurrent(
                provider: .cursor,
                scope: scope,
                expected: observation,
                cookieHeader: "fixtureSession=background-during-login",
                sourceLabel: "Background"))
            #expect(CookieHeaderCache.storeResult(
                provider: .cursor,
                scope: scope,
                cookieHeader: "fixtureSession=selected",
                sourceLabel: "Interactive login"))
            CookieHeaderCache.endConditionalMutationGate(gate)

            #expect(!CookieHeaderCache.storeIfObservationCurrent(
                provider: .cursor,
                scope: scope,
                expected: observation,
                cookieHeader: "fixtureSession=background-after-login",
                sourceLabel: "Background"))
            #expect(CookieHeaderCache.load(provider: .cursor, scope: scope)?.cookieHeader == "fixtureSession=selected")
        }
    }

    @Test
    func owned_clear_observation_accepts_fallback_but_preserves_gate_generation() {
        self.withIsolatedCookieCache {
            let scope = CookieHeaderCache.Scope.providerVariant(UUID().uuidString)
            CookieHeaderCache.store(
                provider: .cursor,
                scope: scope,
                cookieHeader: "fixtureSession=stale",
                sourceLabel: "Stale")
            let stale = CookieHeaderCache.load(provider: .cursor, scope: scope)
            let observation = CookieHeaderCache.observeForConditionalMutation(provider: .cursor, scope: scope)

            #expect(CookieHeaderCache.clearIfCurrent(provider: .cursor, scope: scope, expected: stale))
            let afterClear = observation.afterOwnedClear()
            #expect(CookieHeaderCache.storeIfObservationCurrent(
                provider: .cursor,
                scope: scope,
                expected: afterClear,
                cookieHeader: "fixtureSession=browser-fallback",
                sourceLabel: "Browser fallback"))

            let nextObservation = CookieHeaderCache.observeForConditionalMutation(provider: .cursor, scope: scope)
            let fallback = CookieHeaderCache.load(provider: .cursor, scope: scope)
            #expect(CookieHeaderCache.clearIfCurrent(provider: .cursor, scope: scope, expected: fallback))
            let gate = CookieHeaderCache.beginConditionalMutationGate(provider: .cursor, scope: scope)
            CookieHeaderCache.endConditionalMutationGate(gate)

            #expect(!CookieHeaderCache.storeIfObservationCurrent(
                provider: .cursor,
                scope: scope,
                expected: nextObservation.afterOwnedClear(),
                cookieHeader: "fixtureSession=late-background",
                sourceLabel: "Background"))
        }
    }

    @Test
    func observation_captured_during_cancelled_interactive_mutation_remains_stale() {
        self.withIsolatedCookieCache {
            let scope = CookieHeaderCache.Scope.providerVariant(UUID().uuidString)
            CookieHeaderCache.store(
                provider: .cursor,
                scope: scope,
                cookieHeader: "fixtureSession=original",
                sourceLabel: "Original")
            let gate = CookieHeaderCache.beginConditionalMutationGate(provider: .cursor, scope: scope)
            let observation = CookieHeaderCache.observeForConditionalMutation(provider: .cursor, scope: scope)

            #expect(!CookieHeaderCache.storeIfObservationCurrent(
                provider: .cursor,
                scope: scope,
                expected: observation,
                cookieHeader: "fixtureSession=background-during-login",
                sourceLabel: "Background"))
            CookieHeaderCache.endConditionalMutationGate(gate)

            #expect(!CookieHeaderCache.storeIfObservationCurrent(
                provider: .cursor,
                scope: scope,
                expected: observation,
                cookieHeader: "fixtureSession=background-after-cancel",
                sourceLabel: "Background"))
            #expect(CookieHeaderCache.load(provider: .cursor, scope: scope)?.cookieHeader == "fixtureSession=original")
        }
    }

    @Test
    func nested_interactive_mutation_gate_blocks_until_outer_flow_ends() {
        self.withIsolatedCookieCache {
            let scope = CookieHeaderCache.Scope.providerVariant(UUID().uuidString)
            CookieHeaderCache.store(
                provider: .cursor,
                scope: scope,
                cookieHeader: "fixtureSession=original",
                sourceLabel: "Original")
            let outerGate = CookieHeaderCache.beginConditionalMutationGate(provider: .cursor, scope: scope)
            let runnerGate = CookieHeaderCache.beginConditionalMutationGate(provider: .cursor, scope: scope)
            CookieHeaderCache.endConditionalMutationGate(runnerGate)

            let whileOuterGateIsActive = CookieHeaderCache.observeForConditionalMutation(
                provider: .cursor,
                scope: scope)
            #expect(!CookieHeaderCache.storeIfObservationCurrent(
                provider: .cursor,
                scope: scope,
                expected: whileOuterGateIsActive,
                cookieHeader: "fixtureSession=background",
                sourceLabel: "Background"))
            CookieHeaderCache.endConditionalMutationGate(outerGate)

            let afterOuterGateEnds = CookieHeaderCache.observeForConditionalMutation(provider: .cursor, scope: scope)
            #expect(CookieHeaderCache.storeIfObservationCurrent(
                provider: .cursor,
                scope: scope,
                expected: afterOuterGateEnds,
                cookieHeader: "fixtureSession=late-background",
                sourceLabel: "Background"))
            #expect(CookieHeaderCache.load(provider: .cursor, scope: scope)?.cookieHeader ==
                "fixtureSession=late-background")
        }
    }

    private func withIsolatedCookieCache<T>(_ operation: () -> T) -> T {
        KeychainCacheStore.withServiceOverrideForTesting("cookie-conditional-\(UUID().uuidString)") {
            let legacyBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            return CookieHeaderCache.withLegacyBaseURLOverrideForTesting(legacyBase) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }
                return operation()
            }
        }
    }
}
