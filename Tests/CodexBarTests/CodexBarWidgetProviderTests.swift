import Foundation
import Testing
@testable import CodexBarCore
@testable import CodexBarWidget

struct CodexBarWidgetProviderTests {
    @Test
    func usage_display_follows_remaining_and_used_preference() {
        #expect(WidgetUsageDisplay.percent(fromRemaining: 48, showUsed: false) == 48)
        #expect(WidgetUsageDisplay.percent(fromRemaining: 48, showUsed: true) == 52)
        #expect(WidgetUsageDisplay.percent(fromRemaining: nil, showUsed: true) == nil)
    }

    @Test
    func small_widget_falls_back_to_local_cost_when_quota_rows_are_unavailable() {
        let tokenUsage = WidgetSnapshot.TokenUsageSummary(
            sessionCostUSD: 1.25,
            sessionTokens: 4200,
            last30DaysCostUSD: 12.50,
            last30DaysTokens: 42000,
            currencyCode: "USD",
            sessionLabel: "Today",
            last30DaysLabel: "30d")
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .claude,
            updatedAt: Date(),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            usageRows: [],
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: tokenUsage,
            dailyUsage: [])
        let windowedEntry = WidgetSnapshot.ProviderEntry(
            provider: .claude,
            updatedAt: Date(),
            primary: RateWindow(usedPercent: 25, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            usageRows: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: tokenUsage,
            dailyUsage: [])

        #expect(WidgetUsageRow.compactTokenUsage(for: entry)?.sessionTokens == 4200)
        #expect(WidgetUsageRow.compactTokenUsage(for: windowedEntry) == nil)
    }

    @Test
    func small_widget_limits_custom_usage_rows() {
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .antigravity,
            updatedAt: Date(),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            usageRows: [
                WidgetSnapshot.WidgetUsageRowSnapshot(id: "one", title: "One", percentLeft: 90),
                WidgetSnapshot.WidgetUsageRowSnapshot(id: "two", title: "Two", percentLeft: 80),
                WidgetSnapshot.WidgetUsageRowSnapshot(id: "three", title: "Three", percentLeft: 70),
                WidgetSnapshot.WidgetUsageRowSnapshot(id: "four", title: "Four", percentLeft: 60),
            ],
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        #expect(WidgetUsageRow.rows(for: entry, limit: 2).map(\.id) == ["one", "two"])
        #expect(WidgetUsageRow.rows(for: entry).count == 4)
    }

