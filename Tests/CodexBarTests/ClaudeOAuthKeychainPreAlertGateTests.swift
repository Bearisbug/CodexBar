import Foundation
import Testing
@testable import CodexBarCore

#if os(macOS)
@Suite(.serialized)
struct ClaudeOAuthKeychainPreAlertGateTests {
    @Test
    func acknowledgement_suppresses_repeated_presentation_until_cooldown_expires() {
        let store = ClaudeOAuthKeychainPreAlertGate.StateStore()
        ClaudeOAuthKeychainPreAlertGate.withStateStoreOverrideForTesting(store) {
            let now = Date(timeIntervalSince1970: 1000)
            #expect(ClaudeOAuthKeychainPreAlertGate.presentIfNeeded(now: now, completedAt: now) { true })

            #expect(
                ClaudeOAuthKeychainPreAlertGate.presentIfNeeded(
                    now: now.addingTimeInterval(ClaudeOAuthKeychainPreAlertGate.cooldownInterval - 1),
                    completedAt: now,
                    present: { true }) == false)
            #expect(
                ClaudeOAuthKeychainPreAlertGate.presentIfNeeded(
                    now: now.addingTimeInterval(ClaudeOAuthKeychainPreAlertGate.cooldownInterval + 1),
                    completedAt: now,
                    present: { true }))
        }
    }

    @Test
    func cooldown_starts_when_presentation_completes() {
        let store = ClaudeOAuthKeychainPreAlertGate.StateStore()
        ClaudeOAuthKeychainPreAlertGate.withStateStoreOverrideForTesting(store) {
            let startedAt = Date(timeIntervalSince1970: 1000)
            let completedAt = Date(timeIntervalSince1970: 2000)
            #expect(ClaudeOAuthKeychainPreAlertGate.presentIfNeeded(
                now: startedAt,
                completedAt: completedAt,
                present: { true }))

            #expect(ClaudeOAuthKeychainPreAlertGate.presentIfNeeded(
                now: startedAt.addingTimeInterval(ClaudeOAuthKeychainPreAlertGate.cooldownInterval + 1),
                completedAt: completedAt,
                present: { true }) == false)
            #expect(ClaudeOAuthKeychainPreAlertGate.presentIfNeeded(
                now: completedAt.addingTimeInterval(ClaudeOAuthKeychainPreAlertGate.cooldownInterval + 1),
                completedAt: completedAt,
                present: { true }))
        }
    }

    @Test
    func missing_prompt_handler_does_not_consume_acknowledgement_cooldown() {
        let store = ClaudeOAuthKeychainPreAlertGate.StateStore()
        ClaudeOAuthKeychainPreAlertGate.withStateStoreOverrideForTesting(store) {
            let now = Date(timeIntervalSince1970: 2000)
            #expect(ClaudeOAuthKeychainPreAlertGate.presentIfNeeded(now: now, completedAt: now) { false } == false)
            #expect(ClaudeOAuthKeychainPreAlertGate.presentIfNeeded(now: now, completedAt: now) { true })
        }
    }

    @Test
    func duplicate_while_presentation_is_in_flight_is_suppressed() {
        let store = ClaudeOAuthKeychainPreAlertGate.StateStore()
        ClaudeOAuthKeychainPreAlertGate.withStateStoreOverrideForTesting(store) {
            let now = Date(timeIntervalSince1970: 3000)
            var nestedPresentationRan = false
            var nestedResult: Bool?
            let outerResult = ClaudeOAuthKeychainPreAlertGate.presentIfNeeded(now: now, completedAt: now) {
                nestedResult = ClaudeOAuthKeychainPreAlertGate.presentIfNeeded(now: now) {
                    nestedPresentationRan = true
                    return true
                }
                return true
            }
            #expect(outerResult)
            #expect(nestedResult == false)
            #expect(nestedPresentationRan == false)
        }
    }

    @Test
    func acknowledgement_persists_across_in_memory_reset() {
        ClaudeOAuthKeychainPreAlertGate.resetForTesting()
        defer { ClaudeOAuthKeychainPreAlertGate.resetForTesting() }

        let now = Date(timeIntervalSince1970: 4000)
        #expect(ClaudeOAuthKeychainPreAlertGate.presentIfNeeded(now: now, completedAt: now) { true })
        ClaudeOAuthKeychainPreAlertGate.resetInMemoryForTesting()

        #expect(
            ClaudeOAuthKeychainPreAlertGate.presentIfNeeded(
                now: now.addingTimeInterval(ClaudeOAuthKeychainPreAlertGate.cooldownInterval - 1),
                completedAt: now,
                present: { true }) == false)
    }
}
#endif
