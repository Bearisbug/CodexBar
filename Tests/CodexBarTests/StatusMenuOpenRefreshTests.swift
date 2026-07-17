import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

extension StatusMenuTests {
    @Test
    func store_observation_marks_open_menu_stale_without_rebuilding_during_tracking() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let key = ObjectIdentifier(menu)
        controller.openMenus[key] = menu
        controller.menuRefreshEnabledOverrideForTesting = true

        let openedVersion = controller.menuVersions[key]
        var rebuildCount = 0
        controller._test_openMenuRebuildObserver = { _ in
            rebuildCount += 1
        }

        let now = Date()
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 33,
                    windowMinutes: 300,
                    resetsAt: now.addingTimeInterval(1800),
                    resetDescription: nil),
                secondary: nil,
                tertiary: nil,
                updatedAt: now,
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: "codex@example.com",
                    accountOrganization: nil,
                    loginMethod: "Plus Plan")),
            provider: .codex)

        for _ in 0..<20 where controller.menuContentVersion == openedVersion {
            await Task.yield()
        }

        #expect(controller.menuContentVersion != openedVersion)
        #expect(controller.menuVersions[key] == openedVersion)
        #expect(rebuildCount == 0)
    }

    @Test
    func closed_merged_menu_defers_rebuild_until_next_open_instead_of_pre_warming() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        self.enableOnlyCodex(settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }
        StatusItemController.setClosedMenuPreparationDelayForTesting(.zero)
        defer { StatusItemController.resetClosedMenuPreparationDelayForTesting() }

        controller.menuRefreshEnabledOverrideForTesting = true
        let menu = controller.makeMenu()
        controller.mergedMenu = menu
        controller.statusItem.menu = menu
        for _ in 0..<20 {
            await Task.yield()
        }

        controller.populateMenu(menu, provider: nil)
        controller.markMenuFresh(menu)
        let key = ObjectIdentifier(menu)
        for _ in 0..<40 {
            await Task.yield()
        }
        controller.populateMenu(menu, provider: nil)
        controller.markMenuFresh(menu)
        controller.cancelAllClosedMenuRebuilds()
        controller.closedMenusDeferredUntilNextOpen.removeAll(keepingCapacity: false)
        let openedVersion = controller.menuVersions[key]

        // Background data-refresh tick (stale allowed): closed prep is skipped entirely, so
        // the closed merged menu must not be pre-warmed or marked deferred.
        controller.invalidateMenus(allowStaleContentDuringDataRefresh: true)
        for _ in 0..<40 {
            await Task.yield()
        }
        #expect(controller.openMenus.isEmpty)
        #expect(controller.menuContentVersion != openedVersion)
        #expect(controller.menuVersions[key] == openedVersion)
        #expect(!controller.closedMenusDeferredUntilNextOpen.contains(key))

        // A required (non-stale) invalidation must also leave the closed merged menu deferred.
        controller.invalidateMenus()
        for _ in 0..<40 {
            await Task.yield()
        }
        #expect(controller.menuVersions[key] == openedVersion)
        #expect(controller.closedMenusDeferredUntilNextOpen.contains(key))

        // The deferred merged menu is repopulated synchronously on the next open.
        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }
        #expect(controller.menuVersions[key] == controller.menuContentVersion)
        #expect(!controller.closedMenusDeferredUntilNextOpen.contains(key))
    }

    @Test
    func data_refresh_invalidation_does_not_rebuild_closed_non_merged_attached_menu() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        self.enableOnlyCodex(settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }
        StatusItemController.setClosedMenuPreparationDelayForTesting(.zero)
        defer { StatusItemController.resetClosedMenuPreparationDelayForTesting() }

        controller.menuRefreshEnabledOverrideForTesting = true
        let menu = controller.makeMenu()
        // Use a non-merged attached menu: stale data-refresh invalidations should not pre-warm any
        // closed attached menu, while required invalidations still may prepare non-merged menus.
        controller.fallbackMenu = menu
        controller.statusItem.menu = menu

        controller.populateMenu(menu, provider: nil)
        controller.markMenuFresh(menu)
        let key = ObjectIdentifier(menu)
        for _ in 0..<40 {
            await Task.yield()
        }
        controller.populateMenu(menu, provider: nil)
        controller.markMenuFresh(menu)
        controller.cancelAllClosedMenuRebuilds()
        let openedVersion = controller.menuVersions[key]

        controller.invalidateMenus(allowStaleContentDuringDataRefresh: true)
        for _ in 0..<40 {
            await Task.yield()
        }

        #expect(controller.openMenus.isEmpty)
        #expect(controller.menuContentVersion != openedVersion)
        #expect(controller.menuVersions[key] == openedVersion)

        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }

        for _ in 0..<40 where controller.menuVersions[key] != controller.menuContentVersion {
            await Task.yield()
        }
        #expect(controller.menuVersions[key] == controller.menuContentVersion)
    }

    @Test
    func required_non_merged_closed_menu_preparation_survives_later_data_refresh_invalidation() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        self.enableOnlyCodex(settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }
        StatusItemController.setClosedMenuPreparationDelayForTesting(.zero)
        defer { StatusItemController.resetClosedMenuPreparationDelayForTesting() }

        controller.menuRefreshEnabledOverrideForTesting = true
        let menu = controller.makeMenu()
        // Use a non-merged attached menu so this covers the delayed closed-menu rebuild path. Merged
        // menus are intentionally deferred until next open on current main (#1274).
        controller.fallbackMenu = menu
        controller.statusItem.menu = menu

        controller.populateMenu(menu, provider: nil)
        controller.markMenuFresh(menu)
        let key = ObjectIdentifier(menu)
        let openedVersion = controller.menuVersions[key]

        controller.invalidateMenus()
        let requiredVersion = controller.latestRequiredMenuRebuildVersion
        controller.invalidateMenus(allowStaleContentDuringDataRefresh: true)
        for _ in 0..<40 where controller.menuVersions[key] == openedVersion {
            await Task.yield()
        }

        #expect(controller.openMenus.isEmpty)
        #expect(requiredVersion > (openedVersion ?? -1))
        #expect(controller.menuVersions[key] == controller.menuContentVersion)
    }

    @Test
    func closed_attached_menu_preparation_waits_for_store_refresh_to_finish() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        self.enableOnlyCodex(settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }
        StatusItemController.setClosedMenuPreparationDelayForTesting(.zero)
        defer { StatusItemController.resetClosedMenuPreparationDelayForTesting() }

        controller.menuRefreshEnabledOverrideForTesting = true
        let menu = controller.makeMenu()
        // Use a non-merged attached menu: the merged menu is intentionally never pre-warmed while
        // closed (#1274), so the in-flight-refresh prep machinery is exercised via the fallback menu.
        controller.fallbackMenu = menu
        controller.statusItem.menu = menu

        controller.populateMenu(menu, provider: nil)
        controller.markMenuFresh(menu)
        let key = ObjectIdentifier(menu)
        let openedVersion = controller.menuVersions[key]

        store.isRefreshing = true
        controller.invalidateMenus()
        for _ in 0..<40 {
            await Task.yield()
        }

        #expect(controller.menuVersions[key] == openedVersion)

        store.isRefreshing = false
        controller.invalidateMenus()
        for _ in 0..<40 where controller.menuVersions[key] == openedVersion {
            await Task.yield()
        }

        #expect(controller.openMenus.isEmpty)
        #expect(controller.menuVersions[key] == controller.menuContentVersion)
    }

    @Test
    func closed_attached_menu_preparation_waits_for_token_refresh_to_finish() async {
        StatusItemController.setClosedMenuPreparationDelayForTesting(.zero)
        defer { StatusItemController.resetClosedMenuPreparationDelayForTesting() }

        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        self.enableOnlyCodex(settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        controller.menuRefreshEnabledOverrideForTesting = true
        let menu = controller.makeMenu()
        // Use a non-merged attached menu: the merged menu is intentionally never pre-warmed while
        // closed (#1274), so the in-flight-refresh prep machinery is exercised via the fallback menu.
        controller.fallbackMenu = menu
        controller.statusItem.menu = menu

        controller.populateMenu(menu, provider: nil)
        controller.markMenuFresh(menu)
        let key = ObjectIdentifier(menu)
        let openedVersion = controller.menuVersions[key]

        store.tokenRefreshInFlight.insert(.codex)
        controller.invalidateMenus()
        for _ in 0..<40 {
            await Task.yield()
        }

        #expect(controller.menuVersions[key] == openedVersion)

        store.tokenRefreshInFlight.remove(.codex)
        controller.invalidateMenus()
        for _ in 0..<40 where controller.menuVersions[key] == openedVersion {
            await Task.yield()
        }

        #expect(controller.openMenus.isEmpty)
        #expect(controller.menuVersions[key] == controller.menuContentVersion)
    }

    @Test
    func closed_menu_rebuild_cleanup_runs_when_weak_menu_disappears() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        self.enableOnlyCodex(settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }
        StatusItemController.setClosedMenuPreparationDelayForTesting(.zero)
        defer { StatusItemController.resetClosedMenuPreparationDelayForTesting() }

        let key: ObjectIdentifier
        do {
            let menu = NSMenu()
            key = ObjectIdentifier(menu)
            controller.rebuildClosedMenuIfNeeded(menu)
            #expect(controller.closedMenuRebuildTasks[key] != nil)
            #expect(controller.closedMenuRebuildTokens[key] != nil)
        }

        for _ in 0..<40 where controller.closedMenuRebuildTasks[key] != nil {
            await Task.yield()
        }

        #expect(controller.closedMenuRebuildTasks[key] == nil)
        #expect(controller.closedMenuRebuildTokens[key] == nil)
    }

    @Test
    func merged_menu_close_defers_stale_rebuild_until_next_open() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        self.enableOnlyCodex(settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }
        StatusItemController.setClosedMenuPreparationDelayForTesting(.zero)
        defer { StatusItemController.resetClosedMenuPreparationDelayForTesting() }

        controller.menuRefreshEnabledOverrideForTesting = true
        let menu = controller.makeMenu()
        controller.mergedMenu = menu
        controller.statusItem.menu = menu
        controller.populateMenu(menu, provider: nil)
        controller.markMenuFresh(menu)
        controller.menuWillOpen(menu)

        let key = ObjectIdentifier(menu)
        let openedVersion = controller.menuVersions[key]
        controller.invalidateMenus(refreshOpenMenus: false)
        #expect(controller.menuNeedsRefresh(menu))

        controller.menuDidClose(menu)
        await self.waitUntilClosedMenuRebuildRemainsDeferred(controller, key: key, openedVersion: openedVersion)

        #expect(controller.closedMenuRebuildTasks[key] == nil)
        #expect(controller.menuVersions[key] == openedVersion)

        controller.menuWillOpen(menu)
        #expect(controller.menuVersions[key] == controller.menuContentVersion)
    }

    @Test
    func menu_open_keeps_stale_nonempty_content_while_store_refresh_is_active() {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        self.enableOnlyCodex(settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        controller.menuRefreshEnabledOverrideForTesting = true
        let menu = controller.makeMenu()
        controller.mergedMenu = menu
        controller.statusItem.menu = menu

        controller.populateMenu(menu, provider: nil)
        controller.markMenuFresh(menu)
        let key = ObjectIdentifier(menu)
        let openedVersion = controller.menuVersions[key]
        let openedItemCount = menu.items.count

        store.isRefreshing = true
        defer { store.isRefreshing = false }
        controller.invalidateMenus(allowStaleContentDuringDataRefresh: true)
        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }

        #expect(controller.menuVersions[key] == openedVersion)
        #expect(controller.menuContentVersion != openedVersion)
        #expect(menu.items.count == openedItemCount)
        #expect(controller.openMenus[key] === menu)
    }

    @Test
    func menu_open_rebuilds_stale_content_after_privacy_setting_changes_during_refresh() {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        self.enableOnlyCodex(settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        controller.menuRefreshEnabledOverrideForTesting = true
        let menu = controller.makeMenu()
        controller.mergedMenu = menu
        controller.statusItem.menu = menu

        controller.populateMenu(menu, provider: nil)
        controller.markMenuFresh(menu)
        let key = ObjectIdentifier(menu)
        let openedVersion = controller.menuVersions[key]

        store.isRefreshing = true
        defer { store.isRefreshing = false }
        controller.invalidateMenus(allowStaleContentDuringDataRefresh: true)
        settings.hidePersonalInfo = true
        controller.invalidateMenus()
        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }

        #expect(controller.menuVersions[key] == controller.menuContentVersion)
        #expect(controller.menuVersions[key] != openedVersion)
    }

    @Test
    func menu_open_keeps_stale_nonempty_content_while_token_refresh_is_active() {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        self.enableOnlyCodex(settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        controller.menuRefreshEnabledOverrideForTesting = true
        let menu = controller.makeMenu()
        controller.mergedMenu = menu
        controller.statusItem.menu = menu

        controller.populateMenu(menu, provider: nil)
        controller.markMenuFresh(menu)
        let key = ObjectIdentifier(menu)
        let openedVersion = controller.menuVersions[key]
        let openedItemCount = menu.items.count

        store.tokenRefreshInFlight.insert(.codex)
        defer { store.tokenRefreshInFlight.remove(.codex) }
        controller.invalidateMenus(allowStaleContentDuringDataRefresh: true)
        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }

        #expect(controller.menuVersions[key] == openedVersion)
        #expect(controller.menuContentVersion != openedVersion)
        #expect(menu.items.count == openedItemCount)
        #expect(controller.openMenus[key] === menu)
    }

    @Test
    func explicit_store_actions_defer_visible_parent_menu_rebuild() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let key = ObjectIdentifier(menu)
        controller.openMenus[key] = menu
        controller.menuRefreshEnabledOverrideForTesting = true

        let openedVersion = controller.menuVersions[key]
        var rebuildCount = 0
        controller._test_openMenuRebuildObserver = { _ in
            rebuildCount += 1
        }
        defer { controller._test_openMenuRebuildObserver = nil }

        controller.refreshOpenMenusAfterExplicitStoreAction()
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(controller.menuContentVersion != openedVersion)
        #expect(rebuildCount == 0)
        #expect(controller.menuVersions[key] == openedVersion)
        #expect(controller.parentMenuRebuildsDeferredDuringTracking.contains(key))
    }

    @Test
    func repeated_explicit_store_actions_keep_parent_rebuild_deferred() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let key = ObjectIdentifier(menu)
        controller.openMenus[key] = menu
        controller.menuRefreshEnabledOverrideForTesting = true

        var rebuildCount = 0
        controller._test_openMenuRebuildObserver = { _ in
            rebuildCount += 1
        }
        defer { controller._test_openMenuRebuildObserver = nil }

        controller.refreshOpenMenusAfterExplicitStoreAction()
        controller.refreshOpenMenusAfterExplicitStoreAction()
        controller.refreshOpenMenusAfterExplicitStoreAction()

        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(rebuildCount == 0)
        #expect(controller.menuVersions[key] != controller.menuContentVersion)
        #expect(controller.parentMenuRebuildsDeferredDuringTracking.contains(key))
    }

    @Test
    func explicit_refresh_rebuilds_stale_parent_after_hosted_submenu_closes() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let menuKey = ObjectIdentifier(menu)
        controller.openMenus[menuKey] = menu

        let submenu = controller.makeHostedSubviewPlaceholderMenu(
            chartID: StatusItemController.usageBreakdownChartID,
            provider: .codex)
        let submenuKey = ObjectIdentifier(submenu)
        controller.openMenus[submenuKey] = submenu
        controller.menuRefreshEnabledOverrideForTesting = true

        let openedVersion = controller.menuVersions[menuKey]
        var rebuildCount = 0
        controller._test_openMenuRebuildObserver = { _ in
            rebuildCount += 1
        }
        defer { controller._test_openMenuRebuildObserver = nil }

        controller.refreshOpenMenusAfterExplicitStoreAction()
        for _ in 0..<20 where controller.menuContentVersion == openedVersion {
            await Task.yield()
        }
        #expect(controller.menuVersions[menuKey] == openedVersion)

        controller.menuDidClose(submenu)
        for _ in 0..<20 where rebuildCount == 0 {
            await Task.yield()
        }

        #expect(controller.openMenus[submenuKey] == nil)
        #expect(rebuildCount == 1)
        #expect(controller.menuVersions[menuKey] == controller.menuContentVersion)
        #expect(!controller.parentMenuRebuildsDeferredDuringTracking.contains(menuKey))
    }

    @Test
    func hosted_submenu_close_waits_for_active_refresh_before_rebuilding_parent() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let menuKey = ObjectIdentifier(menu)
        controller.openMenus[menuKey] = menu

        let submenu = controller.makeHostedSubviewPlaceholderMenu(
            chartID: StatusItemController.usageBreakdownChartID,
            provider: .codex)
        let submenuKey = ObjectIdentifier(submenu)
        controller.openMenus[submenuKey] = submenu
        controller.menuRefreshEnabledOverrideForTesting = true

        let openedVersion = controller.menuVersions[menuKey]
        var rebuildCount = 0
        controller._test_openMenuRebuildObserver = { _ in
            rebuildCount += 1
        }
        defer { controller._test_openMenuRebuildObserver = nil }

        store.isRefreshing = true
        controller.refreshOpenMenusAfterExplicitStoreAction()
        controller.menuDidClose(submenu)
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(controller.openMenus[submenuKey] == nil)
        #expect(rebuildCount == 0)
        #expect(controller.menuVersions[menuKey] == openedVersion)
        #expect(controller.parentMenuRebuildPendingAfterHostedSubviewClose)

        store.isRefreshing = false
        controller.handleObservedStoreMenuChange()
        for _ in 0..<20 where rebuildCount == 0 {
            await Task.yield()
        }

        #expect(rebuildCount == 1)
        #expect(controller.menuVersions[menuKey] == controller.menuContentVersion)
        #expect(!controller.parentMenuRebuildPendingAfterHostedSubviewClose)
        #expect(!controller.parentMenuRebuildsDeferredDuringTracking.contains(menuKey))
    }

    @Test
    func plain_open_menu_refresh_preserves_pending_switcher_hosted_submenu_cleanup() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let menuKey = ObjectIdentifier(menu)
        controller.openMenus[menuKey] = menu

        let submenu = controller.makeHostedSubviewPlaceholderMenu(
            chartID: StatusItemController.usageBreakdownChartID,
            provider: .codex)
        let submenuKey = ObjectIdentifier(submenu)
        controller.openMenus[submenuKey] = submenu
        controller.menuRefreshEnabledOverrideForTesting = true

        var rootRebuildCount = 0
        controller._test_openMenuRebuildObserver = { rebuiltMenu in
            guard rebuiltMenu === menu else { return }
            rootRebuildCount += 1
        }
        defer { controller._test_openMenuRebuildObserver = nil }

        controller.deferSwitcherMenuRebuildIfStillVisible(menu, provider: .codex)
        controller.refreshOpenMenuIfStillVisible(menu, provider: .codex)

        for _ in 0..<20 where rootRebuildCount == 0 {
            await Task.yield()
        }

        #expect(controller.openMenus[submenuKey] == nil)
        #expect(rootRebuildCount == 1)
        #expect(controller.menuVersions[menuKey] == controller.menuContentVersion)
    }

    @Test
    func rapid_switcher_rebuild_requests_coalesce_before_populating_open_menu() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let menuKey = ObjectIdentifier(menu)
        controller.openMenus[menuKey] = menu
        controller.menuRefreshEnabledOverrideForTesting = true
        controller._test_providerSwitcherMenuRebuildDebounceNanoseconds = 0
        defer { controller._test_providerSwitcherMenuRebuildDebounceNanoseconds = nil }

        var rebuildCount = 0
        controller._test_openMenuRebuildObserver = { _ in
            rebuildCount += 1
        }
        defer { controller._test_openMenuRebuildObserver = nil }
        var refreshGateEntries = 0
        var pendingRefreshGates: [CheckedContinuation<Void, Never>] = []
        func resumePendingRefreshGates() {
            let gates = pendingRefreshGates
            pendingRefreshGates.removeAll(keepingCapacity: true)
            for gate in gates {
                gate.resume()
            }
        }
        controller._test_openMenuRefreshYieldOverride = {
            refreshGateEntries += 1
            await withCheckedContinuation { continuation in
                pendingRefreshGates.append(continuation)
            }
        }
        defer {
            resumePendingRefreshGates()
            controller._test_openMenuRefreshYieldOverride = nil
        }

        controller.deferSwitcherMenuRebuildIfStillVisible(menu, provider: .codex)
        for _ in 0..<20 where refreshGateEntries == 0 {
            await Task.yield()
        }
        #expect(refreshGateEntries == 1)
        #expect(rebuildCount == 0)

        controller.deferSwitcherMenuRebuildIfStillVisible(menu, provider: .codex)
        resumePendingRefreshGates()
        for _ in 0..<20 where refreshGateEntries < 2 {
            await Task.yield()
        }
        #expect(refreshGateEntries == 2)
        #expect(rebuildCount == 0)
        resumePendingRefreshGates()

        for _ in 0..<20 where rebuildCount == 0 {
            await Task.yield()
        }

        #expect(rebuildCount == 1)
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(rebuildCount == 1)
    }

    @Test
    func codex_parent_menu_open_defers_stale_OpenAI_web_refresh_until_tracking_ends() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.openAIWebAccessEnabled = true
        settings.openAIWebBatterySaverEnabled = true
        settings.codexCookieSource = .auto
        self.enableOnlyCodex(settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        store.openAIDashboard = nil
        store.lastOpenAIDashboardSnapshot = nil
        store._test_providerRefreshOverride = { _ in }
        defer { store._test_providerRefreshOverride = nil }
        store._test_codexCreditsLoaderOverride = {
            CreditsSnapshot(remaining: 25, events: [], updatedAt: Date())
        }
        defer { store._test_codexCreditsLoaderOverride = nil }
        let blocker = BlockingManagedOpenAIDashboardLoader()
        var refreshInteractions: [ProviderInteraction] = []
        store._test_openAIDashboardLoaderOverride = { _, _, _, _ in
            refreshInteractions.append(ProviderInteractionContext.current)
            return try await blocker.awaitResult()
        }
        defer { store._test_openAIDashboardLoaderOverride = nil }

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        controller.menuRefreshEnabledOverrideForTesting = true
        StatusItemController.setDeferredMenuInteractionRefreshDelayForTesting(.zero)
        defer { StatusItemController.resetDeferredMenuInteractionRefreshDelayForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)

        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(await blocker.startedCount() == 0)
        #expect(controller.deferredOpenAIDashboardRefreshReason != nil)

        controller.menuDidClose(menu)
        await blocker.waitUntilStarted(count: 1)
        #expect(await blocker.startedCount() == 1)
        #expect(refreshInteractions == [.background])

        await blocker.resumeNext(with: .success(self.makeOpenAIDashboard(
            dailyBreakdown: [],
            updatedAt: Date())))
    }

    @Test
    func programmatic_parent_menu_close_schedules_deferred_OpenAI_web_refresh() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.openAIWebAccessEnabled = true
        settings.openAIWebBatterySaverEnabled = true
        settings.codexCookieSource = .auto
        self.enableOnlyCodex(settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        store.openAIDashboard = nil
        store.lastOpenAIDashboardSnapshot = nil
        store._test_codexCreditsLoaderOverride = {
            CreditsSnapshot(remaining: 0, events: [], updatedAt: Date())
        }
        defer { store._test_codexCreditsLoaderOverride = nil }
        let blocker = BlockingManagedOpenAIDashboardLoader()
        store._test_openAIDashboardLoaderOverride = { _, _, _, _ in
            try await blocker.awaitResult()
        }
        defer { store._test_openAIDashboardLoaderOverride = nil }

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        controller.menuRefreshEnabledOverrideForTesting = true
        StatusItemController.setDeferredMenuInteractionRefreshDelayForTesting(.zero)
        defer { StatusItemController.resetDeferredMenuInteractionRefreshDelayForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        #expect(controller.deferredOpenAIDashboardRefreshReason != nil)

        controller.forgetClosedMenu(menu)
        await blocker.waitUntilStarted(count: 1)
        #expect(await blocker.startedCount() == 1)

        await blocker.resumeNext(with: .success(self.makeOpenAIDashboard(
            dailyBreakdown: [],
            updatedAt: Date())))
    }

    @Test
    func deferred_OpenAI_web_refresh_retries_after_active_store_refresh_completes() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.openAIWebAccessEnabled = true
        settings.openAIWebBatterySaverEnabled = true
        settings.codexCookieSource = .auto
        self.enableOnlyCodex(settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        store.openAIDashboard = nil
        store.lastOpenAIDashboardSnapshot = nil
        store.isRefreshing = true
        let blocker = BlockingManagedOpenAIDashboardLoader()
        store._test_openAIDashboardLoaderOverride = { _, _, _, _ in
            try await blocker.awaitResult()
        }
        defer { store._test_openAIDashboardLoaderOverride = nil }

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        StatusItemController.setDeferredMenuInteractionRefreshDelayForTesting(.zero)
        defer { StatusItemController.resetDeferredMenuInteractionRefreshDelayForTesting() }

        controller.deferOpenAIDashboardRefreshUntilMenuCloses(reason: "parent menu open")
        controller.scheduleDeferredMenuInteractionRefreshIfNeeded()

        try? await Task.sleep(for: .milliseconds(50))
        #expect(await blocker.startedCount() == 0)
        #expect(controller.deferredOpenAIDashboardRefreshReason != nil)

        store.isRefreshing = false
        await blocker.waitUntilStarted(count: 1)
        #expect(await blocker.startedCount() == 1)

        await blocker.resumeNext(with: .success(self.makeOpenAIDashboard(
            dailyBreakdown: [],
            updatedAt: Date())))
    }

    @Test
    func deferred_OpenAI_web_refresh_waits_for_deferred_store_refresh() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.openAIWebAccessEnabled = true
        settings.openAIWebBatterySaverEnabled = true
        settings.codexCookieSource = .auto
        self.enableOnlyCodex(settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        store._setSnapshotForTesting(nil, provider: .codex)
        store.openAIDashboard = nil
        store.lastOpenAIDashboardSnapshot = nil
        let providerBlocker = BlockingStatusMenuProviderRefresh()
        store._test_providerRefreshOverride = { provider in
            guard provider == .codex else { return }
            await providerBlocker.awaitRelease()
        }
        defer { store._test_providerRefreshOverride = nil }
        let dashboardBlocker = BlockingManagedOpenAIDashboardLoader()
        store._test_openAIDashboardLoaderOverride = { _, _, _, _ in
            try await dashboardBlocker.awaitResult()
        }
        defer { store._test_openAIDashboardLoaderOverride = nil }

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        controller.menuRefreshEnabledOverrideForTesting = true
        StatusItemController.setDeferredMenuInteractionRefreshDelayForTesting(.zero)
        defer { StatusItemController.resetDeferredMenuInteractionRefreshDelayForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        controller.menuDidClose(menu)

        await providerBlocker.waitUntilStarted()
        #expect(await dashboardBlocker.startedCount() == 0)

        await providerBlocker.resumeNext()
        await dashboardBlocker.waitUntilStarted(count: 1)
        #expect(await dashboardBlocker.startedCount() == 1)

        await dashboardBlocker.resumeNext(with: .success(self.makeOpenAIDashboard(
            dailyBreakdown: [],
            updatedAt: Date())))
    }

    @Test
    func reopened_menu_keeps_dashboard_refresh_deferred_after_store_refresh() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.openAIWebAccessEnabled = true
        settings.openAIWebBatterySaverEnabled = true
        settings.codexCookieSource = .auto
        self.enableOnlyCodex(settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        store._setSnapshotForTesting(nil, provider: .codex)
        store.openAIDashboard = nil
        store.lastOpenAIDashboardSnapshot = nil
        let providerBlocker = BlockingStatusMenuProviderRefresh()
        store._test_providerRefreshOverride = { provider in
            guard provider == .codex else { return }
            await providerBlocker.awaitRelease()
        }
        defer { store._test_providerRefreshOverride = nil }
        let dashboardBlocker = BlockingManagedOpenAIDashboardLoader()
        store._test_openAIDashboardLoaderOverride = { _, _, _, _ in
            try await dashboardBlocker.awaitResult()
        }
        defer { store._test_openAIDashboardLoaderOverride = nil }

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        controller.menuRefreshEnabledOverrideForTesting = true
        StatusItemController.setDeferredMenuInteractionRefreshDelayForTesting(.zero)
        defer { StatusItemController.resetDeferredMenuInteractionRefreshDelayForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        controller.menuDidClose(menu)
        await providerBlocker.waitUntilStarted()

        let reopenedMenu = controller.makeMenu()
        controller.menuWillOpen(reopenedMenu)
        await providerBlocker.resumeNext()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await dashboardBlocker.startedCount() == 0)
        #expect(controller.deferredOpenAIDashboardRefreshReason != nil)

        controller.menuDidClose(reopenedMenu)
        await dashboardBlocker.waitUntilStarted(count: 1)
        #expect(await dashboardBlocker.startedCount() == 1)

        await dashboardBlocker.resumeNext(with: .success(self.makeOpenAIDashboard(
            dailyBreakdown: [],
            updatedAt: Date())))
    }

    @Test
    func codex_parent_menu_close_refreshes_recent_dashboard_cache_with_no_chart_history() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.openAIWebAccessEnabled = true
        settings.openAIWebBatterySaverEnabled = true
        settings.codexCookieSource = .auto
        self.enableOnlyCodex(settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        store.openAIDashboard = self.makeOpenAIDashboard(dailyBreakdown: [], updatedAt: Date())
        store.lastOpenAIDashboardSnapshot = store.openAIDashboard
        store._test_providerRefreshOverride = { _ in }
        defer { store._test_providerRefreshOverride = nil }
        let blocker = BlockingManagedOpenAIDashboardLoader()
        store._test_openAIDashboardLoaderOverride = { _, _, _, _ in
            try await blocker.awaitResult()
        }
        defer { store._test_openAIDashboardLoaderOverride = nil }

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        controller.menuRefreshEnabledOverrideForTesting = true
        StatusItemController.setDeferredMenuInteractionRefreshDelayForTesting(.zero)
        defer { StatusItemController.resetDeferredMenuInteractionRefreshDelayForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)

        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(await blocker.startedCount() == 0)

        controller.menuDidClose(menu)
        await blocker.waitUntilStarted(count: 1)
        #expect(await blocker.startedCount() == 1)

        await blocker.resumeNext(with: .success(self.makeOpenAIDashboard(
            dailyBreakdown: [
                OpenAIDashboardDailyBreakdown(day: "2026-05-24", services: [], totalCreditsUsed: 12),
            ],
            updatedAt: Date())))
    }

    @Test
    func codex_parent_menu_open_throttles_recent_empty_dashboard_retry() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.openAIWebAccessEnabled = true
        settings.openAIWebBatterySaverEnabled = true
        settings.codexCookieSource = .auto
        self.enableOnlyCodex(settings)

        let now = Date()
        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        store.openAIDashboard = self.makeOpenAIDashboard(dailyBreakdown: [], updatedAt: now.addingTimeInterval(-120))
        store.lastOpenAIDashboardSnapshot = store.openAIDashboard
        store.lastOpenAIDashboardAttemptAt = now.addingTimeInterval(-60)
        store._test_providerRefreshOverride = { _ in }
        defer { store._test_providerRefreshOverride = nil }
        let blocker = BlockingManagedOpenAIDashboardLoader()
        store._test_openAIDashboardLoaderOverride = { _, _, _, _ in
            try await blocker.awaitResult()
        }
        defer { store._test_openAIDashboardLoaderOverride = nil }

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        controller.menuRefreshEnabledOverrideForTesting = true

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        controller.menuDidClose(menu)

        try? await Task.sleep(for: .milliseconds(150))
        #expect(await blocker.startedCount() == 0)
    }

    @Test
    func credits_history_arriving_after_open_rebuilds_parent_menu_after_tracking_ends() async throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.showOptionalCreditsAndExtraUsage = true
        self.enableOnlyCodex(settings)

        let now = Date()
        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: true)
        store.credits = CreditsSnapshot(remaining: 100, events: [], updatedAt: now)
        store.openAIDashboard = self.makeOpenAIDashboard(dailyBreakdown: [], updatedAt: now)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let key = ObjectIdentifier(menu)
        controller.openMenus[key] = menu
        controller.menuRefreshEnabledOverrideForTesting = true

        let openedVersion = try #require(controller.menuVersions[key])
        #expect(self.menuItem(in: menu, id: "menuCardCredits") == nil)

        store.openAIDashboard = self.makeOpenAIDashboard(
            dailyBreakdown: [
                OpenAIDashboardDailyBreakdown(day: "2026-05-24", services: [], totalCreditsUsed: 12),
            ],
            updatedAt: now.addingTimeInterval(10))

        await self.waitUntilOpenMenuStaysStale(controller, key: key, after: openedVersion)

        #expect(controller.menuContentVersion != openedVersion)
        #expect(controller.menuVersions[key] == openedVersion)

        await self.closeMenuAndWaitUntilFresh(controller, menu: menu, key: key)

        let creditsItem = try #require(self.menuItem(in: menu, id: "menuCardCredits"))
        #expect(
            creditsItem.submenu?.items.first?.representedObject as? String ==
                StatusItemController.creditsHistoryChartID)
        #expect(controller.menuVersions[key] == controller.menuContentVersion)
    }

    @Test
    func fresh_dashboard_history_with_same_day_count_rebuilds_parent_menu_after_tracking_ends() async throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.showOptionalCreditsAndExtraUsage = true
        self.enableOnlyCodex(settings)

        let now = Date(timeIntervalSince1970: 100)
        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: true)
        store.credits = CreditsSnapshot(remaining: 100, events: [], updatedAt: now)
        store.openAIDashboard = self.makeOpenAIDashboard(
            dailyBreakdown: [
                OpenAIDashboardDailyBreakdown(day: "2026-05-24", services: [], totalCreditsUsed: 12),
            ],
            updatedAt: now)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let key = ObjectIdentifier(menu)
        controller.openMenus[key] = menu
        controller.menuRefreshEnabledOverrideForTesting = true

        let openedVersion = try #require(controller.menuVersions[key])
        _ = try #require(self.menuItem(in: menu, id: "menuCardCredits"))

        store.openAIDashboard = self.makeOpenAIDashboard(
            dailyBreakdown: [
                OpenAIDashboardDailyBreakdown(day: "2026-05-24", services: [], totalCreditsUsed: 99),
            ],
            updatedAt: now.addingTimeInterval(10))

        await self.waitUntilOpenMenuStaysStale(controller, key: key, after: openedVersion)

        #expect(controller.menuContentVersion != openedVersion)
        #expect(controller.menuVersions[key] == openedVersion)

        await self.closeMenuAndWaitUntilFresh(controller, menu: menu, key: key)

        let creditsItem = try #require(self.menuItem(in: menu, id: "menuCardCredits"))
        #expect(creditsItem.submenu?.items.first?.representedObject as? String == StatusItemController
            .creditsHistoryChartID)
    }

    @Test
    func token_cost_history_arriving_after_open_rebuilds_parent_menu_after_tracking_ends() async throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.costUsageEnabled = true
        settings.costSummaryDisplayStyle = .both
        self.enableOnlyCodex(settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let key = ObjectIdentifier(menu)
        controller.openMenus[key] = menu
        controller.menuRefreshEnabledOverrideForTesting = true

        let openedVersion = try #require(controller.menuVersions[key])
        #expect(self.menuItem(in: menu, id: "menuCardCost") == nil)

        store._setTokenSnapshotForTesting(self.makeCodexTokenCostSnapshot(), provider: .codex)

        await self.waitUntilOpenMenuStaysStale(controller, key: key, after: openedVersion)

        #expect(controller.menuContentVersion != openedVersion)
        #expect(controller.menuVersions[key] == openedVersion)

        await self.closeMenuAndWaitUntilFresh(controller, menu: menu, key: key)

        let costItem = try #require(self.menuItem(in: menu, id: "menuCardCost"))
        #expect(costItem.submenu?.items.first?.representedObject as? String == StatusItemController.costHistoryChartID)
        #expect(controller.menuVersions[key] == controller.menuContentVersion)
    }

    @Test
    func fresh_token_cost_history_with_same_day_count_rebuilds_parent_menu_after_tracking_ends() async throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.costUsageEnabled = true
        settings.costSummaryDisplayStyle = .both
        self.enableOnlyCodex(settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        store._setTokenSnapshotForTesting(
            self.makeCodexTokenCostSnapshot(
                sessionTokens: 123,
                sessionCostUSD: 0.12,
                last30DaysTokens: 456,
                last30DaysCostUSD: 1.23,
                updatedAt: Date(timeIntervalSince1970: 100)),
            provider: .codex)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let key = ObjectIdentifier(menu)
        controller.openMenus[key] = menu
        controller.menuRefreshEnabledOverrideForTesting = true

        let openedVersion = try #require(controller.menuVersions[key])
        _ = try #require(self.menuItem(in: menu, id: "menuCardCost"))

        store._setTokenSnapshotForTesting(
            self.makeCodexTokenCostSnapshot(
                sessionTokens: 999,
                sessionCostUSD: 0.99,
                last30DaysTokens: 888,
                last30DaysCostUSD: 8.88,
                updatedAt: Date(timeIntervalSince1970: 200)),
            provider: .codex)

        await self.waitUntilOpenMenuStaysStale(controller, key: key, after: openedVersion)

        #expect(controller.menuContentVersion != openedVersion)
        #expect(controller.menuVersions[key] == openedVersion)

        await self.closeMenuAndWaitUntilFresh(controller, menu: menu, key: key)

        let costItem = try #require(self.menuItem(in: menu, id: "menuCardCost"))
        #expect(costItem.submenu?.items.first?.representedObject as? String == StatusItemController.costHistoryChartID)
    }

    @Test
    func plan_utilization_history_arriving_after_open_rebuilds_parent_menu_after_tracking_ends() async throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        self.enableOnlyCodex(settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let key = ObjectIdentifier(menu)
        controller.openMenus[key] = menu
        controller.menuRefreshEnabledOverrideForTesting = true

        let openedVersion = try #require(controller.menuVersions[key])
        let usageHistoryItem = try #require(self.menuItem(in: menu, id: "usageHistorySubmenu"))
        #expect(usageHistoryItem.submenu?.items.first?.representedObject as? String == StatusItemController
            .usageHistoryChartID)
        let openedRevision = store.planUtilizationHistoryRevision

        await store.recordPlanUtilizationHistorySample(
            provider: .codex,
            snapshot: self.makeCodexPlanUtilizationSnapshot(),
            now: Date())

        await self.waitUntilOpenMenuStaysStale(controller, key: key, after: openedVersion)

        #expect(store.planUtilizationHistoryRevision > openedRevision)
        #expect(controller.menuContentVersion != openedVersion)
        #expect(controller.menuVersions[key] == openedVersion)

        await self.closeMenuAndWaitUntilFresh(controller, menu: menu, key: key)
    }

    @Test
    func dashboard_attachment_authorization_arriving_after_open_rebuilds_parent_menu_after_close() async throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.openAIWebAccessEnabled = true
        settings.codexCookieSource = .auto
        self.enableOnlyCodex(settings)

        let now = Date()
        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        store.openAIDashboard = self.makeOpenAIDashboard(
            dailyBreakdown: [
                OpenAIDashboardDailyBreakdown(day: "2026-05-24", services: [], totalCreditsUsed: 12),
            ],
            updatedAt: now)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let key = ObjectIdentifier(menu)
        controller.openMenus[key] = menu
        controller.menuRefreshEnabledOverrideForTesting = true

        let openedVersion = try #require(controller.menuVersions[key])
        #expect(store.openAIDashboardAttachmentRevision == 0)

        store.openAIDashboardAttachmentAuthorized = true

        await self.waitUntilOpenMenuStaysStale(controller, key: key, after: openedVersion)

        #expect(store.openAIDashboardAttachmentRevision == 1)
        #expect(controller.menuContentVersion != openedVersion)
        #expect(controller.menuVersions[key] == openedVersion)

        await self.closeMenuAndWaitUntilFresh(controller, menu: menu, key: key)
    }

    private func enableOnlyCodex(_ settings: SettingsStore) {
        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: provider == .codex)
        }
    }

    private func menuItem(in menu: NSMenu, id: String) -> NSMenuItem? {
        menu.items.first { ($0.representedObject as? String) == id }
    }

    private func waitUntilMenuVersionChanges(
        _ controller: StatusItemController,
        from version: Int?) async
    {
        for _ in 0..<20 where controller.menuContentVersion == version {
            await Task.yield()
        }
    }

    private func waitUntilOpenMenuStaysStale(
        _ controller: StatusItemController,
        key: ObjectIdentifier,
        after version: Int?) async
    {
        for _ in 0..<40 {
            guard controller.menuContentVersion != version else {
                await Task.yield()
                continue
            }
            guard controller.menuVersions[key] == version else {
                await Task.yield()
                continue
            }
            return
        }
    }

    private func closeMenuAndWaitUntilFresh(
        _ controller: StatusItemController,
        menu: NSMenu,
        key: ObjectIdentifier) async
    {
        controller.menuDidClose(menu)
        for _ in 0..<40 where controller.menuVersions[key] != controller.menuContentVersion {
            await Task.yield()
        }
        if controller.menuVersions[key] != controller.menuContentVersion {
            controller.menuWillOpen(menu)
        }
        for _ in 0..<40 where controller.menuVersions[key] != controller.menuContentVersion {
            await Task.yield()
        }
        #expect(controller.menuVersions[key] == controller.menuContentVersion)
    }

    private func waitUntilClosedMenuRebuildRemainsDeferred(
        _ controller: StatusItemController,
        key: ObjectIdentifier,
        openedVersion: Int?) async
    {
        for _ in 0..<40
            where controller.closedMenuRebuildTasks[key] != nil ||
            controller.menuVersions[key] != openedVersion
        {
            await Task.yield()
        }
    }

    private func makeOpenAIDashboard(
        dailyBreakdown: [OpenAIDashboardDailyBreakdown],
        updatedAt: Date) -> OpenAIDashboardSnapshot
    {
        OpenAIDashboardSnapshot(
            signedInEmail: "codex@example.com",
            codeReviewRemainingPercent: nil,
            creditEvents: [],
            dailyBreakdown: dailyBreakdown,
            usageBreakdown: [],
            creditsPurchaseURL: nil,
            updatedAt: updatedAt)
    }

    private func makeCodexTokenCostSnapshot(
        sessionTokens: Int = 123,
        sessionCostUSD: Double = 0.12,
        last30DaysTokens: Int = 456,
        last30DaysCostUSD: Double = 1.23,
        updatedAt: Date = Date()) -> CostUsageTokenSnapshot
    {
        CostUsageTokenSnapshot(
            sessionTokens: sessionTokens,
            sessionCostUSD: sessionCostUSD,
            last30DaysTokens: last30DaysTokens,
            last30DaysCostUSD: last30DaysCostUSD,
            daily: [
                CostUsageDailyReport.Entry(
                    date: "2026-05-24",
                    inputTokens: nil,
                    outputTokens: nil,
                    totalTokens: sessionTokens,
                    costUSD: last30DaysCostUSD,
                    modelsUsed: nil,
                    modelBreakdowns: nil),
            ],
            updatedAt: updatedAt)
    }

    private func makeCodexPlanUtilizationSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: 35,
                windowMinutes: 300,
                resetsAt: Date().addingTimeInterval(1800),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 42,
                windowMinutes: 10080,
                resetsAt: Date().addingTimeInterval(86400),
                resetDescription: nil),
            updatedAt: Date(),
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: "codex@example.com",
                accountOrganization: nil,
                loginMethod: "Plus Plan"))
    }

    /// The recent-interaction signal that `AdaptiveRefreshPolicy` reads has exactly one production
    /// entry point: `StatusItemController.menuWillOpen(_:)` calling `store.noteMenuOpened()`. Every
    /// other adaptive-refresh test drives `UsageStore` directly, so none of them would catch that
    /// wiring line being deleted — this test drives the real menu-open path instead.
    @Test
    func menuWillOpen_records_the_menu_open_signal_on_the_store() {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        #expect(store.lastMenuOpenAt == nil)

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)

        #expect(store.lastMenuOpenAt != nil)
    }
}

private actor BlockingStatusMenuProviderRefresh {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var started = 0

    func awaitRelease() async {
        self.started += 1
        self.resumeStartWaiters()
        await withCheckedContinuation { continuation in
            self.continuations.append(continuation)
        }
    }

    func waitUntilStarted() async {
        if self.started > 0 { return }
        await withCheckedContinuation { continuation in
            self.startWaiters.append(continuation)
        }
    }

    func resumeNext() {
        guard !self.continuations.isEmpty else { return }
        self.continuations.removeFirst().resume()
    }

    private func resumeStartWaiters() {
        let waiters = self.startWaiters
        self.startWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }
}
