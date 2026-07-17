import CodexBarCore
import Foundation
import Testing

@Suite(.serialized)
struct MiniMaxLogRedactorTests {
    private static var miniMaxCpPlaceholder: String {
        ["sk", "cp", "placeholder"].joined(separator: "-")
    }

    private static var miniMaxApiPlaceholder: String {
        ["sk", "api", "placeholder"].joined(separator: "-")
    }

    @Test
    func sk_cp_token_is_redacted() {
        let input = Self.miniMaxCpPlaceholder
        let redacted = LogRedactor.redact(input)
        #expect(redacted.contains("sk-cp-") == false)
        #expect(redacted.contains("<redacted-minimax-token>"))
        #expect(redacted.contains("placeholder") == false)
    }

    @Test
    func sk_api_token_is_redacted() {
        let input = Self.miniMaxApiPlaceholder
        let redacted = LogRedactor.redact(input)
        #expect(redacted.contains("sk-api-") == false)
        #expect(redacted.contains("<redacted-minimax-token>"))
        #expect(redacted.contains("placeholder") == false)
    }

    @Test
    func cookie_header_is_redacted() {
        let input = "Cookie: session=cookie-session-placeholder; token=\(Self.miniMaxCpPlaceholder)"
        let redacted = LogRedactor.redact(input)
        #expect(redacted.contains("session=cookie-session-placeholder") == false)
        #expect(redacted.contains(Self.miniMaxCpPlaceholder) == false)
        #expect(redacted.contains("Cookie: <redacted>"))
    }

    @Test
    func authorization_header_value_is_redacted() {
        // Short obvious placeholder, not JWT-like
        let input = "Authorization: Bearer fake-bearer-token"
        let redacted = LogRedactor.redact(input)
        #expect(redacted.contains("fake-bearer-token") == false)
        #expect(redacted.contains("Authorization:"))
    }

    @Test
    func bearer_token_is_not_present_in_raw_form() {
        let input = "Authorization: bearer \(Self.miniMaxApiPlaceholder)"
        let redacted = LogRedactor.redact(input)
        #expect(redacted.contains(Self.miniMaxApiPlaceholder) == false)
    }

    @Test
    func email_is_redacted() {
        let input = "Contact: user@example.com"
        let redacted = LogRedactor.redact(input)
        #expect(redacted.contains("user@example.com") == false)
        #expect(redacted.contains("<redacted-email>"))
    }

    @Test
    func minimax_token_in_cookie_is_not_present_in_raw_form() {
        let input = "Cookie: session=session-placeholder; token=\(Self.miniMaxCpPlaceholder)"
        let redacted = LogRedactor.redact(input)
        #expect(redacted.contains("session=session-placeholder") == false)
        #expect(redacted.contains(Self.miniMaxCpPlaceholder) == false)
    }

    @Test
    func redacted_text_no_longer_matches_original_token_pattern() {
        let originalToken = Self.miniMaxCpPlaceholder
        let input = "Token: \(originalToken)"
        let redacted = LogRedactor.redact(input)

        #expect(redacted.contains(originalToken) == false)
        #expect(redacted.contains("<redacted-minimax-token>"))
    }

    @Test
    func minimax_token_with_punctuation_suffix_is_fully_redacted() {
        let punctuatedToken = "\(Self.miniMaxApiPlaceholder).suffix-more"
        let input = "Error: token=\(punctuatedToken)"
        let redacted = LogRedactor.redact(input)

        #expect(redacted.contains("sk-api-") == false)
        #expect(redacted.contains("suffix-more") == false)
        #expect(redacted.contains("<redacted-minimax-token>"))
    }

    @Test
    func authorization_header_minimax_token_leaves_no_suffix_fragment() {
        let punctuatedToken = "\(Self.miniMaxCpPlaceholder)-part.two"
        let input = "Authorization: Bearer \(punctuatedToken)"
        let redacted = LogRedactor.redact(input)

        #expect(redacted.contains("sk-cp-") == false)
        #expect(redacted.contains("part.two") == false)
        #expect(redacted.contains("Authorization: <redacted>"))
    }
}
