import AppKit
import CodexBarCore
import Foundation
import XCTest
@testable import CodexBar

@MainActor
final class StatusMenuClaudeNativeAccountsTests: XCTestCase {
    override func tearDown() {
        StatusItemController.claudeNativeAccountSetOverrideForTesting = nil
        super.tearDown()
    }

    private func makeSettings() -> SettingsStore {
        let settings = testSettingsStore(
            suiteName: "StatusMenuClaudeNativeAccountsTests",
            tokenAccountStore: InMemoryTokenAccountStore())
        settings.providerDetectionCompleted = true
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: provider == .claude)
        }
        return settings
    }

    private func makeController(settings: SettingsStore) -> (StatusItemController, UsageStore) {
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        return (controller, store)
    }

    private static func accountSet(_ accounts: [ClaudeManagedAccount]) -> ClaudeManagedAccountSet {
        ClaudeManagedAccountSet(version: FileClaudeManagedAccountStore.currentVersion, accounts: accounts)
    }

    func test_nativeSwitcherRendersAccountsWithActiveHighlight() throws {
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.setMenuRefreshEnabledForTesting(false)
        StatusItemController.claudeNativeAccountSetOverrideForTesting = Self.accountSet([
            ClaudeManagedAccount(email: "a@example.com", customLabel: "Main", isActive: true),
            ClaudeManagedAccount(email: "b@example.com", customLabel: "Backup"),
        ])
        let settings = self.makeSettings()
        let (controller, _) = self.makeController(settings: settings)
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu(for: .claude)
        controller.menuWillOpen(menu)

        let switcher = try XCTUnwrap(
            menu.items.compactMap { $0.view as? ClaudeNativeAccountSwitcherView }.first)
        XCTAssertEqual(switcher._test_buttonTitles(), ["Main", "Backup"])
        XCTAssertEqual(switcher._test_activeTitle(), "Main")
    }

    func test_nativeSwitcherRendersInMergedIconsMode() throws {
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.setMenuRefreshEnabledForTesting(false)
        StatusItemController.claudeNativeAccountSetOverrideForTesting = Self.accountSet([
            ClaudeManagedAccount(email: "a@example.com", customLabel: "Main", isActive: true),
            ClaudeManagedAccount(email: "b@example.com", customLabel: "Backup"),
        ])
        let settings = self.makeSettings()
        settings.mergeIcons = true
        let registry = ProviderRegistry.shared
        for provider in [UsageProvider.claude, .codex] {
            guard let metadata = registry.metadata[provider] else { continue }
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: true)
        }
        settings.mergedMenuLastSelectedWasOverview = false
        let (controller, _) = self.makeController(settings: settings)
        defer { controller.releaseStatusItemsForTesting() }
        controller.selectedMenuProvider = .claude

        let menu = try XCTUnwrap(controller.makeMenu() as? StatusItemMenu)
        controller.mergedMenu = menu
        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }

        let switcher = try XCTUnwrap(
            menu.items.compactMap { $0.view as? ClaudeNativeAccountSwitcherView }.first)
        XCTAssertEqual(switcher._test_activeTitle(), "Main")
    }

    func test_nativeSwitcherHiddenWithFewerThanTwoAccounts() {
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.setMenuRefreshEnabledForTesting(false)
        StatusItemController.claudeNativeAccountSetOverrideForTesting = Self.accountSet([
            ClaudeManagedAccount(email: "a@example.com", isActive: true),
        ])
        let settings = self.makeSettings()
        let (controller, _) = self.makeController(settings: settings)
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu(for: .claude)
        controller.menuWillOpen(menu)

        XCTAssertNil(menu.items.compactMap { $0.view as? ClaudeNativeAccountSwitcherView }.first)
    }
}
