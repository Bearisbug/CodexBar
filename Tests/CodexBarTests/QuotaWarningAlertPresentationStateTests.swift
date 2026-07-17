import Testing
@testable import CodexBar

struct QuotaWarningAlertPresentationStateTests {
    @Test
    func replacement_alert_ignores_stale_dismissal() {
        var state = QuotaWarningAlertPresentationState()
        let session = state.present(title: "Session quota low", message: "20% left")
        let weekly = state.present(title: "Weekly quota low", message: "10% left")

        #expect(state.dismiss(generation: session.generation) == false)
        #expect(state.current == weekly)
        #expect(state.dismiss(generation: weekly.generation) == true)
        #expect(state.current == nil)
    }

    @Test
    func manual_dismissal_clears_current_alert() {
        var state = QuotaWarningAlertPresentationState()
        let presentation = state.present(title: "Session quota low", message: "20% left")
        #expect(state.current == presentation)

        state.dismiss()

        #expect(state.current == nil)
    }
}
