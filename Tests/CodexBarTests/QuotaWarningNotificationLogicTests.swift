import Testing
@testable import CodexBar

@Suite(.serialized)
struct QuotaWarningNotificationLogicTests {
    @Test
    func quota_warning_copy_includes_current_remaining_and_threshold() {
        Self.withAppLanguage("en") {
            let copy = QuotaWarningNotificationLogic.notificationCopy(
                providerName: "Codex",
                window: .session,
                threshold: 20,
                currentRemaining: 12.4)

            #expect(copy.title == "Codex session quota low")
            #expect(copy.body == "12% left. Reached your 20% session warning threshold.")
        }
    }

    @Test
    func quota_warning_copy_clamps_current_remaining() {
        Self.withAppLanguage("en") {
            let copy = QuotaWarningNotificationLogic.notificationCopy(
                providerName: "Codex",
                window: .weekly,
                threshold: 50,
                currentRemaining: -3)

            #expect(copy.title == "Codex weekly quota low")
            #expect(copy.body == "0% left. Reached your 50% weekly warning threshold.")
        }
    }

    @Test
    func quota_warning_copy_includes_account_when_provided() {
        Self.withAppLanguage("en") {
            let copy = QuotaWarningNotificationLogic.notificationCopy(
                providerName: "Codex",
                window: .session,
                threshold: 50,
                currentRemaining: 45,
                accountDisplayName: "person@example.com")

            #expect(copy.title == "Codex session quota low")
            #expect(copy.body == "Account person@example.com. 45% left. Reached your 50% session warning threshold.")
        }
    }

    @Test
    func quota_warning_copy_uses_the_extra_window_display_label_when_provided() {
        Self.withAppLanguage("en") {
            let copy = QuotaWarningNotificationLogic.notificationCopy(
                providerName: "Claude",
                window: .weekly,
                threshold: 50,
                currentRemaining: 45,
                windowDisplayLabel: "Fable only")

            #expect(copy.title == "Claude Fable only quota low")
            #expect(copy.body == "45% left. Reached your 50% Fable only warning threshold.")
        }
    }

    @Test
    func extra_window_notification_identifiers_are_independent() {
        let fable = QuotaWarningEvent(
            window: .weekly,
            threshold: 50,
            currentRemaining: 45,
            windowID: "claude-weekly-scoped-fable")
        let routines = QuotaWarningEvent(
            window: .weekly,
            threshold: 50,
            currentRemaining: 45,
            windowID: "claude-routines")

        let ids = [fable, routines].map {
            QuotaWarningNotificationLogic.notificationIDPrefix(provider: .claude, event: $0)
        }
        #expect(Set(ids).count == 2)
        #expect(ids[0].contains("claude-weekly-scoped-fable"))
        #expect(ids[1].contains("claude-routines"))
    }

    @Test
    func quota_warning_copy_follows_Traditional_Chinese_app_language() {
        Self.withAppLanguage("zh-Hant") {
            let copy = QuotaWarningNotificationLogic.notificationCopy(
                providerName: "Codex",
                window: .session,
                threshold: 50,
                currentRemaining: 45,
                accountDisplayName: "person@example.com")

            #expect(copy.title == "Codex 工作階段配額偏低")
            #expect(copy.body == "帳號 person@example.com。剩餘 45%。已達到 50% 工作階段提醒門檻。")
        }
    }

    @Test
    func does_nothing_without_crossing() {
        let crossed = QuotaWarningNotificationLogic.crossedThreshold(
            previousRemaining: 60,
            currentRemaining: 55,
            thresholds: [50, 20],
            alreadyFired: [])

        #expect(crossed == nil)
    }

    @Test
    func detects_downward_crossing() {
        let crossed = QuotaWarningNotificationLogic.crossedThreshold(
            previousRemaining: 55,
            currentRemaining: 45,
            thresholds: [50, 20],
            alreadyFired: [])

        #expect(crossed == 50)
    }

    @Test
    func skips_already_fired_thresholds() {
        let crossed = QuotaWarningNotificationLogic.crossedThreshold(
            previousRemaining: 55,
            currentRemaining: 45,
            thresholds: [50, 20],
            alreadyFired: [50])

        #expect(crossed == nil)
    }

    @Test
    func chooses_most_severe_threshold_when_crossing_several_at_once() {
        let crossed = QuotaWarningNotificationLogic.crossedThreshold(
            previousRemaining: 80,
            currentRemaining: 10,
            thresholds: [50, 20],
            alreadyFired: [])

        #expect(crossed == 20)
    }

    @Test
    func startup_below_threshold_warns_once_at_most_severe_threshold() {
        let crossed = QuotaWarningNotificationLogic.crossedThreshold(
            previousRemaining: nil,
            currentRemaining: 10,
            thresholds: [50, 20],
            alreadyFired: [])

        #expect(crossed == 20)
    }

    @Test
    func warning_marks_threshold_and_higher_thresholds_fired() {
        let fired = QuotaWarningNotificationLogic.firedThresholdsAfterWarning(
            threshold: 20,
            thresholds: [50, 20])

        #expect(fired == [50, 20])
    }

    @Test
    func recovery_clears_only_thresholds_below_current_remaining() {
        let cleared = QuotaWarningNotificationLogic.thresholdsToClear(
            currentRemaining: 30,
            alreadyFired: [50, 20])

        #expect(cleared == [20])
    }

    @Test
    func zero_threshold_does_not_post_quota_warning() {
        let crossed = QuotaWarningNotificationLogic.crossedThreshold(
            previousRemaining: 10,
            currentRemaining: 0,
            thresholds: [10, 0],
            alreadyFired: [10])

        #expect(crossed == nil)
        #expect(QuotaWarningNotificationLogic.firedThresholdsAfterWarning(threshold: 10, thresholds: [10, 0]) == [10])
    }

    private static func withAppLanguage(_ language: String, perform body: () -> Void) {
        CodexBarLocalizationOverride.$appLanguage.withValue(language, operation: body)
    }
}
