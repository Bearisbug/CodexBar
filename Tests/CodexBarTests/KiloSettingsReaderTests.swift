import CodexBarCore
import Testing

struct KiloSettingsReaderTests {
    @Test
    func api_URL_defaults_to_app_kilo_AI_trpc() {
        let url = KiloSettingsReader.apiURL(environment: [:])

        #expect(url.scheme == "https")
        #expect(url.host() == "app.kilo.ai")
        #expect(url.path == "/api/trpc")
    }

    @Test
    func api_URL_ignores_environment_override() {
        let url = KiloSettingsReader.apiURL(environment: ["KILO_API_URL": "https://proxy.example.com/trpc"])

        #expect(url.host() == "app.kilo.ai")
        #expect(url.path == "/api/trpc")
    }

    @Test
    func descriptor_uses_app_kilo_AI_dashboard() {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .kilo)
        #expect(descriptor.metadata.dashboardURL == "https://app.kilo.ai/usage")
    }

    @Test
    func descriptor_uses_dedicated_kilo_icon_resource() {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .kilo)
        #expect(descriptor.branding.iconResourceName == "ProviderIcon-kilo")
    }

    @Test
    func descriptor_supports_auto_API_and_CLI_source_modes() {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .kilo)
        let expected: Set<ProviderSourceMode> = [.auto, .api, .cli]
        #expect(descriptor.fetchPlan.sourceModes == expected)
    }
}