    @Test
    func small_antigravity_widget_keeps_one_row_per_quota_family() {
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .antigravity,
            updatedAt: Date(),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            usageRows: [
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "antigravity-quota-summary-gemini-session",
                    title: "Gemini Models Five Hour Limit",
                    percentLeft: 80),
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "antigravity-quota-summary-gemini-weekly",
                    title: "Gemini Models Weekly Limit",
                    percentLeft: 20),
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "antigravity-quota-summary-third-party-session",
                    title: "Claude and GPT models Five Hour Limit",
                    percentLeft: 5),
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "antigravity-quota-summary-third-party-weekly",
                    title: "Claude and GPT models Weekly Limit",
                    percentLeft: 60),
            ],
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        let rows = WidgetUsageRow.rows(for: entry, limit: 2)

        #expect(rows.map(\.title) == ["Gemini Models Weekly Limit", "Claude and GPT models Five Hour Limit"])
        #expect(rows.compactMap(\.percentLeft) == [20, 5])
        #expect(WidgetUsageRow.smallWidgetRowLimit(for: entry) == 2)
        #expect(WidgetUsageRow.mediumWidgetRowLimit(for: entry) == 3)
        let mediumRows = WidgetUsageRow.rows(
            for: entry,
            limit: WidgetUsageRow.mediumWidgetRowLimit(for: entry))
        #expect(mediumRows.map(\.title) == [
            "Gemini Models Weekly Limit",
            "Claude and GPT models Five Hour Limit",
            "Claude and GPT models Weekly Limit",
        ])
    }

    @Test
    func small_antigravity_widget_keeps_claude_gpt_family_when_fallback_rows_are_more_constrained() {
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .antigravity,
            updatedAt: Date(),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            usageRows: [
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "antigravity-quota-summary-gemini-5h",
                    title: "Gemini Models Five Hour Limit",
                    percentLeft: 40),
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "antigravity-quota-summary-gemini-weekly",
                    title: "Gemini Models Weekly Limit",
                    percentLeft: 70),
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "antigravity-quota-summary-3p-5h",
                    title: "Claude and GPT models Five Hour Limit",
                    percentLeft: 60),
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "antigravity-quota-summary-other-5h",
                    title: "Other Five Hour Limit",
                    percentLeft: 1),
            ],
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        let rows = WidgetUsageRow.rows(for: entry, limit: 2)

        #expect(rows.map(\.id) == [
            "antigravity-quota-summary-gemini-5h",
            "antigravity-quota-summary-3p-5h",
        ])
    }

    @Test
    func small_widget_preserves_tertiary_rows_for_other_providers() {
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .cursor,
            updatedAt: Date(),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            usageRows: [
                WidgetSnapshot.WidgetUsageRowSnapshot(id: "one", title: "One", percentLeft: 90),
                WidgetSnapshot.WidgetUsageRowSnapshot(id: "two", title: "Two", percentLeft: 80),
                WidgetSnapshot.WidgetUsageRowSnapshot(id: "three", title: "Three", percentLeft: 70),
            ],
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        let limit = WidgetUsageRow.smallWidgetRowLimit(for: entry)

        #expect(limit == nil)
        #expect(WidgetUsageRow.rows(for: entry, limit: limit).map(\.id) == ["one", "two", "three"])
    }

    @Test
    func small_antigravity_widget_prefers_known_quota_rows() {
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .antigravity,
            updatedAt: Date(),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            usageRows: [
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "antigravity-quota-summary-gemini-session",
                    title: "Gemini Models Five Hour Limit",
                    percentLeft: nil),
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "antigravity-quota-summary-gemini-weekly",
                    title: "Gemini Models Weekly Limit",
                    percentLeft: 100),
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "antigravity-quota-summary-third-party-session",
                    title: "Claude and GPT models Five Hour Limit",
                    percentLeft: 80),
            ],
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        let rows = WidgetUsageRow.rows(for: entry, limit: 2)

        #expect(rows.map(\.title) == ["Gemini Models Weekly Limit", "Claude and GPT models Five Hour Limit"])
    }

    @Test
    func small_antigravity_widget_keeps_nonstandard_quota_groups_visible() {
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .antigravity,
            updatedAt: Date(),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            usageRows: [
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "antigravity-quota-summary-other-session",
                    title: "Other Session",
                    percentLeft: 70),
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "antigravity-quota-summary-other-weekly",
                    title: "Other Weekly",
                    percentLeft: 40),
            ],
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        let rows = WidgetUsageRow.rows(for: entry, limit: 2)

        #expect(rows.map(\.title) == ["Other Weekly", "Other Session"])
    }

    @Test
    func provider_choice_supports_alibaba() {
        #expect(ProviderChoice(provider: .alibaba) == .alibaba)
        #expect(ProviderChoice.alibaba.provider == .alibaba)
    }

    @Test
    func provider_choice_supports_alibaba_token_plan() {
        #expect(ProviderChoice(provider: .alibabatokenplan) == .alibabatokenplan)
        #expect(ProviderChoice.alibabatokenplan.provider == .alibabatokenplan)
    }

    @Test
    func provider_choice_supports_opencode_go() {
        #expect(ProviderChoice(provider: .opencodego) == .opencodego)
        #expect(ProviderChoice.opencodego.provider == .opencodego)
    }

    @Test
    func provider_choice_supports_devin() {
        #expect(ProviderChoice(provider: .devin) == .devin)
        #expect(ProviderChoice.devin.provider == .devin)
    }

    @Test
    func widget_entry_carries_devin_overage_balance_through_providerCost() {
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .devin,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [],
            providerCost: ProviderCostSnapshot(
                used: 48.0,
                limit: 0,
                currencyCode: "USD",
                period: "Extra usage balance",
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        let encoded = try? JSONEncoder().encode(entry)
        #expect(encoded != nil)
        let decoded = encoded.flatMap { try? JSONDecoder().decode(WidgetSnapshot.ProviderEntry.self, from: $0) }
        #expect(decoded?.providerCost?.period == "Extra usage balance")
        #expect(decoded?.providerCost?.used == 48.0)
        #expect(decoded?.providerCost?.limit == 0)
        #expect(decoded?.provider == .devin)
    }

    @Test
    func widget_balance_formatter_renders_devin_extra_usage_balance() {
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .devin,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [],
            providerCost: ProviderCostSnapshot(
                used: 48.0,
                limit: 0,
                currencyCode: "USD",
                period: "Extra usage balance",
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        let line = WidgetBalanceFormatter.extraUsageBalance(for: entry)
        #expect(line?.title == "Extra usage")
        #expect(line?.value.hasPrefix("Balance: ") == true)
        #expect(line?.value.contains("48") == true)
    }

    @Test
    func compact_credits_render_Devin_extra_usage_balance() {
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .devin,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [],
            providerCost: ProviderCostSnapshot(
                used: 48.0,
                limit: 0,
                currencyCode: "USD",
                period: "Extra usage balance",
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)))

        let display = CompactMetricFormatter.display(for: entry, metric: .credits)

        #expect(display.value.contains("48"))
        #expect(display.label == "Extra usage balance")
        #expect(display.detail == nil)
    }

    @Test
    func widget_balance_formatter_does_not_leak_another_provider_balance() {
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .factory,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [],
            providerCost: ProviderCostSnapshot(
                used: 12.0,
                limit: 100.0,
                currencyCode: "USD",
                period: "Extra usage balance",
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        #expect(WidgetBalanceFormatter.extraUsageBalance(for: entry) == nil)
    }

    @Test
    func provider_choice_supports_Mistral() {
        #expect(ProviderChoice(provider: .mistral) == .mistral)
        #expect(ProviderChoice.mistral.provider == .mistral)
    }

    @Test
    func provider_choice_supports_Kimi() {
        #expect(ProviderChoice(provider: .kimi) == .kimi)
        #expect(ProviderChoice.kimi.provider == .kimi)
    }

    @Test
    func compact_Kimi_widgets_keep_established_row_fit_while_large_widgets_show_all_quotas() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .kimi,
            updatedAt: now,
            primary: RateWindow(usedPercent: 25, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 50, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            usageRows: [
                WidgetSnapshot.WidgetUsageRowSnapshot(id: "primary", title: "Weekly", percentLeft: 75),
                WidgetSnapshot.WidgetUsageRowSnapshot(id: "secondary", title: "Rate Limit", percentLeft: 50),
                WidgetSnapshot.WidgetUsageRowSnapshot(id: "kimi-monthly", title: "Monthly", percentLeft: 25),
                WidgetSnapshot.WidgetUsageRowSnapshot(id: "kimi-code-7d", title: "Code 7-day", percentLeft: 90),
            ],
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        let smallRows = WidgetUsageRow.rows(
            for: entry,
            limit: WidgetUsageRow.smallWidgetRowLimit(for: entry))
        let mediumRows = WidgetUsageRow.rows(
            for: entry,
            limit: WidgetUsageRow.mediumWidgetRowLimit(for: entry))
        let largeRows = WidgetUsageRow.rows(for: entry)

        #expect(WidgetUsageRow.smallWidgetRowLimit(for: entry) == 3)
        #expect(WidgetUsageRow.mediumWidgetRowLimit(for: entry) == 3)
        #expect(smallRows.map(\.id) == ["primary", "secondary", "kimi-monthly"])
        #expect(mediumRows == smallRows)
        #expect(largeRows.map(\.id) == ["primary", "secondary", "kimi-monthly", "kimi-code-7d"])
    }

    @Test
    func provider_choice_excludes_unsupported_Chutes_widgets() {
        #expect(ProviderChoice(provider: .chutes) == nil)
        #expect(ProviderChoice(provider: .sub2api) == nil)
    }

    @Test
    func supported_providers_fall_back_to_codex_when_snapshot_is_empty() {
        let snapshot = WidgetSnapshot(entries: [], enabledProviders: [], generatedAt: Date())

        #expect(CodexBarSwitcherTimelineProvider.supportedProviders(from: snapshot) == [.codex])
    }

    @Test
    func supported_providers_keep_alibaba_when_it_is_the_only_enabled_provider() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .alibaba,
            updatedAt: now,
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        let snapshot = WidgetSnapshot(entries: [entry], enabledProviders: [.alibaba], generatedAt: now)

        #expect(CodexBarSwitcherTimelineProvider.supportedProviders(from: snapshot) == [.alibaba])
    }

    @Test
    func supported_providers_keep_alibaba_token_plan_when_it_is_the_only_enabled_provider() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .alibabatokenplan,
            updatedAt: now,
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        let snapshot = WidgetSnapshot(entries: [entry], enabledProviders: [.alibabatokenplan], generatedAt: now)

        #expect(CodexBarSwitcherTimelineProvider.supportedProviders(from: snapshot) == [.alibabatokenplan])
    }

    @Test
    func supported_providers_keep_Mistral_when_it_is_the_only_enabled_provider() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .mistral,
            updatedAt: now,
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        let snapshot = WidgetSnapshot(entries: [entry], enabledProviders: [.mistral], generatedAt: now)

        #expect(CodexBarSwitcherTimelineProvider.supportedProviders(from: snapshot) == [.mistral])
    }

    @Test
    func supported_providers_keep_Kimi_when_it_is_the_only_enabled_provider() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .kimi,
            updatedAt: now,
            primary: RateWindow(usedPercent: 25, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 50, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        let snapshot = WidgetSnapshot(entries: [entry], enabledProviders: [.kimi], generatedAt: now)

        #expect(CodexBarSwitcherTimelineProvider.supportedProviders(from: snapshot) == [.kimi])
    }

    @Test
    func codex_weekly_only_widget_rows_omit_session() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .codex,
            updatedAt: now,
            primary: nil,
            secondary: RateWindow(usedPercent: 25, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        let rows = WidgetUsageRow.rows(for: entry)

        #expect(rows.count == 1)
        #expect(rows.first?.title == "Weekly")
        #expect(rows.first?.percentLeft == 75)
    }

    @Test
    func codex_widget_usage_rows_keep_code_review_separate_from_rate_rows() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .codex,
            updatedAt: now,
            primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 25, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: 60,
            tokenUsage: nil,
            dailyUsage: [])

        let rows = WidgetUsageRow.rows(for: entry)

        #expect(rows.map(\.title) == ["Session", "Weekly"])
        #expect(rows.count == 2)
        #expect(!rows.contains { $0.title == "Code review" })
    }

    @Test
    func widget_usage_rows_prefer_projected_rows_over_legacy_slots() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .codex,
            updatedAt: now,
            primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 25, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            usageRows: [
                WidgetSnapshot.WidgetUsageRowSnapshot(id: "weekly", title: "Weekly", percentLeft: 75),
            ],
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        let rows = WidgetUsageRow.rows(for: entry)

        #expect(rows == [WidgetUsageRow(id: "weekly", title: "Weekly", percentLeft: 75)])
    }

    @Test
    func codex_widget_session_cap_lifts_at_weekly_reset_without_a_new_snapshot() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let weeklyReset = now.addingTimeInterval(3600)
        let sessionWindow = RateWindow(
            usedPercent: 1,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(1800),
            resetDescription: nil)
        let weeklyWindow = RateWindow(
            usedPercent: 100,
            windowMinutes: 10080,
            resetsAt: weeklyReset,
            resetDescription: nil)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .codex,
            updatedAt: now.addingTimeInterval(-7200),
            primary: sessionWindow,
            secondary: weeklyWindow,
            tertiary: nil,
            usageRows: [
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "session",
                    title: "Session",
                    percentLeft: 99,
                    window: sessionWindow),
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "weekly",
                    title: "Weekly",
                    percentLeft: 0,
                    window: weeklyWindow),
            ],
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        let capped = WidgetUsageRow.rows(for: entry, now: now)
        let reset = WidgetUsageRow.rows(for: entry, now: weeklyReset)

        #expect(capped.map(\.percentLeft) == [0, 0])
        #expect(reset.map(\.percentLeft) == [99, 0])
    }

    @Test
    func legacy_widget_usage_rows_use_antigravity_grouped_slots() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .antigravity,
            updatedAt: now,
            primary: RateWindow(usedPercent: 10, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            tertiary: RateWindow(usedPercent: 30, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        let rows = WidgetUsageRow.rows(for: entry)

        #expect(rows.map(\.id) == ["primary", "secondary"])
        #expect(rows.map(\.title) == ["Gemini Models", "Claude and GPT"])
        #expect(rows.compactMap(\.percentLeft) == [90, 80])
    }

    @Test
    func widget_configuration_intents_default_to_codex_and_credits() {
        let providerIntent = ProviderSelectionIntent()
        let compactIntent = CompactMetricSelectionIntent()
        let burnIntent = BurnDownSelectionIntent()
        let combinedBurnIntent = BurnProviderSelectionIntent()

        #expect(providerIntent.provider == .codex)
        #expect(compactIntent.provider == .codex)
        #expect(compactIntent.metric == .credits)
        #expect(burnIntent.provider == .codex)
        #expect(burnIntent.window == .session)
        #expect(combinedBurnIntent.provider == .codex)
    }

    @Test
    func burn_down_uses_an_exact_provider_entry() {
        let snapshot = Self.burnSnapshot(provider: .claude, primaryUsed: 20, secondaryUsed: 30)

        #expect(BurnDownState(snapshot: snapshot, provider: .codex, selection: .session) == nil)
        #expect(BurnDownState(snapshot: snapshot, provider: .claude, selection: .session) != nil)
    }

    @Test
    func codex_exhausted_weekly_cap_blocks_the_session_chart_until_weekly_reset() throws {
        let weeklyReset = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = Self.burnSnapshot(
            provider: .codex,
            primaryUsed: 80,
            secondaryUsed: 100,
            primaryReset: weeklyReset.addingTimeInterval(-3600),
            secondaryReset: weeklyReset)
        let state = try #require(BurnDownState(snapshot: snapshot, provider: .codex, selection: .session))

        #expect(state.secondaryGloballyCapsPrimary)
        #expect(state.primaryWindow?.remainingPercent == 0)
        #expect(state.blankPrimaryChart)
        #expect(state.selectedResetOverride == weeklyReset)
    }

    @Test
    func gemini_exhausted_secondary_window_does_not_block_the_independent_primary() throws {
        let primaryReset = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = Self.burnSnapshot(
            provider: .gemini,
            primaryUsed: 20,
            secondaryUsed: 100,
            primaryReset: primaryReset,
            secondaryReset: primaryReset.addingTimeInterval(-3600))
        let state = try #require(BurnDownState(snapshot: snapshot, provider: .gemini, selection: .session))

        #expect(!state.secondaryGloballyCapsPrimary)
        #expect(state.primaryWindow?.remainingPercent == 80)
        #expect(!state.blankPrimaryChart)
        #expect(state.selectedResetOverride == nil)
    }

    @Test
    func independent_secondary_reset_never_overrides_primary_reset() throws {
        let primaryReset = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = Self.burnSnapshot(
            provider: .gemini,
            primaryUsed: 20,
            secondaryUsed: 30,
            primaryReset: primaryReset,
            secondaryReset: primaryReset.addingTimeInterval(-3600))
        let state = try #require(BurnDownState(snapshot: snapshot, provider: .gemini, selection: .session))

        #expect(state.selectedWindow?.resetsAt == primaryReset)
        #expect(state.selectedResetOverride == nil)
    }

    @Test
    func burn_down_preview_includes_session_and_weekly_windows() throws {
        let snapshot = WidgetPreviewData.snapshot()

        let session = try #require(BurnDownState(snapshot: snapshot, provider: .codex, selection: .session))
        let weekly = try #require(BurnDownState(snapshot: snapshot, provider: .codex, selection: .weekly))

        #expect(session.selectedWindow?.windowMinutes == 300)
        #expect(weekly.selectedWindow?.windowMinutes == 10080)
    }

    @Test
    func burn_down_selection_does_not_fall_back_to_another_window() throws {
        let weeklyOnly = Self.burnSnapshot(provider: .codex, primaryUsed: nil, secondaryUsed: 30)
        let sessionOnly = Self.burnSnapshot(provider: .codex, primaryUsed: 20, secondaryUsed: nil)
        let weeklyStoredInPrimary = Self.burnSnapshot(
            provider: .claude,
            primaryUsed: 30,
            secondaryUsed: nil,
            primaryWindowMinutes: 7 * 24 * 60)

        let weeklyOnlySession = try #require(BurnDownState(
            snapshot: weeklyOnly,
            provider: .codex,
            selection: .session))
        let weeklyOnlyWeekly = try #require(BurnDownState(
            snapshot: weeklyOnly,
            provider: .codex,
            selection: .weekly))
        let sessionOnlySession = try #require(BurnDownState(
            snapshot: sessionOnly,
            provider: .codex,
            selection: .session))
        let sessionOnlyWeekly = try #require(BurnDownState(
            snapshot: sessionOnly,
            provider: .codex,
            selection: .weekly))
        let weeklyPrimarySession = try #require(BurnDownState(
            snapshot: weeklyStoredInPrimary,
            provider: .claude,
            selection: .session))
        let weeklyPrimaryWeekly = try #require(BurnDownState(
            snapshot: weeklyStoredInPrimary,
            provider: .claude,
            selection: .weekly))

        #expect(weeklyOnlySession.selectedWindow == nil)
        #expect(weeklyOnlyWeekly.selectedWindow == weeklyOnlyWeekly.secondaryWindow)
        #expect(sessionOnlySession.selectedWindow == sessionOnlySession.primaryWindow)
        #expect(sessionOnlyWeekly.selectedWindow == nil)
        #expect(weeklyPrimarySession.selectedWindow == nil)
        #expect(weeklyPrimaryWeekly.selectedWindow?.usedPercent == 30)
    }

    @Test
    func expired_weekly_reset_no_longer_blocks_the_session_chart() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = Self.burnSnapshot(
            provider: .codex,
            primaryUsed: 20,
            secondaryUsed: 100,
            primaryReset: now.addingTimeInterval(300),
            secondaryReset: now.addingTimeInterval(-1))
        let state = try #require(BurnDownState(
            snapshot: snapshot,
            provider: .codex,
            selection: .session,
            now: now))

        #expect(!state.secondaryExhausted)
        #expect(state.primaryWindow?.remainingPercent == 80)
        #expect(!state.blankPrimaryChart)
        #expect(state.selectedResetOverride == nil)
    }

    @Test
    func explicit_reset_takes_precedence_over_estimated_reset() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let future = now.addingTimeInterval(600)

        #expect(burnEffectiveResetDate(
            explicitResetAt: now.addingTimeInterval(-1),
            estimatedResetMinutes: 5,
            now: now) == nil)
        #expect(burnEffectiveResetDate(
            explicitResetAt: future,
            estimatedResetMinutes: 5,
            now: now) == future)
        #expect(burnEffectiveResetDate(
            explicitResetAt: nil,
            estimatedResetMinutes: 5,
            now: now) == now.addingTimeInterval(300))
        #expect(burnEffectiveResetDate(
            explicitResetAt: nil,
            estimatedResetMinutes: nil,
            now: now) == nil)
    }

    @Test
    func burn_down_axis_shares_the_effective_estimated_reset() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let effectiveReset = try #require(burnEffectiveResetDate(
            explicitResetAt: nil,
            estimatedResetMinutes: 90,
            now: now))

        let axis = burnAxisDateRange(
            effectiveResetAt: effectiveReset,
            windowMinutes: 300,
            now: now)

        #expect(axis.reset == effectiveReset)
        #expect(axis.start == effectiveReset.addingTimeInterval(-5 * 60 * 60))
    }

    @Test
    func burn_down_refreshes_immediately_after_the_earliest_future_reset() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = Self.burnSnapshot(
            provider: .codex,
            primaryUsed: 20,
            secondaryUsed: 30,
            primaryReset: now.addingTimeInterval(60),
            secondaryReset: now.addingTimeInterval(120))

        #expect(BurnDownRefreshSchedule.nextRefresh(snapshot: snapshot, provider: .codex, now: now)
            == now.addingTimeInterval(61))
    }

    @Test
    func burn_down_refresh_ignores_past_resets_and_unrelated_provider_entries() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = Self.burnSnapshot(
            provider: .claude,
            primaryUsed: 20,
            secondaryUsed: 30,
            primaryReset: now.addingTimeInterval(-60),
            secondaryReset: now.addingTimeInterval(-30))
        let fallback = now.addingTimeInterval(30 * 60)

        #expect(BurnDownRefreshSchedule.nextRefresh(snapshot: snapshot, provider: .claude, now: now) == fallback)
        #expect(BurnDownRefreshSchedule.nextRefresh(snapshot: snapshot, provider: .codex, now: now) == fallback)
    }

    private static func burnSnapshot(
        provider: UsageProvider,
        primaryUsed: Double?,
        secondaryUsed: Double?,
        primaryReset: Date? = nil,
        secondaryReset: Date? = nil,
        primaryWindowMinutes: Int = 5 * 60,
        secondaryWindowMinutes: Int = 7 * 24 * 60) -> WidgetSnapshot
    {
        let entry = WidgetSnapshot.ProviderEntry(
            provider: provider,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            primary: primaryUsed.map {
                RateWindow(
                    usedPercent: $0,
                    windowMinutes: primaryWindowMinutes,
                    resetsAt: primaryReset,
                    resetDescription: nil)
            },
            secondary: secondaryUsed.map {
                RateWindow(
                    usedPercent: $0,
                    windowMinutes: secondaryWindowMinutes,
                    resetsAt: secondaryReset,
                    resetDescription: nil)
            },
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        return WidgetSnapshot(entries: [entry], generatedAt: entry.updatedAt)
    }
}

