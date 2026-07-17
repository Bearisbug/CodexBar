import Foundation
import Testing
@testable import CodexBarCore

struct ManusCookieHeaderTests {
    @Test
    func bare_token_resolves_directly() {
        #expect(ManusCookieHeader.token(from: "abc123") == "abc123")
    }

    @Test
    func extracts_session_id_from_cookie_header() {
        let header = "foo=bar; session_id=token-a; baz=qux"
        #expect(ManusCookieHeader.token(from: header) == "token-a")
    }

    @Test
    func extracts_mixed_case_session_id_from_cookie_header() {
        let header = "foo=bar; Session_ID=token-b; baz=qux"
        #expect(ManusCookieHeader.token(from: header) == "token-b")
    }

    @Test
    func unsupported_cookie_header_returns_nil() {
        #expect(ManusCookieHeader.token(from: "foo=bar; hello=world") == nil)
    }

    #if os(macOS)
    @Test
    func importer_session_info_extracts_session_token() throws {
        let cookies = try [
            #require(self.makeCookie(name: "session_id", value: "cookie-token")),
        ]
        let session = ManusCookieImporter.SessionInfo(cookies: cookies, sourceLabel: "Chrome")
        #expect(session.sessionToken == "cookie-token")
    }

    private func makeCookie(name: String, value: String) -> HTTPCookie? {
        HTTPCookie(properties: [
            .domain: "manus.im",
            .path: "/",
            .name: name,
            .value: value,
            .secure: "TRUE",
        ])
    }
    #endif
}
