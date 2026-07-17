import CodexBarCore
import Testing

struct VeniceSettingsReaderTests {
    @Test
    func reads_VENICE_API_KEY() {
        let env = ["VENICE_API_KEY": "ven-abc123"]
        #expect(VeniceSettingsReader.apiKey(environment: env) == "ven-abc123")
    }

    @Test
    func falls_back_to_VENICE_KEY() {
        let env = ["VENICE_KEY": "ven-fallback"]
        #expect(VeniceSettingsReader.apiKey(environment: env) == "ven-fallback")
    }

    @Test
    func VENICE_API_KEY_takes_priority_over_VENICE_KEY() {
        let env = ["VENICE_API_KEY": "ven-primary", "VENICE_KEY": "ven-secondary"]
        #expect(VeniceSettingsReader.apiKey(environment: env) == "ven-primary")
    }

    @Test
    func trims_whitespace() {
        let env = ["VENICE_API_KEY": "  ven-trimmed  "]
        #expect(VeniceSettingsReader.apiKey(environment: env) == "ven-trimmed")
    }

    @Test
    func strips_double_quotes() {
        let env = ["VENICE_API_KEY": "\"ven-quoted\""]
        #expect(VeniceSettingsReader.apiKey(environment: env) == "ven-quoted")
    }

    @Test
    func strips_single_quotes() {
        let env = ["VENICE_KEY": "'ven-single'"]
        #expect(VeniceSettingsReader.apiKey(environment: env) == "ven-single")
    }

    @Test
    func returns_nil_when_no_key_present() {
        #expect(VeniceSettingsReader.apiKey(environment: [:]) == nil)
    }

    @Test
    func returns_nil_for_empty_key() {
        let env = ["VENICE_API_KEY": ""]
        #expect(VeniceSettingsReader.apiKey(environment: env) == nil)
    }

    @Test
    func returns_nil_for_whitespace_only_key() {
        let env = ["VENICE_API_KEY": "   "]
        #expect(VeniceSettingsReader.apiKey(environment: env) == nil)
    }
}

struct VeniceProviderTokenResolverTests {
    @Test
    func resolves_from_environment() {
        let env = ["VENICE_API_KEY": "ven-resolve-test"]
        let resolution = ProviderTokenResolver.veniceResolution(environment: env)
        #expect(resolution?.token == "ven-resolve-test")
        #expect(resolution?.source == .environment)
    }

    @Test
    func returns_nil_when_key_absent() {
        let resolution = ProviderTokenResolver.veniceResolution(environment: [:])
        #expect(resolution == nil)
    }
}
