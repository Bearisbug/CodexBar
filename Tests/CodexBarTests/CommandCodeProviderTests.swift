import Testing
@testable import CodexBar
@testable import CodexBarCore

struct CommandCodeProviderTests {
    @Test
    func descriptor_metadata_is_correct() {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .commandcode)

        #expect(descriptor.metadata.displayName == "Command Code")
        #expect(descriptor.metadata.dashboardURL == "https://commandcode.ai/studio")
        #expect(descriptor.metadata.subscriptionDashboardURL == "https://commandcode.ai/sixhobbits/settings/billing")
        #expect(descriptor.metadata.cliName == "commandcode")
        #expect(descriptor.branding.iconResourceName == "ProviderIcon-commandcode")
        #expect(descriptor.branding.iconStyle == .commandcode)
    }

    @Test
    func manual_cookie_makes_web_strategy_available() async {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        let settings = ProviderSettingsSnapshot.make(
            commandcode: .init(cookieSource: .manual, manualCookieHeader: "session=manual"))
        let context = ProviderFetchContext(
            runtime: .cli,
            sourceMode: .web,
            includeCredits: true,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: [:],
            settings: settings,
            fetcher: UsageFetcher(),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection)

        #expect(await CommandCodeWebFetchStrategy().isAvailable(context))
    }

    @MainActor
    @Test
    func implementation_is_registered() {
        #expect(ProviderCatalog.implementation(for: .commandcode) != nil)
    }
}
