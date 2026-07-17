import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct WayfinderProviderTests {
    @Test
    @MainActor
    func descriptor_and_implementation_are_registered() throws {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .wayfinder)
        #expect(descriptor.metadata.displayName == "Wayfinder")
        #expect(descriptor.metadata.cliName == "wayfinder")
        #expect(descriptor.cli.aliases.contains("wayfinder-router"))
        #expect(!descriptor.metadata.defaultEnabled)
        #expect(descriptor.branding.iconResourceName == "ProviderIcon-wayfinder")

        let implementation = try #require(ProviderImplementationRegistry.implementation(for: .wayfinder))
        #expect(implementation.id == .wayfinder)
    }

    @Test
    @MainActor
    func dashboard_follows_saved_gateway_instead_of_the_descriptor_default() throws {
        let suite = "WayfinderProviderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.wayfinderGatewayURL = "http://localhost:9191/wayfinder"

        #expect(WayfinderProviderImplementation.dashboardURL(
            settings: settings,
            environment: [:]).absoluteString == "http://localhost:9191/wayfinder/router")
    }
}
