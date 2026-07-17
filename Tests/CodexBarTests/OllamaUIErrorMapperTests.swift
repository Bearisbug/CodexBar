import CodexBarCore
import Testing
@testable import CodexBar

struct OllamaUIErrorMapperTests {
    @Test
    func maps_Safari_cookie_access_error_to_localized_hint() {
        let message = OllamaUIErrorMapper.userFacingMessage(
            OllamaUsageError.safariCookieAccessDenied.localizedDescription,
            localize: { key in "localized:\(key)" })

        #expect(message == "localized:ollama_safari_cookie_access_hint")
    }

    @Test
    func maps_Brave_decryption_denial_with_browser_name() {
        let message = OllamaUIErrorMapper.userFacingMessage(
            OllamaUsageError.browserCookieDecryptionDenied("Brave").localizedDescription,
            localize: { key in
                key == "ollama_browser_cookie_decryption_denied" ? "%@ localized denial" : key
            })

        #expect(message == "Brave localized denial")
    }

    @Test
    func maps_disabled_Keychain_access_with_browser_name() {
        let message = OllamaUIErrorMapper.userFacingMessage(
            OllamaUsageError.browserCookieDecryptionDisabled("Brave").localizedDescription,
            localize: { key in
                key == "ollama_browser_cookie_decryption_disabled" ? "%@ localized disabled" : key
            })

        #expect(message == "Brave localized disabled")
    }

    @Test
    func preserves_generic_Ollama_errors() {
        let raw = OllamaUsageError.noSessionCookie.localizedDescription
        #expect(OllamaUIErrorMapper.userFacingMessage(raw, localize: { $0 }) == raw)
    }
}
