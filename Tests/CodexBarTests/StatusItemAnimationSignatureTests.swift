import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct StatusItemAnimationSignatureTests {
    @Test
    func merged_render_signature_changes_when_unified_icon_style_changes() {
        let suite = "StatusItemAnimationSignatureTests-merged-style-signature"
        let settings = testSettingsStore(suiteName: suite)
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .codex
        settings.menuBarShowsBrandIconWithPercent = false
        settings.syntheticAPIToken = "synthetic-test-token"

        let registry = ProviderRegistry.shared
        if let codexMeta = registry.metadata[.codex] {
            settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: true)
        }
        if let syntheticMeta = registry.metadata[.synthetic] {
            settings.setProviderEnabled(provider: .synthetic, metadata: syntheticMeta, enabled: true)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }

        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 50, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date()),
            provider: .codex)

        #expect(store.enabledProvidersForDisplay() == [.codex, .synthetic])
        #expect(store.enabledProviders() == [.codex, .synthetic])
        #expect(store.iconStyle == .combined)
        controller.applyIcon(phase: nil)
        let combinedSignature = controller.lastAppliedMergedIconRenderSignature

        if let syntheticMeta = registry.metadata[.synthetic] {
            settings.setProviderEnabled(provider: .synthetic, metadata: syntheticMeta, enabled: false)
        }

        #expect(store.enabledProvidersForDisplay() == [.codex])
        #expect(store.enabledProviders() == [.codex])
        #expect(store.iconStyle == .codex)
        controller.applyIcon(phase: nil)
        let codexSignature = controller.lastAppliedMergedIconRenderSignature

        #expect(combinedSignature != nil)
        #expect(codexSignature != nil)
        #expect(combinedSignature != codexSignature)
        #expect(codexSignature?.contains("style=codex") == true)
    }

    @Test
    func merged_antigravity_icon_resolves_quota_summary_with_provider_style() throws {
        let suite = "StatusItemAnimationSignatureTests-merged-antigravity-provider-style"
        let settings = testSettingsStore(suiteName: suite)
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .antigravity
        settings.menuBarShowsBrandIconWithPercent = false
        settings.usageBarsShowUsed = false
        settings.syntheticAPIToken = "synthetic-test-token"

        let registry = ProviderRegistry.shared
        if let antigravityMeta = registry.metadata[.antigravity] {
            settings.setProviderEnabled(provider: .antigravity, metadata: antigravityMeta, enabled: true)
        }
        if let syntheticMeta = registry.metadata[.synthetic] {
            settings.setProviderEnabled(provider: .synthetic, metadata: syntheticMeta, enabled: true)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }

        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 99, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
                secondary: RateWindow(usedPercent: 16, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
                tertiary: nil,
                extraRateWindows: [
                    NamedRateWindow(
                        id: "antigravity-quota-summary-gemini-5h",
                        title: "Gemini Session",
                        window: RateWindow(usedPercent: 1, windowMinutes: 300, resetsAt: nil, resetDescription: nil)),
                    NamedRateWindow(
                        id: "antigravity-quota-summary-gemini-weekly",
                        title: "Gemini Weekly",
                        window: RateWindow(
                            usedPercent: 99,
                            windowMinutes: 10080,
                            resetsAt: nil,
                            resetDescription: nil)),
                    NamedRateWindow(
                        id: "antigravity-quota-summary-3p-5h",
                        title: "Claude + GPT Session",
                        window: RateWindow(usedPercent: 2, windowMinutes: 300, resetsAt: nil, resetDescription: nil)),
                    NamedRateWindow(
                        id: "antigravity-quota-summary-3p-weekly",
                        title: "Claude + GPT Weekly",
                        window: RateWindow(
                            usedPercent: 16,
                            windowMinutes: 10080,
                            resetsAt: nil,
                            resetDescription: nil)),
                ],
                updatedAt: Date()),
            provider: .antigravity)

        #expect(store.iconStyle == .combined)
        #expect(controller.primaryProviderForUnifiedIcon() == .antigravity)

        controller.applyIcon(phase: nil)
        let signature = try #require(controller.lastAppliedMergedIconRenderSignature)

        #expect(signature.contains("provider=antigravity"))
        #expect(signature.contains("style=combined"))
        #expect(signature.contains("primary=98.000"))
        #expect(signature.contains("weekly=1.000"))
    }

    @Test
    func merged_mistral_icon_uses_monthly_plan_metric_when_selected() throws {
        let suite = "StatusItemAnimationSignatureTests-merged-mistral-monthly-plan"
        let settings = testSettingsStore(suiteName: suite)
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .mistral
        settings.menuBarShowsBrandIconWithPercent = false
        settings.usageBarsShowUsed = true
        settings.syntheticAPIToken = "synthetic-test-token"
        settings.setMenuBarMetricPreference(.monthlyPlan, for: .mistral)

        let registry = ProviderRegistry.shared
        if let mistralMeta = registry.metadata[.mistral] {
            settings.setProviderEnabled(provider: .mistral, metadata: mistralMeta, enabled: true)
        }
        if let syntheticMeta = registry.metadata[.synthetic] {
            settings.setProviderEnabled(provider: .synthetic, metadata: syntheticMeta, enabled: true)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }

        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                extraRateWindows: [
                    NamedRateWindow(
                        id: "mistral-monthly-plan",
                        title: "Monthly Plan",
                        window: RateWindow(usedPercent: 42, windowMinutes: nil, resetsAt: nil, resetDescription: nil)),
                ],
                updatedAt: Date()),
            provider: .mistral)

        #expect(store.iconStyle == .combined)
        #expect(controller.primaryProviderForUnifiedIcon() == .mistral)

        controller.applyIcon(phase: nil)
        let signature = try #require(controller.lastAppliedMergedIconRenderSignature)

        #expect(signature.contains("provider=mistral"))
        #expect(signature.contains("primary=42.000"))
        #expect(signature.contains("weekly=nil"))
    }

    @Test
    func mistral_pay_as_you_go_icon_ignores_balance_primary_percent() {
        let suite = "StatusItemAnimationSignatureTests-mistral-payg-balance-percent"
        let settings = testSettingsStore(suiteName: suite)
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.usageBarsShowUsed = true
        settings.setMenuBarMetricPreference(.automatic, for: .mistral)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }

        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 0,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: "$12.50"),
            secondary: nil,
            updatedAt: Date())

        let percents = controller.resolvedMenuBarIconPercents(
            provider: .mistral,
            snapshot: snapshot,
            style: .mistral,
            showUsed: true)

        #expect(percents?.primary == nil)
        #expect(percents?.secondary == nil)
    }

    @Test
    func merged_brand_percent_reapplies_title_when_cached_render_is_skipped() throws {
        let suite = "StatusItemAnimationSignatureTests-merged-brand-percent-title-restore"
        let settings = testSettingsStore(suiteName: suite)
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .codex
        settings.menuBarShowsBrandIconWithPercent = true
        settings.menuBarDisplayMode = .percent
        settings.usageBarsShowUsed = false
        settings.syntheticAPIToken = "synthetic-test-token"

        let registry = ProviderRegistry.shared
        if let codexMeta = registry.metadata[.codex] {
            settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: true)
        }
        if let syntheticMeta = registry.metadata[.synthetic] {
            settings.setProviderEnabled(provider: .synthetic, metadata: syntheticMeta, enabled: true)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }

        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 23, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        store._setSnapshotForTesting(snapshot, provider: .codex)

        let displayText = try #require(controller.menuBarDisplayText(for: .codex, snapshot: snapshot))
        let expectedTitle = StatusItemController.buttonTitle(displayText, hasImage: true)
        controller.applyIcon(phase: nil)
        let button = try #require(controller.statusItem.button)
        #expect(button.title == expectedTitle)
        #expect(button.imagePosition == .imageLeft)

        button.title = ""
        button.imagePosition = .imageOnly

        let skipped = controller.applyIcon(phase: nil)

        #expect(skipped)
        #expect(button.title == expectedTitle)
        #expect(button.imagePosition == .imageLeft)
    }

    @Test
    func merged_icon_only_content_repairs_stale_title_when_cached_render_is_skipped() throws {
        let suite = "StatusItemAnimationSignatureTests-merged-icon-only-title-restore"
        let settings = testSettingsStore(suiteName: suite)
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .codex
        settings.menuBarShowsBrandIconWithPercent = false

        let registry = ProviderRegistry.shared
        if let codexMeta = registry.metadata[.codex] {
            settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: true)
        }
        if let claudeMeta = registry.metadata[.claude] {
            settings.setProviderEnabled(provider: .claude, metadata: claudeMeta, enabled: true)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }

        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 23, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date()),
            provider: .codex)

        controller.applyIcon(phase: nil)
        let button = try #require(controller.statusItem.button)
        button.title = " stale"
        button.imagePosition = .imageLeft

        let skipped = controller.applyIcon(phase: nil)

        #expect(skipped)
        #expect(button.title.isEmpty)
        #expect(button.imagePosition == .imageOnly)
    }

    @Test
    func inactive_display_contrast_embeds_the_brand_and_restores_standard_content_when_disabled() throws {
        let suite = "StatusItemAnimationSignatureTests-inactive-display-contrast"
        let settings = testSettingsStore(suiteName: suite)
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .codex
        settings.menuBarShowsBrandIconWithPercent = true
        settings.menuBarHighContrastOnInactiveDisplays = true
        settings.menuBarDisplayMode = .percent
        settings.usageBarsShowUsed = false

        let registry = ProviderRegistry.shared
        if let codexMeta = registry.metadata[.codex] {
            settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: true)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }

        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 23, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        store._setSnapshotForTesting(snapshot, provider: .codex)

        let displayText = try #require(controller.menuBarDisplayText(for: .codex, snapshot: snapshot))
        let expectedTitle = StatusItemController.buttonTitle(displayText, hasImage: true)
        controller.applyIcon(phase: nil)
        let button = try #require(controller.statusItem.button)

        #expect(button.image == nil)
        #expect(button.imagePosition == .noImage)
        #expect(button.attributedTitle.string == "\u{FFFC}\(expectedTitle)")
        #expect(button.attributedTitle.attribute(.attachment, at: 0, effectiveRange: nil) is NSTextAttachment)

        #expect(controller.prepareButtonForImageOnlyCacheHit(button))
        #expect(button.image == nil)
        #expect(button.imagePosition == .noImage)
        #expect(button.attributedTitle.string == "\u{FFFC}\(expectedTitle)")
        #expect(button.attributedTitle.attribute(.attachment, at: 0, effectiveRange: nil) is NSTextAttachment)

        button.attributedTitle = NSAttributedString()
        #expect(!controller.prepareButtonForImageOnlyCacheHit(button))

        controller.applyIcon(phase: nil)
        #expect(button.attributedTitle.string == "\u{FFFC}\(expectedTitle)")
        #expect(button.attributedTitle.attribute(.attachment, at: 0, effectiveRange: nil) is NSTextAttachment)

        settings.menuBarIconStyle = .critters
        let critterSkipped = controller.applyIcon(phase: nil)

        #expect(!critterSkipped)
        #expect(button.image != nil)
        #expect(button.title.isEmpty)
        #expect(button.imagePosition == .imageOnly)
        #expect(button.attributedTitle.length == 0)

        settings.menuBarIconStyle = .iconAndPercent
        controller.applyIcon(phase: nil)

        #expect(button.image == nil)
        #expect(button.imagePosition == .noImage)
        #expect(button.attributedTitle.string == "\u{FFFC}\(expectedTitle)")
        #expect(button.attributedTitle.attribute(.attachment, at: 0, effectiveRange: nil) is NSTextAttachment)

        settings.menuBarHighContrastOnInactiveDisplays = false
        let skipped = controller.applyIcon(phase: nil)

        #expect(!skipped)
        #expect(button.image != nil)
        #expect(button.title == expectedTitle)
        #expect(button.imagePosition == .imageLeft)
        #expect(button.attributedTitle.attribute(.attachment, at: 0, effectiveRange: nil) == nil)
    }

    @Test
    func merged_icon_render_defers_while_merged_menu_is_tracking() async throws {
        let suite = "StatusItemAnimationSignatureTests-merged-icon-defers-during-tracking"
        let settings = testSettingsStore(suiteName: suite)
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .codex
        settings.menuBarShowsBrandIconWithPercent = false
        settings.syntheticAPIToken = "synthetic-test-token"

        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            settings.setProviderEnabled(
                provider: provider,
                metadata: metadata,
                enabled: provider == .codex || provider == .synthetic)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }
        controller.menuRefreshEnabledOverrideForTesting = true

        func snapshot(usedPercent: Double) -> UsageSnapshot {
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: usedPercent,
                    windowMinutes: nil,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: nil,
                updatedAt: Date())
        }

        store._setSnapshotForTesting(snapshot(usedPercent: 20), provider: .codex)
        controller.updateIcons()
        #expect(controller.animationDriver == nil)
        controller.applyIcon(phase: nil)
        let initialSignature = try #require(controller.lastAppliedMergedIconRenderSignature)

        let menu = controller.makeMenu()
        controller.mergedMenu = menu
        controller.statusItem.menu = menu
        controller.menuWillOpen(menu)
        #expect(controller.isMergedMenuOpen)

        store._setSnapshotForTesting(nil, provider: .codex)
        controller.updateIcons()
        #expect(controller.animationDriver != nil)
        #expect(controller.deferredMergedIconRenderAfterTracking)

        store._setSnapshotForTesting(snapshot(usedPercent: 80), provider: .codex)
        controller.updateIcons()
        #expect(controller.animationDriver == nil)
        #expect(controller.deferredMergedIconRenderAfterTracking)
        #expect(controller.lastAppliedMergedIconRenderSignature == initialSignature)

        controller.startQuotaWarningFlash(provider: .codex)
        #expect(controller.lastAppliedMergedIconRenderSignature?.contains("warningFlash=1") == true)

        let quotaWarningTask = controller.quotaWarningFlashTasks[.codex]
        controller.clearExpiredQuotaWarningFlash(provider: .codex, now: .distantFuture)
        quotaWarningTask?.cancel()
        #expect(controller.lastAppliedMergedIconRenderSignature?.contains("warningFlash=0") == true)

        controller.menuDidClose(menu)

        #expect(!controller.deferredMergedIconRenderAfterTracking)
        #expect(controller.lastAppliedMergedIconRenderSignature?.contains("warningFlash=0") == true)

        controller.menuWillOpen(menu)
        settings.selectedMenuProvider = .synthetic
        #expect(controller.primaryProviderForUnifiedIcon() == .synthetic)
        #expect(controller.lastAppliedMergedIconRenderSignature?.contains("provider=codex") == true)

        controller.startQuotaWarningFlash(provider: .codex)
        let switchedProviderWarningTask = controller.quotaWarningFlashTasks[.codex]
        #expect(controller.lastAppliedMergedIconRenderSignature?.contains("provider=synthetic") == true)
        controller.clearExpiredQuotaWarningFlash(provider: .codex, now: .distantFuture)
        switchedProviderWarningTask?.cancel()
        controller.menuDidClose(menu)

        settings.selectedMenuProvider = .codex
        for _ in 0..<10 where controller.primaryProviderForUnifiedIcon() != .codex {
            await Task.yield()
        }

        controller.menuWillOpen(menu)
        store._setSnapshotForTesting(nil, provider: .codex)
        controller.updateAnimationState()
        controller.applyIcon(phase: controller.animationPhase)
        #expect(controller.animationDriver != nil)
        #expect(controller.deferredMergedIconRenderAfterTracking)

        controller.animationDriver?.stop()
        controller.animationDriver = nil
        controller.animationPhase = 0
        controller.menuDidClose(menu)

        #expect(controller.animationDriver == nil)
        #expect(controller.lastAppliedMergedIconRenderSignature?.contains("primary=nil") == true)
    }

    @Test
    func merged_fallback_provider_follows_enabled_provider_order() {
        let suite = "StatusItemAnimationSignatureTests-merged-provider-order"
        let settings = testSettingsStore(suiteName: suite)
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.menuBarShowsBrandIconWithPercent = false
        settings.syntheticAPIToken = "synthetic-test-token"
        settings.setProviderOrder([.synthetic, .codex])

        let registry = ProviderRegistry.shared
        if let codexMeta = registry.metadata[.codex] {
            settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: true)
        }
        if let syntheticMeta = registry.metadata[.synthetic] {
            settings.setProviderEnabled(provider: .synthetic, metadata: syntheticMeta, enabled: true)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }

        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 50, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        store._setSnapshotForTesting(snapshot, provider: .codex)
        store._setSnapshotForTesting(snapshot, provider: .synthetic)

        controller.applyIcon(phase: nil)

        #expect(store.enabledProviders().prefix(2) == [.synthetic, .codex])
        #expect(controller.lastAppliedMergedIconRenderSignature?.contains("provider=synthetic") == true)
    }

    @Test
    func merged_icon_status_indicator_follows_rendered_provider() throws {
        let suite = "StatusItemAnimationSignatureTests-merged-status-provider-scope"
        let settings = testSettingsStore(suiteName: suite)
        settings.statusChecksEnabled = true
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .codex
        settings.menuBarShowsBrandIconWithPercent = false

        let registry = ProviderRegistry.shared
        let codexMeta = try #require(registry.metadata[.codex])
        let claudeMeta = try #require(registry.metadata[.claude])
        settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: true)
        settings.setProviderEnabled(provider: .claude, metadata: claudeMeta, enabled: true)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }

        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 50, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        store._setSnapshotForTesting(snapshot, provider: .codex)
        store._setSnapshotForTesting(snapshot, provider: .claude)
        store.statuses[.claude] = ProviderStatus(
            indicator: .major,
            description: "Claude status issue",
            updatedAt: Date(timeIntervalSince1970: 20))

        controller.applyIcon(phase: nil)

        #expect(controller.primaryProviderForUnifiedIcon() == .codex)
        #expect(controller.lastAppliedMergedIconRenderSignature?.contains("provider=codex") == true)
        #expect(controller.lastAppliedMergedIconRenderSignature?.contains("status=none") == true)

        settings.selectedMenuProvider = .claude
        controller.applyIcon(phase: nil)

        #expect(controller.primaryProviderForUnifiedIcon() == .claude)
        #expect(controller.lastAppliedMergedIconRenderSignature?.contains("provider=claude") == true)
        #expect(controller.lastAppliedMergedIconRenderSignature?.contains("status=major") == true)
    }

    @Test
    func highest_usage_icon_ranks_only_overview_providers() throws {
        let suite = "StatusItemAnimationSignatureTests-highest-usage-overview-subset"
        let settings = testSettingsStore(suiteName: suite)
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.menuBarShowsHighestUsage = true

        let registry = ProviderRegistry.shared
        let codexMeta = try #require(registry.metadata[.codex])
        let claudeMeta = try #require(registry.metadata[.claude])
        settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: true)
        settings.setProviderEnabled(provider: .claude, metadata: claudeMeta, enabled: true)

        let fetcher = UsageFetcher()
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        settings.setMergedOverviewProviderSelection(
            provider: .claude,
            isSelected: false,
            activeProviders: store.enabledProvidersForDisplay())
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }

        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 25, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date()),
            provider: .codex)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 80, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date()),
            provider: .claude)

        #expect(store.providerWithHighestUsage()?.provider == .claude)
        #expect(controller.primaryProviderForUnifiedIcon() == .codex)
    }

    @Test(arguments: [nil, 100.0] as [Double?])
    func highest_usage_icon_keeps_nonempty_overview_authoritative_when_unrankable(
        overviewUsedPercent: Double?) throws
    {
        let suite = "StatusItemAnimationSignatureTests-highest-usage-overview-fallback"
        let settings = testSettingsStore(suiteName: suite)
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.menuBarShowsHighestUsage = true
        settings.selectedMenuProvider = .claude
        settings.mergedMenuLastSelectedWasOverview = false

        let registry = ProviderRegistry.shared
        let codexMeta = try #require(registry.metadata[.codex])
        let claudeMeta = try #require(registry.metadata[.claude])
        settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: true)
        settings.setProviderEnabled(provider: .claude, metadata: claudeMeta, enabled: true)

        let fetcher = UsageFetcher()
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        settings.setMergedOverviewProviderSelection(
            provider: .claude,
            isSelected: false,
            activeProviders: store.enabledProvidersForDisplay())
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }

        if let overviewUsedPercent {
            store._setSnapshotForTesting(
                UsageSnapshot(
                    primary: RateWindow(
                        usedPercent: overviewUsedPercent,
                        windowMinutes: nil,
                        resetsAt: nil,
                        resetDescription: nil),
                    secondary: nil,
                    updatedAt: Date()),
                provider: .codex)
        }
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 80, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date()),
            provider: .claude)

        #expect(store.providerWithHighestUsage(candidateProviders: [.codex]) == nil)
        #expect(controller.primaryProviderForUnifiedIcon() == .codex)
    }

    @Test
    func highest_usage_icon_allows_broad_fallback_for_explicit_empty_overview() throws {
        let suite = "StatusItemAnimationSignatureTests-highest-usage-empty-overview"
        let settings = testSettingsStore(suiteName: suite)
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.menuBarShowsHighestUsage = true
        settings.selectedMenuProvider = .claude

        let registry = ProviderRegistry.shared
        let codexMeta = try #require(registry.metadata[.codex])
        let claudeMeta = try #require(registry.metadata[.claude])
        settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: true)
        settings.setProviderEnabled(provider: .claude, metadata: claudeMeta, enabled: true)

        let fetcher = UsageFetcher()
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let activeProviders = store.enabledProvidersForDisplay()
        settings.setMergedOverviewProviderSelection(
            provider: .codex,
            isSelected: false,
            activeProviders: activeProviders)
        settings.setMergedOverviewProviderSelection(
            provider: .claude,
            isSelected: false,
            activeProviders: activeProviders)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }

        #expect(settings.resolvedMergedOverviewProviders(activeProviders: store.enabledProvidersForDisplay()) == [])
        #expect(controller.primaryProviderForUnifiedIcon() == .claude)
    }

    @Test
    func merged_icon_follows_overview_provider_order_when_first_overview_provider_is_loading() {
        let suite = "StatusItemAnimationSignatureTests-merged-overview-provider-order"
        let settings = testSettingsStore(suiteName: suite)
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .codex
        settings.mergedMenuLastSelectedWasOverview = true
        settings.menuBarShowsBrandIconWithPercent = false
        settings.setProviderOrder([.cursor, .codex, .claude])

        let registry = ProviderRegistry.shared
        if let cursorMeta = registry.metadata[.cursor] {
            settings.setProviderEnabled(provider: .cursor, metadata: cursorMeta, enabled: true)
        }
        if let codexMeta = registry.metadata[.codex] {
            settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: true)
        }
        if let claudeMeta = registry.metadata[.claude] {
            settings.setProviderEnabled(provider: .claude, metadata: claudeMeta, enabled: true)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }

        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 50, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        store._setSnapshotForTesting(snapshot, provider: .codex)
        store._setSnapshotForTesting(snapshot, provider: .claude)

        #expect(store.enabledProvidersForDisplay().prefix(3) == [.cursor, .codex, .claude])
        #expect(settings.resolvedMergedOverviewProviders(activeProviders: store.enabledProvidersForDisplay()) == [
            .cursor,
            .codex,
            .claude,
        ])

        controller.applyIcon(phase: nil)

        #expect(controller.lastAppliedMergedIconRenderSignature?.contains("provider=cursor") == true)
    }

    @Test
    func split_provider_icon_skips_unchanged_render_signature() throws {
        let suite = "StatusItemAnimationSignatureTests-split-provider-signature"
        let settings = testSettingsStore(suiteName: suite)
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.menuBarShowsBrandIconWithPercent = false

        if let codexMeta = ProviderRegistry.shared.metadata[.codex] {
            settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: true)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }

        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 25, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date()),
            provider: .codex)

        #expect(controller.applyIcon(for: .codex, phase: nil) == false)
        let button = try #require(controller.statusItems[.codex]?.button)
        button.title = " stale"
        button.imagePosition = .imageLeft

        #expect(controller.applyIcon(for: .codex, phase: nil) == true)
        #expect(button.title.isEmpty)
        #expect(button.imagePosition == .imageOnly)

        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 50, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date()),
            provider: .codex)

        #expect(controller.applyIcon(for: .codex, phase: nil) == false)
    }
}
