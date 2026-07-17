import Testing
@testable import CodexBarCore

struct OpenCodeWebCookieSupportTests {
    @Test
    func request_cookie_header_keeps_only_opencode_auth_cookies() {
        let header = OpenCodeWebCookieSupport.requestCookieHeader(
            from: "provider=google; auth=session123; theme=dark; __Host-auth=host456")

        #expect(header == "auth=session123; __Host-auth=host456")
    }

    @Test
    func request_cookie_header_returns_nil_when_auth_cookie_is_missing() {
        let header = OpenCodeWebCookieSupport.requestCookieHeader(from: "provider=google; theme=dark")

        #expect(header == nil)
    }
}
