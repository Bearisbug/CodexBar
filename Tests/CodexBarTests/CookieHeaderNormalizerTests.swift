import CodexBarCore
import Testing

struct CookieHeaderNormalizerTests {
    @Test
    func compact_curl_short_form_without_whitespace_still_parses() {
        let normalized = CookieHeaderNormalizer.normalize("curl https://example.com -bfoo=bar")

        #expect(normalized == "foo=bar")
        #expect(CookieHeaderNormalizer.pairs(from: "curl https://example.com -bfoo=bar").count == 1)
        #expect(CookieHeaderNormalizer.pairs(from: "curl https://example.com -bfoo=bar").first?.name == "foo")
        #expect(CookieHeaderNormalizer.pairs(from: "curl https://example.com -bfoo=bar").first?.value == "bar")
    }
}
