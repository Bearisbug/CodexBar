import Testing
@testable import CodexBar

struct GeminiLoginAlertTests {
    @Test
    func returns_alert_for_missing_binary() {
        let result = GeminiLoginRunner.Result(outcome: .missingBinary)
        let info = StatusItemController.geminiLoginAlertInfo(for: result)
        #expect(info?.title == "Gemini CLI not found")
        #expect(info?.message == "Install the Gemini CLI (npm i -g @google/gemini-cli) and try again.")
    }

    @Test
    func returns_alert_for_launch_failure() {
        let result = GeminiLoginRunner.Result(outcome: .launchFailed("Boom"))
        let info = StatusItemController.geminiLoginAlertInfo(for: result)
        #expect(info?.title == "Could not open Terminal for Gemini")
        #expect(info?.message == "Boom")
    }

    @Test
    func returns_nil_on_success() {
        let result = GeminiLoginRunner.Result(outcome: .success)
        let info = StatusItemController.geminiLoginAlertInfo(for: result)
        #expect(info == nil)
    }
}
