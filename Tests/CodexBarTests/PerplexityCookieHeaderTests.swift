import Foundation
import Testing
@testable import CodexBarCore

struct PerplexityCookieHeaderTests {
    @Test
    func bare_token_uses_default_session_cookie_name() {
        let override = PerplexityCookieHeader.override(from: "abc123")
        #expect(override?.name == PerplexityCookieHeader.defaultSessionCookieName)
        #expect(override?.token == "abc123")
        #expect(override?.requestCookieNames == PerplexityCookieHeader.supportedSessionCookieNames)
    }

    @Test
    func extracts_secure_next_auth_session_cookie_from_header() {
        let header = "foo=bar; __Secure-next-auth.session-token=token-a; baz=qux"
        let override = PerplexityCookieHeader.override(from: header)
        #expect(override?.name == "__Secure-next-auth.session-token")
        #expect(override?.token == "token-a")
    }

    @Test
    func extracts_auth_JS_session_cookie_from_header() {
        let header = "foo=bar; __Secure-authjs.session-token=token-b; baz=qux"
        let override = PerplexityCookieHeader.override(from: header)
        #expect(override?.name == "__Secure-authjs.session-token")
        #expect(override?.token == "token-b")
    }

    @Test
    func prefers_auth_JS_session_cookie_when_both_names_exist() {
        let header = """
        __Secure-next-auth.session-token=legacy-token; __Secure-authjs.session-token=live-token
        """
        let override = PerplexityCookieHeader.override(from: header)
        #expect(override?.name == "__Secure-authjs.session-token")
        #expect(override?.token == "live-token")
    }

    @Test
    func reassembles_chunked_next_auth_session_cookie_from_header() {
        let header = """
        foo=bar; __Secure-next-auth.session-token.1=chunk-b; __Secure-next-auth.session-token.0=chunk-a
        """
        let override = PerplexityCookieHeader.override(from: header)
        #expect(override?.name == "__Secure-next-auth.session-token")
        #expect(override?.token == "chunk-achunk-b")
    }

    @Test
    func reassembles_chunked_auth_JS_session_cookie_from_header() {
        let header = "foo=bar; authjs.session-token.0=chunk-a; authjs.session-token.1=chunk-b"
        let override = PerplexityCookieHeader.override(from: header)
        #expect(override?.name == "authjs.session-token")
        #expect(override?.token == "chunk-achunk-b")
    }

    @Test
    func unsupported_cookie_header_returns_nil() {
        let override = PerplexityCookieHeader.override(from: "foo=bar; hello=world")
        #expect(override == nil)
    }

    #if os(macOS)
    @Test
    func importer_session_info_reassembles_chunked_session_cookies() throws {
        let cookies = try [
            #require(self.makeCookie(name: "__Secure-authjs.session-token.0", value: "chunk-a")),
            #require(self.makeCookie(name: "__Secure-authjs.session-token.1", value: "chunk-b")),
        ]
        let session = PerplexityCookieImporter.SessionInfo(cookies: cookies, sourceLabel: "Chrome")

        #expect(session.sessionCookie?.name == "__Secure-authjs.session-token")
        #expect(session.sessionCookie?.token == "chunk-achunk-b")
    }
    #endif

    #if os(macOS)
    private func makeCookie(name: String, value: String) -> HTTPCookie? {
        HTTPCookie(properties: [
            .domain: "www.perplexity.ai",
            .path: "/",
            .name: name,
            .value: value,
            .secure: "TRUE",
        ])
    }
    #endif
}
