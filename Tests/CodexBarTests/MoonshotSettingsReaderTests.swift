import CodexBarCore
import Testing

struct MoonshotSettingsReaderTests {
    @Test
    func api_key_prefers_MOONSHOT_API_KEY() {
        let env = [
            "MOONSHOT_API_KEY": "primary-token",
            "MOONSHOT_KEY": "fallback-token",
        ]

        #expect(MoonshotSettingsReader.apiKey(environment: env) == "primary-token")
    }

    @Test
    func api_key_strips_quotes() {
        let env = ["MOONSHOT_KEY": "\"quoted-token\""]

        #expect(MoonshotSettingsReader.apiKey(environment: env) == "quoted-token")
    }

    @Test
    func region_parses_china() {
        let env = ["MOONSHOT_REGION": "china"]

        #expect(MoonshotSettingsReader.region(environment: env) == .china)
    }

    @Test
    func default_settings_snapshot_does_not_mask_environment_region() {
        let settings = ProviderSettingsSnapshot.MoonshotProviderSettings()

        #expect(settings.region == nil)
    }

    @Test
    func region_defaults_to_international_for_unknown_values() {
        let env = ["MOONSHOT_REGION": "moon"]

        #expect(MoonshotSettingsReader.region(environment: env) == .international)
    }
}

struct MoonshotProviderTokenResolverTests {
    @Test
    func resolves_from_environment() {
        let env = ["MOONSHOT_API_KEY": "env-token"]
        let resolution = ProviderTokenResolver.moonshotResolution(environment: env)

        #expect(resolution?.token == "env-token")
        #expect(resolution?.source == .environment)
    }

    @Test
    func uses_kimi_branding_icon() {
        let branding = MoonshotProviderDescriptor.descriptor.branding

        #expect(branding.iconStyle == .kimi)
        #expect(branding.iconResourceName == "ProviderIcon-kimi")
    }

    @Test
    func dashboard_url_opens_account_console() {
        #expect(
            MoonshotProviderDescriptor.descriptor.metadata.dashboardURL
                == "https://platform.moonshot.ai/console/account")
    }
}