extension CodexBarWidgetProviderTests {
    @Test
    func provider_choice_supports_Cursor() {
        #expect(ProviderChoice(provider: .cursor) == .cursor)
        #expect(ProviderChoice.cursor.provider == .cursor)
    }

    @Test
    func supported_providers_keep_Cursor_when_it_is_the_only_enabled_provider() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .cursor,
            updatedAt: now,
            primary: RateWindow(usedPercent: 25, windowMinutes: 43200, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        let snapshot = WidgetSnapshot(entries: [entry], enabledProviders: [.cursor], generatedAt: now)

        #expect(CodexBarSwitcherTimelineProvider.supportedProviders(from: snapshot) == [.cursor])
    }

    @Test
    func widget_token_titles_disclose_stale_age_for_today_and_history_rows() {
        let entryUpdatedAt = Date()
        let staleToken = WidgetSnapshot.TokenUsageSummary(
            sessionCostUSD: 1.25,
            sessionTokens: 4200,
            last30DaysCostUSD: 12.50,
            last30DaysTokens: 42000,
            updatedAt: entryUpdatedAt.addingTimeInterval(-45 * 60))
        let freshToken = WidgetSnapshot.TokenUsageSummary(
            sessionCostUSD: 1.25,
            sessionTokens: 4200,
            last30DaysCostUSD: 12.50,
            last30DaysTokens: 42000,
            updatedAt: entryUpdatedAt.addingTimeInterval(-5 * 60))

        let todayTitle = WidgetFormat.tokenRowTitle(
            staleToken.sessionLabel,
            summary: staleToken,
            entryUpdatedAt: entryUpdatedAt)
        let historyTitle = WidgetFormat.tokenRowTitle(
            staleToken.last30DaysLabel,
            summary: staleToken,
            entryUpdatedAt: entryUpdatedAt)

        #expect(todayTitle.hasPrefix("Today · "))
        #expect(historyTitle.hasPrefix("30d · "))
        #expect(WidgetFormat.tokenRowTitle(
            freshToken.sessionLabel,
            summary: freshToken,
            entryUpdatedAt: entryUpdatedAt) == "Today")

        let entry = WidgetSnapshot.ProviderEntry(
            provider: .codex,
            updatedAt: entryUpdatedAt,
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: staleToken,
            dailyUsage: [])
        let todayMetric = CompactMetricFormatter.display(for: entry, metric: .todayCost)
        let historyMetric = CompactMetricFormatter.display(for: entry, metric: .last30DaysCost)

        #expect(todayMetric.label.hasPrefix("Today API est. · not billed · "))
        #expect(historyMetric.label.hasPrefix("30d API est. · not billed · "))
        #expect(CompactMetricFormatter.costMetricLabel("7d", provider: .codex) == "7d API est. · not billed")
        #expect(CompactMetricFormatter.costMetricLabel("90d", provider: .codex) == "90d API est. · not billed")
        #expect(CompactMetricFormatter.costMetricLabel("This month", provider: .codex) ==
            "This month API est. · not billed")
        #expect(CompactMetricFormatter.costMetricLabel(
            "This month API est. · not billed",
            provider: .codex) == "This month API est. · not billed")
    }

    @Test
    func usage_history_chart_mode_requires_every_point_to_expose_cost() {
        let costPoints = [
            WidgetSnapshot.DailyUsagePoint(dayKey: "2026-07-01", totalTokens: 100, costUSD: 1.2),
            WidgetSnapshot.DailyUsagePoint(dayKey: "2026-07-02", totalTokens: 200, costUSD: 2.4),
        ]
        let tokenPoints = [
            WidgetSnapshot.DailyUsagePoint(dayKey: "2026-07-01", totalTokens: 100, costUSD: nil),
            WidgetSnapshot.DailyUsagePoint(dayKey: "2026-07-02", totalTokens: 200, costUSD: nil),
        ]
        let mixedPoints = [
            WidgetSnapshot.DailyUsagePoint(dayKey: "2026-07-01", totalTokens: 100, costUSD: 1.2),
            WidgetSnapshot.DailyUsagePoint(dayKey: "2026-07-02", totalTokens: 200, costUSD: nil),
        ]
        let emptyPoints: [WidgetSnapshot.DailyUsagePoint] = []

        #expect(UsageHistoryChartMode.isCostMode(costPoints) == true)
        #expect(UsageHistoryChartMode.isCostMode(tokenPoints) == false)
        #expect(UsageHistoryChartMode.isCostMode(mixedPoints) == false)
        #expect(UsageHistoryChartMode.isCostMode(emptyPoints) == false)
    }
}
