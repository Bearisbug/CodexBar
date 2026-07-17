import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
struct SessionQuotaNotificationLogicTests {
    @Test
    func does_nothing_without_previous_value() {
        let transition = SessionQuotaNotificationLogic.transition(previousRemaining: nil, currentRemaining: 0)
        #expect(transition == .none)
    }

    @Test
    func detects_depleted_transition() {
        let transition = SessionQuotaNotificationLogic.transition(previousRemaining: 12, currentRemaining: 0)
        #expect(transition == .depleted)
    }

    @Test
    func detects_restored_transition() {
        let transition = SessionQuotaNotificationLogic.transition(previousRemaining: 0, currentRemaining: 5)
        #expect(transition == .restored)
    }

    @Test
    func ignores_non_transitions() {
        #expect(SessionQuotaNotificationLogic.transition(previousRemaining: 0, currentRemaining: 0) == .none)
        #expect(SessionQuotaNotificationLogic.transition(previousRemaining: 10, currentRemaining: 10) == .none)
        #expect(SessionQuotaNotificationLogic.transition(previousRemaining: 10, currentRemaining: 9) == .none)
    }

    @Test
    func treats_tiny_positive_remaining_as_depleted() {
        let transition = SessionQuotaNotificationLogic.transition(previousRemaining: 0, currentRemaining: 0.00001)
        #expect(transition == .none)
    }

    @Test
    func depleted_notification_copy_follows_Traditional_Chinese_app_language() {
        Self.withAppLanguage("zh-Hant") {
            let copy = SessionQuotaNotificationLogic.notificationCopy(
                transition: .depleted,
                providerName: "Codex")

            #expect(copy.title == "Codex 工作階段已用完")
            #expect(copy.body == "剩餘 0%。恢復可用時會再通知。")
        }
    }

    @Test
    func restored_notification_copy_follows_Traditional_Chinese_app_language() {
        Self.withAppLanguage("zh-Hant") {
            let copy = SessionQuotaNotificationLogic.notificationCopy(
                transition: .restored,
                providerName: "Codex")

            #expect(copy.title == "Codex 工作階段已恢復")
            #expect(copy.body == "工作階段配額已恢復可用。")
        }
    }

    private static func withAppLanguage(_ language: String, perform body: () -> Void) {
        CodexBarLocalizationOverride.$appLanguage.withValue(language, operation: body)
    }
}
