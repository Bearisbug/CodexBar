import CodexBarCore
import Testing

struct ClaudeCredentialRoutingTests {
    @Test
    func resolves_raw_OAuth_token() {
        let routing = ClaudeCredentialRouting.resolve(
            tokenAccountToken: "sk-ant-oat-test-token",
            manualCookieHeader: nil)

        #expect(routing == .oauth(accessToken: "sk-ant-oat-test-token"))
    }

    @Test
    func resolves_bearer_OAuth_token() {
        let routing = ClaudeCredentialRouting.resolve(
            tokenAccountToken: "Bearer sk-ant-oat-test-token",
            manualCookieHeader: nil)

        #expect(routing == .oauth(accessToken: "sk-ant-oat-test-token"))
    }

    @Test
    func resolves_session_token_to_cookie_header() {
        let routing = ClaudeCredentialRouting.resolve(
            tokenAccountToken: "sk-ant-session-token",
            manualCookieHeader: nil)

        #expect(routing == .webCookie(header: "sessionKey=sk-ant-session-token"))
    }

    @Test
    func resolves_config_cookie_header_through_shared_normalizer() {
        let routing = ClaudeCredentialRouting.resolve(
            tokenAccountToken: nil,
            manualCookieHeader: "Cookie: sessionKey=sk-ant-session-token; foo=bar")

        #expect(routing == .webCookie(header: "sessionKey=sk-ant-session-token; foo=bar"))
    }

    @Test
    func token_account_input_wins_over_config_cookie_fallback() {
        let routing = ClaudeCredentialRouting.resolve(
            tokenAccountToken: "Bearer sk-ant-oat-test-token",
            manualCookieHeader: "Cookie: sessionKey=sk-ant-session-token")

        #expect(routing == .oauth(accessToken: "sk-ant-oat-test-token"))
    }

    @Test
    func empty_inputs_resolve_to_none() {
        let routing = ClaudeCredentialRouting.resolve(
            tokenAccountToken: "   ",
            manualCookieHeader: "\n")

        #expect(routing == .none)
    }
}
