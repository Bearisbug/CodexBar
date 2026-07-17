import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct AntigravityLoginAlertTests {
    @Test
    func authorization_URL_asks_Google_to_select_an_account() throws {
        let redirectURL = try #require(URL(string: "http://127.0.0.1:54321/callback"))
        let url = try AntigravityLoginRunner.makeAuthorizationURL(
            redirectURL: redirectURL,
            state: "state",
            oauthClient: AntigravityOAuthClient(
                clientID: "client.apps.googleusercontent.com",
                clientSecret: "secret"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let prompt = components.queryItems?.first(where: { $0.name == "prompt" })?.value

        #expect(prompt?.split(separator: " ").contains("select_account") == true)
        #expect(prompt?.split(separator: " ").contains("consent") == true)
    }

    @Test
    func returns_alert_for_timeout() {
        let result = AntigravityLoginRunner.Result(outcome: .timedOut)
        let info = StatusItemController.antigravityLoginAlertInfo(for: result)
        #expect(info?.title == "Antigravity login timed out")
    }

    @Test
    func returns_alert_for_launch_failure() {
        let result = AntigravityLoginRunner.Result(outcome: .launchFailed("https://example.com/login"))
        let info = StatusItemController.antigravityLoginAlertInfo(for: result)
        #expect(info?.title == "Could not open browser for Antigravity")
        #expect(info?.message.contains("https://example.com/login") == true)
    }

    @Test
    func returns_alert_for_auth_failure() {
        let result = AntigravityLoginRunner.Result(outcome: .failed("permission denied"))
        let info = StatusItemController.antigravityLoginAlertInfo(for: result)
        #expect(info?.title == "Antigravity login failed")
        #expect(info?.message == "permission denied")
    }

    @Test
    func returns_nil_on_success() {
        let result = AntigravityLoginRunner.Result(outcome: .success("user@example.com"))
        let info = StatusItemController.antigravityLoginAlertInfo(for: result)
        #expect(info == nil)
    }
}
