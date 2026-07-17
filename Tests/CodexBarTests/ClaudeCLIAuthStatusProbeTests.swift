import Testing
@testable import CodexBarCore

struct ClaudeCLIAuthStatusProbeTests {
    @Test
    func parses_logged_in_status() {
        #expect(ClaudeCLIAuthStatusProbe.parseLoggedIn(#"{"loggedIn":true,"authMethod":"claude.ai"}"#))
    }

    @Test
    func rejects_logged_out_and_malformed_status() {
        #expect(!ClaudeCLIAuthStatusProbe.parseLoggedIn(#"{"loggedIn":false,"authMethod":"none"}"#))
        #expect(!ClaudeCLIAuthStatusProbe.parseLoggedIn("not-json"))
        #expect(!ClaudeCLIAuthStatusProbe.parseLoggedIn(#"{"authMethod":"none"}"#))
    }
}
