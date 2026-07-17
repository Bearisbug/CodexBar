import CodexBarCore
import Foundation
import Observation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
// swiftlint:disable:next type_body_length
struct SettingsStoreTests {
    private final class ObservationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func set() {
            self.lock.lock()
            self.value = true
            self.lock.unlock()
        }

        func get() -> Bool {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.value
        }
    }

    private final class BoolRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Bool] = []

        func append(_ value: Bool) {
            self.lock.lock()
            self.values.append(value)
            self.lock.unlock()
        }

        func get() -> [Bool] {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.values
        }
    }

    @Test
    func default_refresh_frequency_is_five_minutes() throws {
        let suite = "SettingsStoreTests-default"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.refreshFrequency == .fiveMinutes)
        #expect(store.refreshFrequency.seconds == 300)
        #expect(defaults.string(forKey: "refreshFrequency") == RefreshFrequency.fiveMinutes.rawValue)
    }

    @Test
    func repairs_unrecognized_refresh_frequency_raw_value() throws {
        let suite = "SettingsStoreTests-invalid-refresh"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set("legacyValue", forKey: "refreshFrequency")
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.refreshFrequency == .fiveMinutes)
        #expect(defaults.string(forKey: "refreshFrequency") == RefreshFrequency.fiveMinutes.rawValue)
    }

    @Test
    func persists_refresh_frequency_across_instances() throws {
        let suite = "SettingsStoreTests-persist"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        storeA.refreshFrequency = .fifteenMinutes

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeB.refreshFrequency == .fifteenMinutes)
        #expect(storeB.refreshFrequency.seconds == 900)
    }

    @Test
    func refresh_on_open_defaults_off_and_persists() throws {
        let suite = "SettingsStoreTests-refresh-on-open"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.refreshAllProvidersOnMenuOpen == false)
        store.refreshAllProvidersOnMenuOpen = true

        let reloaded = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        #expect(reloaded.refreshAllProvidersOnMenuOpen == true)
    }

    @Test
    func exhausted_reset_time_display_defaults_off_and_persists() throws {
        let suite = "SettingsStoreTests-exhausted-reset-time"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.menuBarShowsResetTimeWhenExhausted == false)
        store.menuBarShowsResetTimeWhenExhausted = true

        let reloaded = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        #expect(reloaded.menuBarShowsResetTimeWhenExhausted == true)
    }

    @Test
    func weekly_confetti_setting_defaults_off_and_persists() throws {
        let suite = "SettingsStoreTests-weekly-confetti"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeA.confettiOnWeeklyLimitResetsEnabled == false)
        storeA.confettiOnWeeklyLimitResetsEnabled = true

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeB.confettiOnWeeklyLimitResetsEnabled == true)
    }

    @Test
    func session_confetti_setting_defaults_off_and_persists() throws {
        let suite = "SettingsStoreTests-session-confetti"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeA.confettiOnSessionLimitResetsEnabled == false)
        storeA.confettiOnSessionLimitResetsEnabled = true

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeB.confettiOnSessionLimitResetsEnabled == true)
    }

    @Test
    func provider_storage_setting_defaults_off_and_persists() throws {
        let suite = "SettingsStoreTests-provider-storage"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeA.providerStorageFootprintsEnabled == false)
        #expect(defaultsA.bool(forKey: "providerStorageFootprintsEnabled") == false)
        storeA.providerStorageFootprintsEnabled = true

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeB.providerStorageFootprintsEnabled == true)
    }

    @Test
    func providers_sorted_alphabetically_defaults_off_and_persists() throws {
        let suite = "SettingsStoreTests-providers-sorted-alpha"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeA.providersSortedAlphabetically == false)
        storeA.providersSortedAlphabetically = true

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeB.providersSortedAlphabetically == true)
    }

    @Test
    func alphabetical_provider_order_puts_enabled_first_then_sorts_by_name() {
        let metadata = ProviderDescriptorRegistry.metadata
        let enabled: Set<UsageProvider> = [.cursor, .claude, .codex]
        let ordered = CodexBarConfig.alphabeticalProviderOrder(
            enablement: { enabled.contains($0) })

        #expect(Set(ordered) == Set(UsageProvider.allCases))

        let displayName: (UsageProvider) -> String = { metadata[$0]?.displayName ?? $0.rawValue }
        let enabledPart = ordered.filter { enabled.contains($0) }
        let disabledPart = ordered.filter { !enabled.contains($0) }
        // Enabled providers occupy the top of the list, ahead of every disabled provider.
        #expect(Array(ordered.prefix(enabled.count)) == enabledPart)
        #expect(ordered == enabledPart + disabledPart)
        let isSortedByName: ([UsageProvider]) -> Bool = { group in
            group == group.sorted {
                displayName($0).localizedCaseInsensitiveCompare(displayName($1)) == .orderedAscending
            }
        }
        #expect(isSortedByName(enabledPart))
        #expect(isSortedByName(disabledPart))
    }

    @Test
    func provider_changelog_links_setting_defaults_off_and_persists() throws {
        let suite = "SettingsStoreTests-provider-changelog-links"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeA.providerChangelogLinksEnabled == false)
        #expect(defaultsA.bool(forKey: "providerChangelogLinksEnabled") == false)
        storeA.providerChangelogLinksEnabled = true

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeB.providerChangelogLinksEnabled == true)
    }

    @Test
    func hide_critters_setting_defaults_off_and_persists() throws {
        let suite = "SettingsStoreTests-hide-critters"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeA.menuBarHidesCritters == false)
        #expect(defaultsA.bool(forKey: "menuBarHidesCritters") == false)
        storeA.menuBarHidesCritters = true

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeB.menuBarHidesCritters == true)
    }

    @Test
    func inactive_display_contrast_setting_defaults_off_and_persists() throws {
        let suite = "SettingsStoreTests-inactive-display-contrast"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeA.menuBarHighContrastOnInactiveDisplays == false)
        #expect(defaultsA.bool(forKey: "menuBarHighContrastOnInactiveDisplays") == false)
        storeA.menuBarHighContrastOnInactiveDisplays = true

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeB.menuBarHighContrastOnInactiveDisplays == true)
    }

    @Test
    func persists_selected_menu_provider_across_instances() throws {
        let suite = "SettingsStoreTests-selectedMenuProvider"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        storeA.selectedMenuProvider = .claude

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeB.selectedMenuProvider == .claude)
    }

    @Test
    func persists_merged_menu_last_selected_was_overview_across_instances() throws {
        let suite = "SettingsStoreTests-merged-last-overview"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        storeA.mergedMenuLastSelectedWasOverview = true

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeB.mergedMenuLastSelectedWasOverview == true)
    }

    @Test
    func merged_overview_selected_providers_persists_and_normalizes_across_instances() throws {
        let suite = "SettingsStoreTests-merged-overview-selection"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        storeA.mergedOverviewSelectedProviders = [.opencode, .codex, .opencode, .claude]
        #expect(storeA.mergedOverviewSelectedProviders == [.opencode, .codex, .claude])

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeB.mergedOverviewSelectedProviders == [.opencode, .codex, .claude])
    }

    @Test
    func merged_overview_selected_providers_ignores_invalid_raw_values() throws {
        let suite = "SettingsStoreTests-merged-overview-invalid-raw"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(["codex", "unknown-provider", "claude", "codex"], forKey: "mergedOverviewSelectedProviders")
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.mergedOverviewSelectedProviders == [.codex, .claude])
    }

    @Test
    func resolved_merged_overview_providers_defaults_to_first_three_when_selection_empty() throws {
        let suite = "SettingsStoreTests-merged-overview-default-first-three"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        let activeProviders: [UsageProvider] = [.codex, .claude, .cursor, .opencode, .warp]
        let resolved = store.resolvedMergedOverviewProviders(activeProviders: activeProviders)

        #expect(resolved == [.codex, .claude, .cursor])
    }

    @Test
    func resolved_merged_overview_providers_honors_explicit_empty_selection() throws {
        let suite = "SettingsStoreTests-merged-overview-explicit-empty"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        store.mergedOverviewSelectedProviders = []
        let activeProviders: [UsageProvider] = [.codex, .claude, .cursor, .opencode, .warp]
        let resolved = store.resolvedMergedOverviewProviders(activeProviders: activeProviders)

        #expect(resolved == [])
    }

    @Test
    func resolved_merged_overview_providers_uses_provider_order_not_selection_order() throws {
        let suite = "SettingsStoreTests-merged-overview-order"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        store.mergedOverviewSelectedProviders = [.opencode, .codex, .cursor]
        let activeProviders: [UsageProvider] = [.codex, .claude, .cursor, .opencode]
        let resolved = store.resolvedMergedOverviewProviders(activeProviders: activeProviders)

        #expect(resolved == [.codex, .cursor, .opencode])
    }

    @Test
    func reconcile_merged_overview_selection_removes_unavailable_without_auto_fill() throws {
        let suite = "SettingsStoreTests-merged-overview-reconcile"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        store.mergedOverviewSelectedProviders = [.codex, .claude, .opencode]
        let activeProviders: [UsageProvider] = [.codex, .cursor, .gemini, .opencode]

        let resolved = store.reconcileMergedOverviewSelectedProviders(activeProviders: activeProviders)

        #expect(resolved == [.codex, .opencode])
        #expect(store.mergedOverviewSelectedProviders == [.codex, .opencode])
    }

    @Test
    func reconcile_merged_overview_selection_does_not_clobber_stored_preference_when_three_or_fewer() throws {
        let suite = "SettingsStoreTests-merged-overview-three-or-fewer"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        store.mergedOverviewSelectedProviders = [.codex, .claude, .cursor]
        let activeProviders: [UsageProvider] = [.codex, .claude]

        let resolved = store.reconcileMergedOverviewSelectedProviders(activeProviders: activeProviders)

        #expect(resolved == [.codex, .claude])
        #expect(store.mergedOverviewSelectedProviders == [.codex, .claude, .cursor])
    }

    @Test
    func reconcile_merged_overview_selection_ignores_stale_subset_without_persisting_auto_fill_when_three_or_fewer()
        throws
    {
        let suite = "SettingsStoreTests-merged-overview-three-or-fewer-subset"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        store.mergedOverviewSelectedProviders = [.codex]
        let activeProviders: [UsageProvider] = [.codex, .claude, .cursor]

        let resolved = store.reconcileMergedOverviewSelectedProviders(activeProviders: activeProviders)

        #expect(resolved == [.codex, .claude, .cursor])
        #expect(store.mergedOverviewSelectedProviders == [.codex])
    }

    @Test
    func merged_overview_selection_allows_deselecting_providers_when_three_or_fewer() throws {
        let suite = "SettingsStoreTests-merged-overview-deselect-three-or-fewer"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        let activeProviders: [UsageProvider] = [.codex, .claude, .cursor]
        #expect(store.resolvedMergedOverviewProviders(activeProviders: activeProviders) == activeProviders)

        _ = store.setMergedOverviewProviderSelection(
            provider: .claude,
            isSelected: false,
            activeProviders: activeProviders)

        #expect(store.mergedOverviewSelectedProviders == [.codex, .cursor])
        #expect(store.resolvedMergedOverviewProviders(activeProviders: activeProviders) == [.codex, .cursor])
    }

    @Test
    func merged_overview_selection_applies_when_same_active_set_is_reordered() throws {
        let suite = "SettingsStoreTests-merged-overview-ordered-context"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        let initialActiveProviders: [UsageProvider] = [.codex, .claude, .cursor]
        _ = store.setMergedOverviewProviderSelection(
            provider: .claude,
            isSelected: false,
            activeProviders: initialActiveProviders)

        let reorderedActiveProviders: [UsageProvider] = [.cursor, .codex, .claude]
        let resolved = store.resolvedMergedOverviewProviders(activeProviders: reorderedActiveProviders)

        #expect(resolved == [.cursor, .codex])
    }

    @Test
    func merged_overview_selection_allows_deselecting_providers_when_more_than_three_active() throws {
        let suite = "SettingsStoreTests-merged-overview-deselect-subset"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        store.mergedOverviewSelectedProviders = [.codex, .claude, .cursor]
        let activeProviders: [UsageProvider] = [.codex, .claude, .cursor, .opencode]

        _ = store.setMergedOverviewProviderSelection(
            provider: .cursor,
            isSelected: false,
            activeProviders: activeProviders)

        #expect(store.mergedOverviewSelectedProviders == [.codex, .claude])
        #expect(store.resolvedMergedOverviewProviders(activeProviders: activeProviders) == [.codex, .claude])
    }

    @Test
    func reconcile_merged_overview_selection_preserves_stored_subset_when_active_drops_to_three_or_fewer() throws {
        let suite = "SettingsStoreTests-merged-overview-preserve-subset-across-drop"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        let activeProviders: [UsageProvider] = [.codex, .claude, .cursor, .opencode]
        _ = store.setMergedOverviewProviderSelection(
            provider: .claude,
            isSelected: false,
            activeProviders: activeProviders)
        _ = store.setMergedOverviewProviderSelection(
            provider: .opencode,
            isSelected: true,
            activeProviders: activeProviders)
        #expect(store.mergedOverviewSelectedProviders == [.codex, .cursor, .opencode])

        let reducedActiveProviders: [UsageProvider] = [.codex, .claude, .cursor]
        let resolvedWhenReduced = store.reconcileMergedOverviewSelectedProviders(
            activeProviders: reducedActiveProviders)

        #expect(resolvedWhenReduced == [.codex, .claude, .cursor])
        #expect(store.mergedOverviewSelectedProviders == [.codex, .cursor, .opencode])

        let resolvedWhenRestored = store.resolvedMergedOverviewProviders(activeProviders: activeProviders)
        #expect(resolvedWhenRestored == [.codex, .cursor, .opencode])
    }

    @Test
    func reconcile_merged_overview_selection_clears_preference_when_no_providers_active() throws {
        let suite = "SettingsStoreTests-merged-overview-clear-on-empty-active"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        let activeProviders: [UsageProvider] = [.codex, .claude, .cursor, .opencode]
        _ = store.setMergedOverviewProviderSelection(
            provider: .codex,
            isSelected: false,
            activeProviders: activeProviders)
        #expect(store.resolvedMergedOverviewProviders(activeProviders: activeProviders) == [.claude, .cursor])

        let resolvedWhenEmpty = store.reconcileMergedOverviewSelectedProviders(activeProviders: [])
        #expect(resolvedWhenEmpty == [])

        let resolvedAfterReenable = store.resolvedMergedOverviewProviders(activeProviders: activeProviders)
        #expect(resolvedAfterReenable == [.codex, .claude, .cursor])
    }

    @Test
    func persists_open_code_workspace_ID_across_instances() throws {
        let suite = "SettingsStoreTests-opencode-workspace"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore())

        storeA.opencodeWorkspaceID = "wrk_01KEJ50SHK9YR41HSRSJ6QTFCM"

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore())

        #expect(storeB.opencodeWorkspaceID == "wrk_01KEJ50SHK9YR41HSRSJ6QTFCM")
    }

    @Test
    func defaults_session_quota_notifications_to_enabled() throws {
        let key = "sessionQuotaNotificationsEnabled"
        let suite = "SettingsStoreTests-sessionQuotaNotifications"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        #expect(store.sessionQuotaNotificationsEnabled == true)
        #expect(defaults.bool(forKey: key) == true)
    }

    @Test
    func defaults_quota_warnings_to_disabled_with_global_thresholds_and_sound() throws {
        let suite = "SettingsStoreTests-quota-warning-defaults"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.quotaWarningNotificationsEnabled == false)
        #expect(store.quotaWarningThresholds == [50, 20])
        #expect(store.quotaWarningWindowEnabled(.session) == true)
        #expect(store.quotaWarningWindowEnabled(.weekly) == true)
        #expect(store.quotaWarningSoundEnabled == true)
        #expect(store.quotaWarningOnScreenAlertEnabled == false)
        #expect(store.quotaWarningMarkersVisible == true)
        #expect(defaults.array(forKey: "quotaWarningThresholds") as? [Int] == [50, 20])
        #expect(defaults.object(forKey: "quotaWarningSessionEnabled") as? Bool == true)
        #expect(defaults.object(forKey: "quotaWarningWeeklyEnabled") as? Bool == true)
        #expect(defaults.bool(forKey: "quotaWarningSoundEnabled") == true)
        #expect(defaults.object(forKey: "quotaWarningOnScreenAlertEnabled") as? Bool == false)
        #expect(defaults.object(forKey: "quotaWarningMarkersVisible") as? Bool == true)
    }

    @Test
    func on_screen_quota_warning_preference_persists() throws {
        let suite = "SettingsStoreTests-quota-warning-on-screen-alert"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        store.quotaWarningOnScreenAlertEnabled = true

        let reloaded = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        #expect(reloaded.quotaWarningOnScreenAlertEnabled == true)
    }

    @Test
    func global_quota_warning_windows_persist_independently() throws {
        let suite = "SettingsStoreTests-quota-warning-window-enabled"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        store.setQuotaWarningWindowEnabled(.weekly, enabled: false)

        #expect(store.quotaWarningWindowEnabled(.session) == true)
        #expect(store.quotaWarningWindowEnabled(.weekly) == false)
        #expect(defaults.object(forKey: "quotaWarningWeeklyEnabled") as? Bool == false)
    }

    @Test
    func sanitizes_invalid_quota_warning_thresholds_from_defaults() throws {
        let suite = "SettingsStoreTests-quota-warning-sanitize"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set([120, 20, 20, -5, 50], forKey: "quotaWarningThresholds")
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.quotaWarningThresholds == [99, 50, 20, 0])
        #expect(defaults.array(forKey: "quotaWarningThresholds") as? [Int] == [99, 50, 20, 0])
    }

    @Test
    func quota_warning_threshold_pair_resolves_blanks_and_clamps_bounds() {
        #expect(QuotaWarningThresholds.resolved(upper: nil, lower: nil) == [50, 20])
        #expect(QuotaWarningThresholds.resolved(upper: nil, lower: 10) == [50, 10])
        #expect(QuotaWarningThresholds.resolved(upper: 10, lower: nil) == [10, 0])
        #expect(QuotaWarningThresholds.resolved(upper: 120, lower: -5) == [99, 0])
    }

    @Test
    func provider_quota_warning_override_resolves_before_global_thresholds() throws {
        let suite = "SettingsStoreTests-quota-warning-provider-override"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        store.quotaWarningThresholds = [50, 20]

        #expect(store.resolvedQuotaWarningThresholds(provider: .codex, window: .session) == [50, 20])
        #expect(store.explicitQuotaWarningThresholds(provider: .codex, window: .session) == nil)
        store.setQuotaWarningThresholds(provider: .codex, window: .session, thresholds: [10])
        #expect(store.explicitQuotaWarningThresholds(provider: .codex, window: .session) == [10])
        #expect(store.resolvedQuotaWarningThresholds(provider: .codex, window: .session) == [10])
        #expect(store.resolvedQuotaWarningThresholds(provider: .codex, window: .weekly) == [50, 20])

        store.setQuotaWarningThresholds(provider: .codex, window: .session, thresholds: nil)
        #expect(store.explicitQuotaWarningThresholds(provider: .codex, window: .session) == nil)
        #expect(store.resolvedQuotaWarningThresholds(provider: .codex, window: .session) == [50, 20])
    }

    @Test
    func provider_quota_warning_stale_editor_save_does_not_restore_cleared_override() throws {
        let suite = "SettingsStoreTests-quota-warning-provider-cleared-override"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        store.quotaWarningThresholds = [50, 20]
        store.setQuotaWarningOverride(provider: .codex, window: .session, thresholds: [70, 30], enabled: true)
        let staleEditorThresholds = store.resolvedQuotaWarningThresholds(provider: .codex, window: .session)

        store.setQuotaWarningOverride(provider: .codex, window: .session, thresholds: nil, enabled: nil)
        store.setQuotaWarningThresholdsIfOverridden(
            provider: .codex,
            window: .session,
            thresholds: staleEditorThresholds)

        #expect(store.hasQuotaWarningOverride(provider: .codex, window: .session) == false)
        #expect(store.resolvedQuotaWarningThresholds(provider: .codex, window: .session) == [50, 20])
    }

    @Test
    func provider_quota_warning_inherited_thresholds_stay_inherited_after_no_op_editor_save() throws {
        let suite = "SettingsStoreTests-quota-warning-provider-inherited-thresholds"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        store.quotaWarningThresholds = [50, 20]
        store.setQuotaWarningOverride(provider: .codex, window: .session, thresholds: nil, enabled: true)

        let resolvedEditorThresholds = store.resolvedQuotaWarningThresholds(provider: .codex, window: .session)
        store.setQuotaWarningThresholdsIfOverridden(
            provider: .codex,
            window: .session,
            thresholds: resolvedEditorThresholds)

        let sessionConfig = store.providerConfig(for: .codex)?.quotaWarnings?.session
        #expect(sessionConfig?.enabled == true)
        #expect(sessionConfig?.thresholds == nil)

        store.quotaWarningThresholds = [80, 40]
        #expect(store.resolvedQuotaWarningThresholds(provider: .codex, window: .session) == [80, 40])
    }

    @Test
    func global_quota_warning_thresholds_resolve_independently_by_window() throws {
        let suite = "SettingsStoreTests-quota-warning-window-thresholds"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        store.setQuotaWarningThresholds(.session, thresholds: [25])
        store.setQuotaWarningThresholds(.weekly, thresholds: [75, 10])

        #expect(store.quotaWarningThresholds(.session) == [25])
        #expect(store.quotaWarningThresholds(.weekly) == [75, 10])
        #expect(store.resolvedQuotaWarningThresholds(provider: .codex, window: .session) == [25])
        #expect(store.resolvedQuotaWarningThresholds(provider: .codex, window: .weekly) == [75, 10])
    }

    @Test
    func provider_quota_warning_windows_override_global_enablement_independently() throws {
        let suite = "SettingsStoreTests-quota-warning-provider-window-override"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        store.setQuotaWarningWindowEnabled(.weekly, enabled: false)
        #expect(store.quotaWarningEnabled(provider: .codex, window: .weekly) == false)

        store.setQuotaWarningWindowEnabled(provider: .codex, window: .weekly, enabled: true)
        store.setQuotaWarningWindowEnabled(provider: .codex, window: .session, enabled: false)
        #expect(store.quotaWarningEnabled(provider: .codex, window: .weekly) == true)
        #expect(store.quotaWarningEnabled(provider: .codex, window: .session) == false)
        #expect(store.hasQuotaWarningOverride(provider: .codex, window: .weekly) == true)
        #expect(store.hasQuotaWarningOverride(provider: .codex, window: .session) == true)

        store.setQuotaWarningWindowEnabled(provider: .codex, window: .weekly, enabled: nil)
        #expect(store.quotaWarningEnabled(provider: .codex, window: .weekly) == false)
    }

    @Test
    func defaults_claude_usage_source_to_auto() throws {
        let suite = "SettingsStoreTests-claude-source"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.claudeUsageDataSource == .auto)
    }

    @Test
    func defaults_codex_usage_source_to_auto() throws {
        let suite = "SettingsStoreTests-codex-source"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.codexUsageDataSource == .auto)
    }

    @Test
    func defaults_kilo_usage_source_to_auto() throws {
        let suite = "SettingsStoreTests-kilo-source"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.kiloUsageDataSource == .auto)
    }

    @Test
    func persists_kilo_usage_source_across_instances() throws {
        let suite = "SettingsStoreTests-kilo-source-persist"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        storeA.kiloUsageDataSource = .cli

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeB.kiloUsageDataSource == .cli)
    }

    @Test
    func kilo_extras_only_apply_in_auto_mode() throws {
        let suite = "SettingsStoreTests-kilo-extras"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        store.kiloExtrasEnabled = true
        #expect(store.kiloExtrasEnabled)

        store.kiloUsageDataSource = .api
        #expect(!store.kiloExtrasEnabled)

        store.kiloUsageDataSource = .auto
        #expect(store.kiloExtrasEnabled)
    }

    @Test
    @MainActor
    func apply_external_config_does_not_broadcast() throws {
        let suite = "SettingsStoreTests-external-config"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        final class NotificationCounter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0

            func increment() {
                self.lock.lock()
                self.value += 1
                self.lock.unlock()
            }

            func get() -> Int {
                self.lock.lock()
                defer { self.lock.unlock() }
                return self.value
            }
        }

        let notifications = NotificationCounter()
        let token = NotificationCenter.default.addObserver(
            forName: .codexbarProviderConfigDidChange,
            object: store,
            queue: .main)
        { _ in
            notifications.increment()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        store.applyExternalConfig(store.configSnapshot, reason: "test-external")

        #expect(notifications.get() == 0)
    }

    @Test
    func config_notifications_classify_order_and_provider_changes() throws {
        let suite = "SettingsStoreTests-config-change-impact"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        let impacts = BoolRecorder()
        let token = NotificationCenter.default.addObserver(
            forName: .codexbarProviderConfigDidChange,
            object: store,
            queue: .main)
        { notification in
            impacts.append(notification.userInfo?["affectsBackgroundWork"] as? Bool ?? true)
        }
        defer { NotificationCenter.default.removeObserver(token) }

        store.setProviderOrder(Array(store.orderedProviders().reversed()))
        store.codexUsageDataSource = .cli

        #expect(impacts.get() == [false, true])
    }

    @Test
    func external_config_ignores_order_only_changes_for_background_work() throws {
        let suite = "SettingsStoreTests-external-config-impact"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        let initialConfigRevision = store.configRevision
        let initialBackgroundRevision = store.backgroundWorkSettingsRevision
        var reordered = store.configSnapshot
        reordered.providers.reverse()
        store.applyExternalConfig(reordered, reason: "order-only")

        #expect(store.configRevision == initialConfigRevision + 1)
        #expect(store.backgroundWorkSettingsRevision == initialBackgroundRevision)
        #expect(store.orderedProviders() == reordered.providers.map(\.id))

        var changed = store.configSnapshot
        let codexIndex = try #require(changed.providers.firstIndex(where: { $0.id == .codex }))
        changed.providers[codexIndex].source = .cli
        store.applyExternalConfig(changed, reason: "provider-source", affectsBackgroundWork: false)

        #expect(store.backgroundWorkSettingsRevision == initialBackgroundRevision + 1)
    }

    @Test
    func persists_zai_API_region_across_instances() throws {
        let suite = "SettingsStoreTests-zai-region"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore())

        storeA.zaiAPIRegion = .bigmodelCN

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore())

        #expect(storeB.zaiAPIRegion == .bigmodelCN)
    }

    @Test
    func persists_mini_max_API_region_across_instances() throws {
        let suite = "SettingsStoreTests-minimax-region"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore())

        storeA.minimaxAPIRegion = .chinaMainland

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore())

        #expect(storeB.minimaxAPIRegion == .chinaMainland)
    }

    @Test
    func defaults_open_AI_web_access_to_disabled() throws {
        let suite = "SettingsStoreTests-openai-web"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(false, forKey: "debugDisableKeychainAccess")
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.openAIWebAccessEnabled == false)
        #expect(defaults.bool(forKey: "openAIWebAccessEnabled") == false)
        #expect(store.openAIWebBatterySaverEnabled == false)
        #expect(defaults.bool(forKey: "openAIWebBatterySaverEnabled") == false)
        #expect(store.codexCookieSource == .off)
    }

    @Test
    func infers_open_AI_web_access_enabled_for_legacy_configured_codex_cookies() throws {
        let suite = "SettingsStoreTests-openai-web-legacy"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.removeObject(forKey: "openAIWebAccessEnabled")
        defaults.set(false, forKey: "debugDisableKeychainAccess")
        let configStore = testConfigStore(suiteName: suite)
        try configStore.save(CodexBarConfig(providers: [
            ProviderConfig(id: .codex, cookieSource: .auto),
        ]))

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.openAIWebAccessEnabled == true)
        #expect(defaults.bool(forKey: "openAIWebAccessEnabled") == true)
        #expect(store.openAIWebBatterySaverEnabled == false)
        #expect(defaults.bool(forKey: "openAIWebBatterySaverEnabled") == false)
        #expect(store.codexCookieSource == .auto)
    }

    @Test
    func imports_legacy_open_AI_web_access_defaults_key() throws {
        let suite = "SettingsStoreTests-openai-web-legacy-key"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.removeObject(forKey: "openAIWebAccessEnabled")
        defaults.set(false, forKey: "openAIWebAccess")
        defaults.set(false, forKey: "debugDisableKeychainAccess")
        let configStore = testConfigStore(suiteName: suite)
        try configStore.save(CodexBarConfig(providers: [
            ProviderConfig(id: .codex, cookieSource: .auto),
        ]))

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.openAIWebAccessEnabled == false)
        #expect(defaults.bool(forKey: "openAIWebAccessEnabled") == false)
    }

    @Test
    func infers_open_AI_web_access_enabled_for_legacy_codex_config_with_implicit_auto_cookies() throws {
        let suite = "SettingsStoreTests-openai-web-legacy-implicit-auto"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.removeObject(forKey: "openAIWebAccessEnabled")
        defaults.set(false, forKey: "debugDisableKeychainAccess")
        let configStore = testConfigStore(suiteName: suite)
        try configStore.save(CodexBarConfig(providers: [
            ProviderConfig(id: .codex),
        ]))

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.openAIWebAccessEnabled == true)
        #expect(defaults.bool(forKey: "openAIWebAccessEnabled") == true)
        #expect(store.openAIWebBatterySaverEnabled == false)
        #expect(defaults.bool(forKey: "openAIWebBatterySaverEnabled") == false)
        #expect(store.codexCookieSource == .auto)
    }

    @Test
    func disabling_open_AI_web_access_turns_codex_cookie_source_off() throws {
        let suite = "SettingsStoreTests-openai-web-toggle"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(false, forKey: "debugDisableKeychainAccess")
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        store.codexCookieSource = .auto
        #expect(store.codexCookieSource == .auto)

        store.openAIWebAccessEnabled = false
        #expect(store.codexCookieSource == .off)
        #expect(defaults.bool(forKey: "openAIWebAccessEnabled") == false)

        store.openAIWebAccessEnabled = true
        #expect(store.codexCookieSource == .auto)
        #expect(defaults.bool(forKey: "openAIWebAccessEnabled") == true)
    }

    @Test
    func open_AI_web_battery_saver_persists_separately_from_extras_availability() throws {
        let suite = "SettingsStoreTests-openai-web-battery-saver"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(false, forKey: "debugDisableKeychainAccess")
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.openAIWebBatterySaverEnabled == false)

        store.openAIWebBatterySaverEnabled = false
        #expect(defaults.bool(forKey: "openAIWebBatterySaverEnabled") == false)

        store.openAIWebAccessEnabled = true
        #expect(store.openAIWebBatterySaverEnabled == false)
    }

    @Test
    func codex_spark_usage_visibility_defaults_on_persists_and_refreshes_only_menus() async throws {
        let suite = "SettingsStoreTests-codex-spark-usage-visible"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.codexSparkUsageVisible)
        let backgroundRevision = store.backgroundWorkSettingsRevision
        let menuDidChange = ObservationFlag()
        withObservationTracking {
            _ = store.menuObservationToken
        } onChange: {
            menuDidChange.set()
        }
        store.codexSparkUsageVisible = false
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(store.backgroundWorkSettingsRevision == backgroundRevision)
        #expect(menuDidChange.get())

        let reloaded = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        #expect(reloaded.codexSparkUsageVisible == false)
    }

    @Test
    func menu_observation_token_updates_on_defaults_change() async throws {
        let suite = "SettingsStoreTests-observation-defaults"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        let didChange = ObservationFlag()

        withObservationTracking {
            _ = store.menuObservationToken
        } onChange: {
            didChange.set()
        }

        store.statusChecksEnabled.toggle()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(didChange.get() == true)
    }

    @Test
    func menu_observation_token_updates_on_cost_summary_display_style_changes() async throws {
        let suite = "SettingsStoreTests-observation-cost-summary-display-style"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        let didChange = ObservationFlag()

        withObservationTracking {
            _ = store.menuObservationToken
        } onChange: {
            didChange.set()
        }

        store.costSummaryDisplayStyle = .costSubmenu
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(didChange.get() == true)
    }

    @Test
    func menu_observation_token_ignores_merged_switcher_selection_churn() async throws {
        let suite = "SettingsStoreTests-observation-switcher-selection"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        let didChange = ObservationFlag()

        withObservationTracking {
            _ = store.menuObservationToken
        } onChange: {
            didChange.set()
        }

        store.selectedMenuProvider = .claude
        store.mergedMenuLastSelectedWasOverview.toggle()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(didChange.get() == false)
    }

    @Test
    func menu_observation_token_updates_on_per_window_quota_threshold_changes() async throws {
        let suite = "SettingsStoreTests-observation-quota-threshold-windows"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        func expectObservation(
            for window: QuotaWarningWindow,
            thresholds: [Int]) async
        {
            let didChange = ObservationFlag()
            withObservationTracking {
                _ = store.menuObservationToken
            } onChange: {
                didChange.set()
            }

            store.setQuotaWarningThresholds(window, thresholds: thresholds)
            try? await Task.sleep(nanoseconds: 50_000_000)

            #expect(didChange.get() == true)
        }

        await expectObservation(for: .session, thresholds: [70, 30])
        await expectObservation(for: .weekly, thresholds: [80, 40])
    }

    @Test
    func quota_warning_threshold_setters_ignore_unchanged_values() async throws {
        let suite = "SettingsStoreTests-observation-quota-threshold-noop"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        store.setQuotaWarningThresholds(.session, thresholds: [70, 30])

        let didChange = ObservationFlag()
        withObservationTracking {
            _ = store.menuObservationToken
        } onChange: {
            didChange.set()
        }

        store.setQuotaWarningThresholds(.session, thresholds: [70, 30])
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(didChange.get() == false)
    }

    @Test
    func menu_observation_token_updates_on_weekly_progress_work_days_changes() async throws {
        let suite = "SettingsStoreTests-observation-weekly-progress-work-days"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        let didChange = ObservationFlag()

        withObservationTracking {
            _ = store.menuObservationToken
        } onChange: {
            didChange.set()
        }

        store.weeklyProgressWorkDays = 5
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(didChange.get() == true)
    }

    @Test
    func config_backed_settings_trigger_observation() async throws {
        let suite = "SettingsStoreTests-observation-config"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        let didChange = ObservationFlag()

        withObservationTracking {
            _ = store.codexCookieSource
        } onChange: {
            didChange.set()
        }

        store.codexCookieSource = .manual
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(didChange.get() == true)
    }

    @Test
    func menu_observation_token_updates_on_codex_active_source_change() async throws {
        let suite = "SettingsStoreTests-observation-codex-active-source"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        let didChange = ObservationFlag()

        withObservationTracking {
            _ = store.menuObservationToken
        } onChange: {
            didChange.set()
        }

        store.codexActiveSource = .liveSystem
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(didChange.get() == true)
    }

    @Test
    func provider_order_defaults_to_all_cases() throws {
        let suite = "SettingsStoreTests-providerOrder-default"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.orderedProviders() == UsageProvider.allCases)
    }

    @Test
    func provider_order_persists_and_appends_new_providers() throws {
        let suite = "SettingsStoreTests-providerOrder-persist"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        // Partial list to mimic "older version" missing providers.
        let config = CodexBarConfig(providers: [
            ProviderConfig(id: .gemini),
            ProviderConfig(id: .codex),
        ])
        try configStore.save(config)

        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        let legacyOrder: [UsageProvider] = [.gemini, .codex]
        let appendedProviders = UsageProvider.allCases.filter { !legacyOrder.contains($0) }
        #expect(storeA.orderedProviders() == legacyOrder + appendedProviders)

        // Move one provider; ensure it's persisted across instances.
        let antigravityIndex = try #require(storeA.orderedProviders().firstIndex(of: .antigravity))
        storeA.moveProvider(fromOffsets: IndexSet(integer: antigravityIndex), toOffset: 0)

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeB.orderedProviders().first == .antigravity)
    }

    @Test
    func setting_alibaba_API_key_enables_provider() throws {
        let suite = "SettingsStoreTests-alibaba-enable-on-token"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        let metadata = try #require(ProviderDescriptorRegistry.metadata[.alibaba])
        store.setProviderEnabled(provider: .alibaba, metadata: metadata, enabled: false)

        store.alibabaCodingPlanAPIToken = "cpk-test-token"

        #expect(store.isProviderEnabled(provider: .alibaba, metadata: metadata))
    }

    @Test
    func alibaba_provider_auto_enables_on_startup_when_token_exists() throws {
        let suite = "SettingsStoreTests-alibaba-auto-enable-startup"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let config = CodexBarConfig(providers: [
            ProviderConfig(id: .alibaba, enabled: false, apiKey: "cpk-startup-token"),
        ])
        try configStore.save(config)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        let metadata = try #require(ProviderDescriptorRegistry.metadata[.alibaba])
        #expect(store.isProviderEnabled(provider: .alibaba, metadata: metadata))
    }

    @Test
    func cost_comparison_periods_default_off_and_persist() throws {
        let suite = "SettingsStoreTests-cost-comparison-periods"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(!storeA.costComparisonPeriodsEnabled)
        storeA.costComparisonPeriodsEnabled = true

        let storeB = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        #expect(storeB.costComparisonPeriodsEnabled)
    }

    @Test
    func cost_summary_display_style_defaults_to_both_and_persists() throws {
        let suite = "SettingsStoreTests-cost-summary-display-style"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeA.costSummaryDisplayStyle == .both)

        storeA.costSummaryDisplayStyle = .costSubmenu

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeB.costSummaryDisplayStyle == .costSubmenu)

        storeB.costSummaryDisplayStyleRaw = "legacy-style"
        #expect(storeB.costSummaryDisplayStyle == .both)
    }

    @Test
    func missing_cost_summary_display_style_preserves_existing_enabled_cost_summary() throws {
        let suite = "SettingsStoreTests-cost-summary-display-style-upgrade"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "tokenCostUsageEnabled")
        defaults.removeObject(forKey: "costSummaryDisplayStyle")
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.costSummaryDisplayStyle == .both)
        #expect(defaults.string(forKey: "costSummaryDisplayStyle") == CostSummaryDisplayStyle.both.rawValue)
    }

    @Test
    func enabling_cost_summary_preserves_both_display_style_across_relaunch() throws {
        let suite = "SettingsStoreTests-cost-summary-display-style-enable"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeA.costSummaryDisplayStyle == .both)
        #expect(defaultsA.string(forKey: "costSummaryDisplayStyle") == nil)

        storeA.costUsageEnabled = true

        #expect(storeA.costSummaryDisplayStyle == .both)
        #expect(defaultsA.string(forKey: "costSummaryDisplayStyle") == nil)

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeB.costSummaryDisplayStyle == .both)
    }
}
