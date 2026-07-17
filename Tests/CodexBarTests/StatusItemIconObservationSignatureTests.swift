import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct StatusItemIconObservationSignatureTests {
    private func makeController(suiteName: String) -> (SettingsStore, UsageStore, StatusItemController) {
        let settings = SettingsStore(
            configStore: testConfigStore(suiteName: suiteName),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.statusChecksEnabled = true
        settings.refreshFrequency = .manual
        settings.usageBarsShowUsed = false
        settings.showOptionalCreditsAndExtraUsage = true
        settings.menuBarShowsBrandIconWithPercent = false
        settings.menuBarShowsHighestUsage = false
        settings.mergeIcons = true
        settings.mergedMenuLastSelectedWasOverview = false
        settings.selectedMenuProvider = .codex

        let registry = ProviderRegistry.shared
        if let codexMeta = registry.metadata[.codex] {
            settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: true)
        }
        if let claudeMeta = registry.metadata[.claude] {
            settings.setProviderEnabled(provider: .claude, metadata: claudeMeta, enabled: false)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        store._setSnapshotForTesting(Self.makeSnapshot(provider: .codex, email: "icon@example.com"), provider: .codex)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
        return (settings, store, controller)
    }

    @Test
    func store_icon_observation_signature_ignores_refresh_and_status_metadata_churn() {
        let (_, store, controller) = self.makeController(
            suiteName: "StatusItemIconObservationSignatureTests-refresh-metadata")
        defer { controller.releaseStatusItemsForTesting() }

        store.statuses[.codex] = ProviderStatus(
            indicator: .none,
            description: "initial",
            updatedAt: Date(timeIntervalSince1970: 10))
        let baseline = controller.storeIconObservationSignature()

        store.isRefreshing = true
        store.statuses[.codex] = ProviderStatus(
            indicator: .none,
            description: "same indicator, newer timestamp",
            updatedAt: Date(timeIntervalSince1970: 20))

        #expect(controller.storeIconObservationSignature() == baseline)
    }

    @Test
    func store_icon_observation_signature_ignores_non_visual_snapshot_churn() {
        let (_, store, controller) = self.makeController(
            suiteName: "StatusItemIconObservationSignatureTests-snapshot-metadata")
        defer { controller.releaseStatusItemsForTesting() }

        let baseline = controller.storeIconObservationSignature()

        store._setSnapshotForTesting(
            Self.makeSnapshot(
                provider: .codex,
                email: "rotated-account@example.com",
                updatedAt: Date(timeIntervalSince1970: 200)),
            provider: .codex)

        let signature = controller.storeIconObservationSignature()

        #expect(signature == baseline)
        #expect(!signature.contains("rotated-account@example.com"))
    }

    @Test
    func merged_store_icon_observation_signature_ignores_non_primary_snapshot_churn() throws {
        let (settings, store, controller) = self.makeController(
            suiteName: "StatusItemIconObservationSignatureTests-merged-secondary-snapshot")
        defer { controller.releaseStatusItemsForTesting() }

        let registry = ProviderRegistry.shared
        let claudeMetadata = try #require(registry.metadata[.claude])
        settings.setProviderEnabled(provider: .claude, metadata: claudeMetadata, enabled: true)
        settings.selectedMenuProvider = .codex
        store._setSnapshotForTesting(
            Self.makeSnapshot(provider: .claude, email: "claude@example.com"),
            provider: .claude)
        let baseline = controller.storeIconObservationSignature()

        store._setSnapshotForTesting(
            Self.makeSnapshot(
                provider: .claude,
                email: "changed@example.com",
                primaryUsedPercent: 99,
                secondaryUsedPercent: 88,
                updatedAt: Date(timeIntervalSince1970: 300)),
            provider: .claude)

        #expect(controller.storeIconObservationSignature() == baseline)
    }

    @Test
    func store_icon_observation_signature_changes_when_icon_percentages_change() {
        let (_, store, controller) = self.makeController(
            suiteName: "StatusItemIconObservationSignatureTests-percent-change")
        defer { controller.releaseStatusItemsForTesting() }

        let baseline = controller.storeIconObservationSignature()

        store._setSnapshotForTesting(
            Self.makeSnapshot(
                provider: .codex,
                email: "icon@example.com",
                primaryUsedPercent: 42,
                secondaryUsedPercent: 63),
            provider: .codex)

        #expect(controller.storeIconObservationSignature() != baseline)
    }

    @Test
    func store_icon_observation_signature_tracks_selected_copilot_budget() throws {
        let (settings, store, controller) = self.makeController(
            suiteName: "StatusItemIconObservationSignatureTests-copilot-budget")
        defer { controller.releaseStatusItemsForTesting() }

        let registry = ProviderRegistry.shared
        let codexMetadata = try #require(registry.metadata[.codex])
        let copilotMetadata = try #require(registry.metadata[.copilot])
        settings.setProviderEnabled(provider: .codex, metadata: codexMetadata, enabled: false)
        settings.setProviderEnabled(provider: .copilot, metadata: copilotMetadata, enabled: true)
        settings.selectedMenuProvider = .copilot
        settings.copilotBudgetExtrasEnabled = true
        settings.copilotIconSecondaryWindowID = "copilot-budget-agent"

        store._setSnapshotForTesting(
            Self.makeCopilotSnapshot(budgetUsedPercent: 25),
            provider: .copilot)
        let baseline = controller.storeIconObservationSignature()

        store._setSnapshotForTesting(
            Self.makeCopilotSnapshot(budgetUsedPercent: 75),
            provider: .copilot)

        #expect(controller.storeIconObservationSignature() != baseline)
    }

    @Test
    func store_icon_observation_signature_changes_when_credit_fallback_changes() {
        let (_, store, controller) = self.makeController(
            suiteName: "StatusItemIconObservationSignatureTests-credit-fallback")
        defer { controller.releaseStatusItemsForTesting() }

        store._setSnapshotForTesting(
            Self.makeSnapshot(
                provider: .codex,
                email: "icon@example.com",
                primaryUsedPercent: 100,
                secondaryUsedPercent: 20),
            provider: .codex)
        store.credits = CreditsSnapshot(remaining: 80, events: [], updatedAt: Date(timeIntervalSince1970: 100))
        let baseline = controller.storeIconObservationSignature()

        store.credits = CreditsSnapshot(remaining: 42, events: [], updatedAt: Date(timeIntervalSince1970: 200))

        #expect(controller.storeIconObservationSignature() != baseline)
    }

    @Test
    func store_icon_observation_signature_ignores_unused_credit_balance() {
        let (_, store, controller) = self.makeController(
            suiteName: "StatusItemIconObservationSignatureTests-unused-credits")
        defer { controller.releaseStatusItemsForTesting() }

        store.credits = CreditsSnapshot(remaining: 80, events: [], updatedAt: Date(timeIntervalSince1970: 100))
        let baseline = controller.storeIconObservationSignature()

        store.credits = CreditsSnapshot(remaining: 42, events: [], updatedAt: Date(timeIntervalSince1970: 200))

        #expect(controller.storeIconObservationSignature() == baseline)
    }

    @Test
    func merged_store_icon_observation_signature_ignores_non_primary_status_changes() throws {
        let (settings, store, controller) = self.makeController(
            suiteName: "StatusItemIconObservationSignatureTests-merged-secondary-status")
        defer { controller.releaseStatusItemsForTesting() }

        let registry = ProviderRegistry.shared
        let claudeMetadata = try #require(registry.metadata[.claude])
        settings.setProviderEnabled(provider: .claude, metadata: claudeMetadata, enabled: true)
        let baseline = controller.storeIconObservationSignature()

        store.statuses[.claude] = ProviderStatus(
            indicator: .major,
            description: "Claude status issue",
            updatedAt: Date(timeIntervalSince1970: 20))

        #expect(controller.storeIconObservationSignature() == baseline)
    }

    @Test
    func store_icon_observation_signature_changes_when_status_indicator_changes() {
        let (_, store, controller) = self.makeController(
            suiteName: "StatusItemIconObservationSignatureTests-status-indicator")
        defer { controller.releaseStatusItemsForTesting() }

        store.statuses[.codex] = ProviderStatus(
            indicator: .none,
            description: "initial",
            updatedAt: Date(timeIntervalSince1970: 10))
        let baseline = controller.storeIconObservationSignature()

        store.statuses[.codex] = ProviderStatus(
            indicator: .major,
            description: "major outage",
            updatedAt: Date(timeIntervalSince1970: 20))

        #expect(controller.storeIconObservationSignature() != baseline)
    }

    @Test
    func store_icon_observation_signature_changes_when_hide_critters_toggles() {
        let (settings, _, controller) = self.makeController(
            suiteName: "StatusItemIconObservationSignatureTests-hide-critters")
        defer { controller.releaseStatusItemsForTesting() }

        settings.menuBarHidesCritters = false
        let baseline = controller.storeIconObservationSignature()

        settings.menuBarHidesCritters = true

        #expect(controller.storeIconObservationSignature() != baseline)
    }

    @Test
    func display_settings_persist_cached_widget_snapshot() async {
        let (settings, store, controller) = self.makeController(
            suiteName: "StatusItemIconObservationSignatureTests-widget-display")
        defer { controller.releaseStatusItemsForTesting() }

        var widgetSnapshots: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { widgetSnapshots.append($0) }
        defer { store._test_widgetSnapshotSaveOverride = nil }

        settings.usageBarsShowUsed = true
        try? await Task.sleep(nanoseconds: 50_000_000)
        await store.widgetSnapshotPersistTask?.value

        #expect(widgetSnapshots.last?.usageBarsShowUsed == true)
        #expect(widgetSnapshots.last?.entries.contains(where: { $0.provider == .codex }) == true)
    }

    @Test
    func config_only_settings_do_not_persist_cached_widget_snapshot() async {
        let (settings, store, controller) = self.makeController(
            suiteName: "StatusItemIconObservationSignatureTests-widget-config-only")
        defer { controller.releaseStatusItemsForTesting() }

        var widgetSnapshots: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { widgetSnapshots.append($0) }
        defer { store._test_widgetSnapshotSaveOverride = nil }

        settings.zaiAPIToken = "test-token"
        try? await Task.sleep(nanoseconds: 100_000_000)
        await store.widgetSnapshotPersistTask?.value

        #expect(widgetSnapshots.isEmpty)
    }

    @Test
    func updateIcons_reuses_a_precomputed_store_icon_signature_instead_of_recomputing_it() {
        let (_, _, controller) = self.makeController(
            suiteName: "StatusItemIconObservationSignatureTests-precomputed-reuse")
        defer { controller.releaseStatusItemsForTesting() }

        let precomputed = "precomputed-store-icon-signature-sentinel"
        controller.updateIcons(precomputedStoreIconSignature: precomputed)

        // A supplied signature must be stored verbatim; if updateIcons recomputed it, the gate would
        // never equal the sentinel value.
        #expect(controller.lastObservedStoreIconWorkSignature == precomputed)
    }

    @Test
    func updateIcons_recomputes_the_store_icon_signature_when_none_is_provided() {
        let (_, _, controller) = self.makeController(
            suiteName: "StatusItemIconObservationSignatureTests-recompute-default")
        defer { controller.releaseStatusItemsForTesting() }

        controller.updateIcons()

        #expect(controller.lastObservedStoreIconWorkSignature == controller.storeIconObservationSignature())
    }

    private static func makeSnapshot(
        provider: UsageProvider,
        email: String,
        primaryUsedPercent: Double = 10,
        secondaryUsedPercent: Double = 20,
        updatedAt: Date = Date(timeIntervalSince1970: 100))
        -> UsageSnapshot
    {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: primaryUsedPercent,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: secondaryUsedPercent,
                windowMinutes: 10080,
                resetsAt: nil,
                resetDescription: nil),
            updatedAt: updatedAt,
            identity: ProviderIdentitySnapshot(
                providerID: provider,
                accountEmail: email,
                accountOrganization: nil,
                loginMethod: "plus"))
    }

    private static func makeCopilotSnapshot(budgetUsedPercent: Double) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: 10,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 20,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: nil),
            extraRateWindows: [
                NamedRateWindow(
                    id: "copilot-budget-agent",
                    title: "Budget - Copilot Agent Premium Requests",
                    window: RateWindow(
                        usedPercent: budgetUsedPercent,
                        windowMinutes: nil,
                        resetsAt: nil,
                        resetDescription: nil)),
            ],
            updatedAt: Date(timeIntervalSince1970: 100),
            identity: ProviderIdentitySnapshot(
                providerID: .copilot,
                accountEmail: "copilot@example.com",
                accountOrganization: nil,
                loginMethod: "individual"))
    }
}
