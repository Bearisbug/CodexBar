import Testing
@testable import CodexBarCore

struct PerplexitySettingsReaderTests {
    @Test
    func PERPLEXITY_COOKIE_preserves_the_original_supported_cookie_name() {
        let override = PerplexitySettingsReader.sessionCookieOverride(environment: [
            "PERPLEXITY_COOKIE": "authjs.session-token=env-token",
        ])

        #expect(override?.name == "authjs.session-token")
        #expect(override?.token == "env-token")
        #expect(PerplexitySettingsReader.sessionToken(environment: [
            "PERPLEXITY_COOKIE": "authjs.session-token=env-token",
        ]) == "env-token")
    }

    @Test
    func PERPLEXITY_COOKIE_reassembles_chunked_session_cookies() {
        let override = PerplexitySettingsReader.sessionCookieOverride(environment: [
            "PERPLEXITY_COOKIE": "authjs.session-token.0=chunk-a; authjs.session-token.1=chunk-b",
        ])

        #expect(override?.name == "authjs.session-token")
        #expect(override?.token == "chunk-achunk-b")
    }

    @Test
    func PERPLEXITY_SESSION_TOKEN_tries_all_supported_cookie_names() {
        let override = PerplexitySettingsReader.sessionCookieOverride(environment: [
            "PERPLEXITY_SESSION_TOKEN": "env-token",
        ])

        #expect(override?.name == PerplexityCookieHeader.defaultSessionCookieName)
        #expect(override?.token == "env-token")
        #expect(override?.requestCookieNames == PerplexityCookieHeader.supportedSessionCookieNames)
    }
}
