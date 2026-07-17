import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct StatusItemControllerSplitLifecycleTests {
    private func disableMenuCardsForTesting() {
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.setMenuRefreshEnabledForTesting(false)
    }

    private func makeStatusBarForTesting() -> NSStatusBar {
        .system
    }

    private func makeSettings() -> SettingsStore {
        let suite = "StatusItemControllerSplitLifecycleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    private func containsHostingView(_ view: NSView) -> Bool {
        if String(describing: type(of: view)).contains("NSHostingView") {
            return true
        }
        return view.subviews.contains { self.containsHostingView($0) }
    }

    private func makeSplitController() throws -> (SettingsStore, StatusItemController) {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.providerDetectionCompleted = true

        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            if let metadata = registry.metadata[provider] {
                settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: false)
            }
        }
        try settings.setProviderEnabled(provider: .codex, metadata: #require(registry.metadata[.codex]), enabled: true)
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(registry.metadata[.claude]),
            enabled: true)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        return (settings, controller)
    }

    @Test
    func provider_config_notifications_relay_background_work_impact_between_settings_stores() {
        self.disableMenuCardsForTesting()
        let sourceSettings = self.makeSettings()
        let controllerSettings = self.makeSettings()
        controllerSettings.statusChecksEnabled = false
        controllerSettings.refreshFrequency = .manual

        let fetcher = UsageFetcher()
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: controllerSettings)
        let controller = StatusItemController(
            store: store,
            settings: controllerSettings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting(),
            observeProviderConfigNotifications: true)
        defer { controller.releaseStatusItemsForTesting() }

        let initialBackgroundRevision = controllerSettings.backgroundWorkSettingsRevision
        let reorderedProviders = Array(sourceSettings.orderedProviders().reversed())
        sourceSettings.setProviderOrder(reorderedProviders)

        #expect(controllerSettings.orderedProviders() == reorderedProviders)
        #expect(controllerSettings.backgroundWorkSettingsRevision == initialBackgroundRevision)

        sourceSettings.codexUsageDataSource = .cli

        #expect(controllerSettings.codexUsageDataSource == .cli)
        #expect(controllerSettings.backgroundWorkSettingsRevision == initialBackgroundRevision + 1)
    }

    @Test
    func merged_mode_removes_split_provider_status_items() throws {
        let (settings, controller) = try self.makeSplitController()
        defer { controller.releaseStatusItemsForTesting() }

        #expect(controller.statusItems[.codex] != nil)
        #expect(controller.statusItems[.claude] != nil)
        #expect(controller.expectedVisibleStatusItemAutosaveNames == ["codexbar-codex", "codexbar-claude"])

        settings.mergeIcons = true
        controller.handleProviderConfigChange(reason: "test")

        #expect(controller.statusItem.isVisible == true)
        #expect(controller.statusItems.isEmpty)
        #expect(controller.expectedVisibleStatusItemAutosaveNames == ["codexbar-merged"])
    }

    @Test
    func removing_split_provider_status_items_clears_all_menu_lifecycle_state() throws {
        let (settings, controller) = try self.makeSplitController()
        defer { controller.releaseStatusItemsForTesting() }

        let menus = try [UsageProvider.codex, .claude].map { provider in
            try #require(controller.providerMenus[provider])
        }
        let keys = menus.map(ObjectIdentifier.init)
        for (menu, key) in zip(menus, keys) {
            controller.menuProviders[key] = .codex
            controller.menuReadinessSignatures[key] = "readiness"
            controller.menuIdentitySignatures[key] = "identity"
            controller.menuSession.markFresh(key)
            controller.menuSession.deferUntilNextOpen(key)
            controller.menuSession.deferParentRebuild(key)
            controller.openMenus[key] = menu
            controller.menuRefreshTasks[key] = Task {
                try? await Task.sleep(for: .seconds(60))
            }
            controller.closedMenuRebuildTasks[key] = Task {
                try? await Task.sleep(for: .seconds(60))
            }
            controller.openMenuRebuildTasks[key] = Task {
                try? await Task.sleep(for: .seconds(60))
            }
            _ = controller.closedMenuRebuildRequests.replaceRequest(for: key)
            _ = controller.openMenuRebuildRequests.replaceRequest(for: key)
            controller.openMenuRebuildsClosingHostedSubviewMenus.insert(key)
            controller.highlightedMenuItems[key] = NSMenuItem(title: "Highlighted", action: nil, keyEquivalent: "")
            controller.nativeHighlightDeferredMenuRebuilds[key] = .init(provider: .codex)
            controller.pendingMenuBaselineResyncs.insert(key)
        }

        settings.mergeIcons = true
        controller.handleProviderConfigChange(reason: "test")

        for key in keys {
            #expect(controller.menuProviders[key] == nil)
            #expect(controller.menuReadinessSignatures[key] == nil)
            #expect(controller.menuIdentitySignatures[key] == nil)
            #expect(controller.menuSession.renderedVersion(for: key) == nil)
            #expect(!controller.menuSession.isDeferredUntilNextOpen(key))
            #expect(!controller.menuSession.isParentRebuildDeferred(key))
            #expect(controller.openMenus[key] == nil)
            #expect(controller.menuRefreshTasks[key] == nil)
            #expect(controller.closedMenuRebuildTasks[key] == nil)
            #expect(controller.openMenuRebuildTasks[key] == nil)
            #expect(controller.closedMenuRebuildRequests.tokens[key] == nil)
            #expect(controller.openMenuRebuildRequests.tokens[key] == nil)
            #expect(!controller.openMenuRebuildsClosingHostedSubviewMenus.contains(key))
            #expect(controller.highlightedMenuItems[key] == nil)
            #expect(controller.nativeHighlightDeferredMenuRebuilds[key] == nil)
            #expect(!controller.pendingMenuBaselineResyncs.contains(key))
        }
    }

    @Test
    func menu_bar_icons_stay_appkit_hosted() throws {
        let (settings, controller) = try self.makeSplitController()
        defer { controller.releaseStatusItemsForTesting() }

        let codexButton = try #require(controller.statusItems[.codex]?.button)
        #expect(codexButton.image != nil)
        #expect(!self.containsHostingView(codexButton))

        settings.mergeIcons = true
        controller.handleProviderConfigChange(reason: "test")

        let mergedButton = try #require(controller.statusItem.button)
        #expect(mergedButton.image != nil)
        #expect(!self.containsHostingView(mergedButton))
    }

    @Test
    func status_items_publish_stable_manager_identity() throws {
        let (_, controller) = try self.makeSplitController()
        defer { controller.releaseStatusItemsForTesting() }

        let codexButton = try #require(controller.statusItems[.codex]?.button)
        let claudeButton = try #require(controller.statusItems[.claude]?.button)

        #expect(controller.statusItem.autosaveName == "codexbar-merged")
        #expect(controller.statusItems[.codex]?.autosaveName == "codexbar-codex")
        #expect(controller.statusItems[.claude]?.autosaveName == "codexbar-claude")
        #expect(controller.statusItem.button?.accessibilityIdentifier() == "CodexBar.StatusItem")
        #expect(codexButton.accessibilityIdentifier() == "CodexBar.StatusItem.codex")
        #expect(claudeButton.accessibilityIdentifier() == "CodexBar.StatusItem.claude")
        #expect(controller.statusItem.button?.accessibilityTitle() == "CodexBar")
        #expect(codexButton.accessibilityTitle() == "CodexBar")
        #expect(claudeButton.accessibilityTitle() == "CodexBar")
    }

    @Test
    func status_item_identity_returns_stable_autosave_names() {
        #expect(StatusItemController.StatusItemIdentity.merged.autosaveName == "codexbar-merged")
        #expect(StatusItemController.StatusItemIdentity.provider(.codex).autosaveName == "codexbar-codex")
        #expect(StatusItemController.StatusItemIdentity.provider(.claude).autosaveName == "codexbar-claude")
    }

    @Test
    func status_item_placement_preflight_leaves_fresh_install_placement_unset() throws {
        let suite = "StatusItemControllerSplitLifecycleTests-placement-missing-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let key = MenuBarStatusItemPlacementPreflight.preferredPositionKey(autosaveName: "codexbar-merged")

        #expect(!MenuBarStatusItemPlacementPreflight.prepare(defaults: defaults, autosaveName: "codexbar-merged"))
        #expect(defaults.object(forKey: key) == nil)
    }

    @Test
    func status_item_placement_preflight_preserves_missing_new_key_when_legacy_item_placement_exists() throws {
        let suite = "StatusItemControllerSplitLifecycleTests-placement-legacy-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(42, forKey: "NSStatusItem Preferred Position Item-0")
        let key = MenuBarStatusItemPlacementPreflight.preferredPositionKey(autosaveName: "codexbar-merged")

        #expect(!MenuBarStatusItemPlacementPreflight.prepare(
            defaults: defaults,
            autosaveName: "codexbar-merged",
            legacyDefaultItemIndex: 0))

        #expect(defaults.object(forKey: key) == nil)
        #expect(defaults.double(forKey: "NSStatusItem Preferred Position Item-0") == 42)
    }

    @Test
    func status_item_placement_preflight_clears_suspicious_matching_legacy_placement() throws {
        let suite = "StatusItemControllerSplitLifecycleTests-placement-legacy-high-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(11298, forKey: "NSStatusItem Preferred Position Item-0")
        let key = MenuBarStatusItemPlacementPreflight.preferredPositionKey(autosaveName: "codexbar-merged")

        #expect(MenuBarStatusItemPlacementPreflight.prepare(
            defaults: defaults,
            autosaveName: "codexbar-merged",
            legacyDefaultItemIndex: 0,
            maximumPreferredPosition: 3000))

        #expect(defaults.object(forKey: key) == nil)
        #expect(defaults.object(forKey: "NSStatusItem Preferred Position Item-0") == nil)
    }

    @Test
    func status_item_placement_preflight_preserves_missing_new_key_when_mixed_legacy_placements_exist() throws {
        let suite = "StatusItemControllerSplitLifecycleTests-placement-legacy-mixed-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(42, forKey: "NSStatusItem Preferred Position Item-0")
        defaults.set(11298, forKey: "NSStatusItem Preferred Position Item-1")
        let key = MenuBarStatusItemPlacementPreflight.preferredPositionKey(autosaveName: "codexbar-merged")

        #expect(!MenuBarStatusItemPlacementPreflight.prepare(
            defaults: defaults,
            autosaveName: "codexbar-merged",
            legacyDefaultItemIndex: 0))

        #expect(defaults.object(forKey: key) == nil)
        #expect(defaults.double(forKey: "NSStatusItem Preferred Position Item-0") == 42)
        #expect(defaults.double(forKey: "NSStatusItem Preferred Position Item-1") == 11298)
    }

    @Test
    func status_item_placement_preflight_clears_provider_matching_suspicious_legacy_placement() throws {
        let suite = "StatusItemControllerSplitLifecycleTests-placement-provider-mixed-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(42, forKey: "NSStatusItem Preferred Position Item-0")
        defaults.set(11298, forKey: "NSStatusItem Preferred Position Item-1")
        let key = MenuBarStatusItemPlacementPreflight.preferredPositionKey(autosaveName: "codexbar-codex")

        #expect(MenuBarStatusItemPlacementPreflight.prepare(
            defaults: defaults,
            autosaveName: "codexbar-codex",
            legacyDefaultItemIndex: 1,
            maximumPreferredPosition: 3000))

        #expect(defaults.object(forKey: key) == nil)
        #expect(defaults.double(forKey: "NSStatusItem Preferred Position Item-0") == 42)
        #expect(defaults.object(forKey: "NSStatusItem Preferred Position Item-1") == nil)
    }

    @Test
    func status_item_placement_preflight_leaves_provider_key_unset_when_only_merged_legacy_placement_exists() throws {
        let suite = "StatusItemControllerSplitLifecycleTests-placement-provider-single-legacy-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(42, forKey: "NSStatusItem Preferred Position Item-0")
        let key = MenuBarStatusItemPlacementPreflight.preferredPositionKey(autosaveName: "codexbar-codex")

        #expect(!MenuBarStatusItemPlacementPreflight.prepare(
            defaults: defaults,
            autosaveName: "codexbar-codex",
            legacyDefaultItemIndex: 1))

        #expect(defaults.object(forKey: key) == nil)
        #expect(defaults.double(forKey: "NSStatusItem Preferred Position Item-0") == 42)
    }

    @Test
    func status_item_placement_preflight_preserves_provider_key_with_matching_legacy_placement() throws {
        let suite = "StatusItemControllerSplitLifecycleTests-placement-provider-matching-legacy-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(42, forKey: "NSStatusItem Preferred Position Item-0")
        defaults.set(58, forKey: "NSStatusItem Preferred Position Item-1")
        let key = MenuBarStatusItemPlacementPreflight.preferredPositionKey(autosaveName: "codexbar-codex")

        #expect(!MenuBarStatusItemPlacementPreflight.prepare(
            defaults: defaults,
            autosaveName: "codexbar-codex",
            legacyDefaultItemIndex: 1))

        #expect(defaults.object(forKey: key) == nil)
        #expect(defaults.double(forKey: "NSStatusItem Preferred Position Item-0") == 42)
        #expect(defaults.double(forKey: "NSStatusItem Preferred Position Item-1") == 58)
    }

    @Test
    func status_item_placement_preflight_clears_suspicious_high_position() throws {
        let suite = "StatusItemControllerSplitLifecycleTests-placement-high-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = MenuBarStatusItemPlacementPreflight.preferredPositionKey(autosaveName: "codexbar-merged")
        defaults.set(11298, forKey: key)

        #expect(MenuBarStatusItemPlacementPreflight.prepare(
            defaults: defaults,
            autosaveName: "codexbar-merged",
            maximumPreferredPosition: 3000))

        #expect(defaults.object(forKey: key) == nil)
    }

    @Test
    func status_item_placement_preflight_clears_old_forced_zero_position() throws {
        let suite = "StatusItemControllerSplitLifecycleTests-placement-zero-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = MenuBarStatusItemPlacementPreflight.preferredPositionKey(autosaveName: "codexbar-merged")
        defaults.set(0, forKey: key)

        #expect(MenuBarStatusItemPlacementPreflight.prepare(defaults: defaults, autosaveName: "codexbar-merged"))

        #expect(defaults.object(forKey: key) == nil)
    }

    @Test
    func status_item_placement_preflight_clears_malformed_position() throws {
        let suite = "StatusItemControllerSplitLifecycleTests-placement-malformed-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = MenuBarStatusItemPlacementPreflight.preferredPositionKey(autosaveName: "codexbar-merged")
        defaults.set("not-a-position", forKey: key)

        #expect(MenuBarStatusItemPlacementPreflight.prepare(defaults: defaults, autosaveName: "codexbar-merged"))

        #expect(defaults.object(forKey: key) == nil)
    }

    @Test
    func status_item_placement_preflight_preserves_reasonable_position() throws {
        let suite = "StatusItemControllerSplitLifecycleTests-placement-preserve-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = MenuBarStatusItemPlacementPreflight.preferredPositionKey(autosaveName: "codexbar-merged")
        defaults.set(42, forKey: key)

        #expect(!MenuBarStatusItemPlacementPreflight.prepare(defaults: defaults, autosaveName: "codexbar-merged"))

        #expect(defaults.double(forKey: key) == 42)
    }

    @Test
    func status_item_placement_preflight_preserves_large_display_position() throws {
        let suite = "StatusItemControllerSplitLifecycleTests-placement-preserve-large-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = MenuBarStatusItemPlacementPreflight.preferredPositionKey(autosaveName: "codexbar-merged")
        defaults.set(2500, forKey: key)

        #expect(!MenuBarStatusItemPlacementPreflight.prepare(
            defaults: defaults,
            autosaveName: "codexbar-merged",
            maximumPreferredPosition: 2560))

        #expect(defaults.double(forKey: key) == 2500)
    }

    @Test
    func status_item_defaults_repair_removes_stale_hidden_Control_Center_keys_once() throws {
        let suite = "StatusItemControllerSplitLifecycleTests-repair-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(false, forKey: "NSStatusItem VisibleCC Item-0")
        defaults.set(0, forKey: "NSStatusItem VisibleCC Item-12")
        defaults.set(false, forKey: "NSStatusItem VisibleCC codexbar-merged")
        defaults.set(true, forKey: "NSStatusItem VisibleCC Item-1")
        defaults.set(false, forKey: "NSStatusItem VisibleCC com.apple.clock")
        defer {
            defaults.removePersistentDomain(forName: suite)
        }

        let repairedKeys = MenuBarStatusItemDefaultsRepair.repairHiddenVisibilityDefaultsIfNeeded(defaults: defaults)

        #expect(repairedKeys == [
            "NSStatusItem VisibleCC Item-0",
            "NSStatusItem VisibleCC Item-12",
            "NSStatusItem VisibleCC codexbar-merged",
        ])
        #expect(defaults.object(forKey: "NSStatusItem VisibleCC Item-0") == nil)
        #expect(defaults.object(forKey: "NSStatusItem VisibleCC Item-12") == nil)
        #expect(defaults.object(forKey: "NSStatusItem VisibleCC codexbar-merged") == nil)
        #expect(defaults.bool(forKey: "NSStatusItem VisibleCC Item-1"))
        #expect(defaults.object(forKey: "NSStatusItem VisibleCC com.apple.clock") != nil)

        defaults.set(false, forKey: "NSStatusItem VisibleCC Item-2")
        #expect(MenuBarStatusItemDefaultsRepair.repairHiddenVisibilityDefaultsIfNeeded(defaults: defaults).isEmpty)
        #expect(defaults.object(forKey: "NSStatusItem VisibleCC Item-2") != nil)
    }

    @Test
    func status_item_visibility_default_distinguishes_enabled_disabled_and_unset() throws {
        let suite = "StatusItemControllerSplitLifecycleTests-visibility-default-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "NSStatusItem VisibleCC codexbar-merged")
        defaults.set(false, forKey: "NSStatusItem VisibleCC codexbar-claude")
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(MenuBarStatusItemDefaultsRepair.visibilityDefault(
            defaults: defaults,
            autosaveName: "codexbar-merged") == true)
        #expect(MenuBarStatusItemDefaultsRepair.visibilityDefault(
            defaults: defaults,
            autosaveName: "codexbar-claude") == false)
        #expect(MenuBarStatusItemDefaultsRepair.visibilityDefault(
            defaults: defaults,
            autosaveName: "codexbar-codex") == nil)
    }

    @Test
    func non_destructive_visibility_refresh_preserves_split_provider_status_items() throws {
        let (_, controller) = try self.makeSplitController()
        defer { controller.releaseStatusItemsForTesting() }

        let oldCodexItem = try #require(controller.statusItems[.codex])
        let oldClaudeItem = try #require(controller.statusItems[.claude])
        let oldCodexButton = try #require(oldCodexItem.button)

        controller.refreshExistingStatusItemsForVisibilityRecovery()

        let newCodexItem = try #require(controller.statusItems[.codex])
        let newClaudeItem = try #require(controller.statusItems[.claude])
        #expect(newCodexItem === oldCodexItem)
        #expect(newClaudeItem === oldClaudeItem)
        #expect(newCodexItem.button === oldCodexButton)
        #expect(newCodexItem.autosaveName == "codexbar-codex")
        #expect(newCodexItem.button?.accessibilityIdentifier() == "CodexBar.StatusItem.codex")
    }

    @Test
    func non_destructive_visibility_refresh_preserves_merged_status_item() throws {
        let (settings, controller) = try self.makeSplitController()
        defer { controller.releaseStatusItemsForTesting() }

        settings.mergeIcons = true
        controller.handleProviderConfigChange(reason: "test")
        let oldMergedItem = controller.statusItem
        let oldMergedButton = try #require(controller.statusItem.button)

        controller.refreshExistingStatusItemsForVisibilityRecovery()

        #expect(controller.statusItem === oldMergedItem)
        #expect(controller.statusItem.button === oldMergedButton)
        #expect(controller.statusItem.autosaveName == "codexbar-merged")
        #expect(controller.statusItem.button?.accessibilityIdentifier() == "CodexBar.StatusItem")
    }

    @Test
    func recreation_produces_immediately_healthy_snapshots_for_synchronous_guidance_check() throws {
        // verifyScreenChangeRecoveryIfNeeded does a synchronous re-check immediately after
        // the single recreation to decide whether to show macOS 26 Allow-in-Menu-Bar guidance.
        // AppKit must materialise the button and window before returning from
        // recreateStatusItemsForVisibilityRecovery, so the item must not appear blocked at
        // that point. Only a genuine system-level block would leave it blocked — which is
        // exactly the case where guidance is useful.
        let (_, controller) = try self.makeSplitController()
        defer { controller.releaseStatusItemsForTesting() }

        controller.recreateStatusItemsForVisibilityRecovery()

        let allItems = [controller.statusItem] + Array(controller.statusItems.values)
        let snapshots = MenuBarVisibilityWatcher.visibilitySnapshots(allItems)
        #expect(!MenuBarVisibilityWatcher.hasAnyBlockedVisibleSnapshot(snapshots))
    }

    @Test
    func visibility_recovery_recreates_split_provider_status_items() throws {
        let (_, controller) = try self.makeSplitController()
        defer { controller.releaseStatusItemsForTesting() }

        let oldCodexItem = try #require(controller.statusItems[.codex])
        controller.recreateStatusItemsForVisibilityRecovery()

        let newCodexItem = try #require(controller.statusItems[.codex])
        #expect(newCodexItem !== oldCodexItem)
        #expect(newCodexItem.autosaveName == "codexbar-codex")
        #expect(newCodexItem.button?.accessibilityIdentifier() == "CodexBar.StatusItem.codex")
    }

    @Test
    func visibility_recovery_renders_replacement_merged_status_item() throws {
        let (settings, controller) = try self.makeSplitController()
        defer { controller.releaseStatusItemsForTesting() }

        settings.mergeIcons = true
        controller.handleProviderConfigChange(reason: "test")
        let renderedSignature = try #require(controller.lastAppliedMergedIconRenderSignature)

        controller.lastAppliedMergedIconRenderSignature = renderedSignature
        controller.recreateStatusItemsForVisibilityRecovery()

        let mergedButton = try #require(controller.statusItem.button)
        #expect(mergedButton.image != nil)
        #expect(controller.statusItem.autosaveName == "codexbar-merged")
        #expect(mergedButton.accessibilityIdentifier() == "CodexBar.StatusItem")
    }
}
