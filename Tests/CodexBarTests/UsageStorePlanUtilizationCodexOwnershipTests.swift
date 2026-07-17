import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct UsageStorePlanUtilizationCodexOwnershipTests {
    @MainActor
    @Test
    func codex_plan_history_aliases_pre_upgrade_codex_email_hash_bucket_into_canonical_email_hash() throws {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let snapshot = UsageStorePlanUtilizationTests.makeSnapshot(provider: .codex, email: "alice@example.com")
        let canonicalKey = try #require(
            UsageStore._planUtilizationAccountKeyForTesting(
                provider: .codex,
                snapshot: snapshot))
        let legacyEmailHash = UsageStore._codexLegacyPlanUtilizationEmailHashKeyForTesting(
            normalizedEmail: "alice@example.com")
        let weekly = planSeries(name: .weekly, windowMinutes: 10080, entries: [
            planEntry(at: Date(timeIntervalSince1970: 1_700_000_000), usedPercent: 20),
        ])

        store.planUtilizationHistory[.codex] = PlanUtilizationHistoryBuckets(accounts: [
            legacyEmailHash: [weekly],
        ])
        store._setSnapshotForTesting(snapshot, provider: .codex)

        let history = store.planUtilizationHistory(for: .codex)
        let buckets = try #require(store.planUtilizationHistory[.codex])

        #expect(buckets.preferredAccountKey == canonicalKey)
        #expect(history == [weekly])
        #expect(buckets.accounts[canonicalKey] == [weekly])
        #expect(buckets.accounts[legacyEmailHash] == nil)
    }

    @MainActor
    @Test
    func codex_strict_continuity_adopts_unscoped_only_when_there_is_one_owner() throws {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let snapshot = UsageStorePlanUtilizationTests.makeSnapshot(provider: .codex, email: "alice@example.com")
        let canonicalKey = try #require(
            UsageStore._planUtilizationAccountKeyForTesting(
                provider: .codex,
                snapshot: snapshot))
        let legacyEmailHash = UsageStore._codexLegacyPlanUtilizationEmailHashKeyForTesting(
            normalizedEmail: "alice@example.com")
        let bootstrap = planSeries(name: .session, windowMinutes: 300, entries: [
            planEntry(at: Date(timeIntervalSince1970: 1_699_913_600), usedPercent: 15),
        ])
        let weekly = planSeries(name: .weekly, windowMinutes: 10080, entries: [
            planEntry(at: Date(timeIntervalSince1970: 1_700_000_000), usedPercent: 20),
        ])

        store.planUtilizationHistory[.codex] = PlanUtilizationHistoryBuckets(
            unscoped: [bootstrap],
            accounts: [
                legacyEmailHash: [weekly],
            ])
        store._setSnapshotForTesting(snapshot, provider: .codex)

        let history = store.planUtilizationHistory(for: .codex)
        let buckets = try #require(store.planUtilizationHistory[.codex])

        #expect(buckets.preferredAccountKey == canonicalKey)
        #expect(history == [bootstrap, weekly])
        #expect(buckets.unscoped.isEmpty)
        #expect(buckets.accounts[canonicalKey] == [bootstrap, weekly])
        #expect(buckets.accounts[legacyEmailHash] == nil)
    }

    @MainActor
    @Test
    func codex_strict_continuity_ignores_later_unrelated_owners_outside_the_unscoped_period() throws {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let snapshot = UsageStorePlanUtilizationTests.makeSnapshot(provider: .codex, email: "alice@example.com")
        let canonicalKey = try #require(
            UsageStore._planUtilizationAccountKeyForTesting(
                provider: .codex,
                snapshot: snapshot))
        let legacyEmailHash = UsageStore._codexLegacyPlanUtilizationEmailHashKeyForTesting(
            normalizedEmail: "alice@example.com")
        let laterOtherKey = "codex:v1:provider-account:acct-later"
        let bootstrap = planSeries(name: .session, windowMinutes: 300, entries: [
            planEntry(at: Date(timeIntervalSince1970: 1_699_913_600), usedPercent: 15),
        ])
        let weekly = planSeries(name: .weekly, windowMinutes: 10080, entries: [
            planEntry(at: Date(timeIntervalSince1970: 1_700_000_000), usedPercent: 20),
        ])
        let laterWeekly = planSeries(name: .weekly, windowMinutes: 10080, entries: [
            planEntry(at: Date(timeIntervalSince1970: 1_701_900_000), usedPercent: 35),
        ])

        store.planUtilizationHistory[.codex] = PlanUtilizationHistoryBuckets(
            unscoped: [bootstrap],
            accounts: [
                legacyEmailHash: [weekly],
                laterOtherKey: [laterWeekly],
            ])
        store._setSnapshotForTesting(snapshot, provider: .codex)

        let history = store.planUtilizationHistory(for: .codex)
        let buckets = try #require(store.planUtilizationHistory[.codex])

        #expect(buckets.preferredAccountKey == canonicalKey)
        #expect(history == [bootstrap, weekly])
        #expect(buckets.unscoped.isEmpty)
        #expect(buckets.accounts[canonicalKey] == [bootstrap, weekly])
        #expect(buckets.accounts[laterOtherKey] == [laterWeekly])
    }

    @MainActor
    @Test
    func codex_real_fixture_carries_local_opaque_weekly_continuity_into_provider_account() throws {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let formatter = ISO8601DateFormatter()
        let providerAccountKey = try #require(CodexHistoryOwnership.canonicalKey(for: .providerAccount(
            id: "0c2a5eef-a612-45bb-9796-9aa83ce1bed7")))
        let legacyEmailHash = UsageStore._codexLegacyPlanUtilizationEmailHashKeyForTesting(
            normalizedEmail: "ratulsarna@gmail.com")
        let canonicalEmailHashKey = CodexHistoryOwnership.canonicalEmailHashKey(for: "ratulsarna@gmail.com")
        let opaqueKey = "3e31a7fdc57ea26c62fd7061d25dcab74a91b0da2d8f514b07e99aad800ee897"
        let weeklyResetAt = try #require(ISO8601DateFormatter().date(from: "2026-04-08T07:57:12Z"))
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 12,
                windowMinutes: 10080,
                resetsAt: weeklyResetAt,
                resetDescription: nil),
            updatedAt: weeklyResetAt,
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: "ratulsarna@gmail.com",
                accountOrganization: nil,
                loginMethod: "plus"))

        store.planUtilizationHistory[.codex] = try UsageStorePlanUtilizationTests.loadPlanUtilizationFixture(
            named: "codex-plan-utilization-real-migration.json")
        store.settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: "ratulsarna@gmail.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: weeklyResetAt,
            identity: .providerAccount(id: "0c2a5eef-a612-45bb-9796-9aa83ce1bed7"))
        defer { store.settings._test_liveSystemCodexAccount = nil }
        store._setSnapshotForTesting(snapshot, provider: .codex)

        let history = store.planUtilizationHistory(for: .codex)
        let buckets = try #require(store.planUtilizationHistory[.codex])
        let weekly = try #require(findSeries(history, name: .weekly, windowMinutes: 10080))
        let session = try #require(findSeries(history, name: .session, windowMinutes: 300))
        let expectedOldestWeekly = try #require(formatter.date(from: "2026-03-23T09:55:44Z"))
        let expectedNewestWeekly = try #require(formatter.date(from: "2026-04-01T20:33:41Z"))

        #expect(buckets.preferredAccountKey == providerAccountKey)
        #expect(weekly.entries.first?.capturedAt == expectedOldestWeekly)
        #expect(weekly.entries.last?.capturedAt == expectedNewestWeekly)
        #expect(session.entries.first?.capturedAt == expectedOldestWeekly)
        #expect(buckets.accounts[providerAccountKey] == history)
        #expect(buckets.accounts[opaqueKey] == nil)
        #expect(buckets.accounts[legacyEmailHash] == nil)
        #expect(buckets.accounts[canonicalEmailHashKey] == nil)
    }

    @MainActor
    @Test
    func codex_real_fixture_keeps_opaque_history_separate_when_multiple_opaque_candidates_could_match() throws {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let formatter = ISO8601DateFormatter()
        let providerAccountKey = try #require(CodexHistoryOwnership.canonicalKey(for: .providerAccount(
            id: "0c2a5eef-a612-45bb-9796-9aa83ce1bed7")))
        let originalOpaqueKey = "3e31a7fdc57ea26c62fd7061d25dcab74a91b0da2d8f514b07e99aad800ee897"
        let duplicateOpaqueKey = "legacy-codex-opaque-duplicate"
        let weeklyResetAt = try #require(ISO8601DateFormatter().date(from: "2026-04-08T07:57:12Z"))
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 12,
                windowMinutes: 10080,
                resetsAt: weeklyResetAt,
                resetDescription: nil),
            updatedAt: weeklyResetAt,
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: "ratulsarna@gmail.com",
                accountOrganization: nil,
                loginMethod: "plus"))

        var fixture = try UsageStorePlanUtilizationTests.loadPlanUtilizationFixture(
            named: "codex-plan-utilization-real-migration.json")
        fixture.accounts[duplicateOpaqueKey] = fixture.accounts[originalOpaqueKey]
        store.planUtilizationHistory[.codex] = fixture
        store.settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: "ratulsarna@gmail.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: weeklyResetAt,
            identity: .providerAccount(id: "0c2a5eef-a612-45bb-9796-9aa83ce1bed7"))
        defer { store.settings._test_liveSystemCodexAccount = nil }
        store._setSnapshotForTesting(snapshot, provider: .codex)

        let history = store.planUtilizationHistory(for: .codex)
        let buckets = try #require(store.planUtilizationHistory[.codex])
        let weekly = try #require(findSeries(history, name: .weekly, windowMinutes: 10080))
        let expectedNonOpaqueStart = try #require(formatter.date(from: "2026-03-28T06:50:16Z"))

        #expect(buckets.preferredAccountKey == providerAccountKey)
        #expect(weekly.entries.first?.capturedAt == expectedNonOpaqueStart)
        #expect(buckets.accounts[originalOpaqueKey] != nil)
        #expect(buckets.accounts[duplicateOpaqueKey] != nil)
    }

    @MainActor
    @Test
    func codex_real_fixture_keeps_opaque_history_separate_when_overlapping_non_target_owner_exists() throws {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let formatter = ISO8601DateFormatter()
        let providerAccountKey = try #require(CodexHistoryOwnership.canonicalKey(for: .providerAccount(
            id: "0c2a5eef-a612-45bb-9796-9aa83ce1bed7")))
        let opaqueKey = "3e31a7fdc57ea26c62fd7061d25dcab74a91b0da2d8f514b07e99aad800ee897"
        let overlappingOtherKey = "codex:v1:provider-account:acct-other"
        let weeklyResetAt = try #require(formatter.date(from: "2026-04-08T07:57:12Z"))
        let expectedNonOpaqueStart = try #require(formatter.date(from: "2026-03-28T06:50:16Z"))
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 12,
                windowMinutes: 10080,
                resetsAt: weeklyResetAt,
                resetDescription: nil),
            updatedAt: weeklyResetAt,
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: "ratulsarna@gmail.com",
                accountOrganization: nil,
                loginMethod: "plus"))

        let overlappingCapturedAt = try #require(formatter.date(from: "2026-03-30T12:00:00Z"))
        var fixture = try UsageStorePlanUtilizationTests.loadPlanUtilizationFixture(
            named: "codex-plan-utilization-real-migration.json")
        fixture.accounts[overlappingOtherKey] = [
            planSeries(name: .weekly, windowMinutes: 10080, entries: [
                planEntry(
                    at: overlappingCapturedAt,
                    usedPercent: 35,
                    resetsAt: weeklyResetAt),
            ]),
        ]
        store.planUtilizationHistory[.codex] = fixture
        store.settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: "ratulsarna@gmail.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: weeklyResetAt,
            identity: .providerAccount(id: "0c2a5eef-a612-45bb-9796-9aa83ce1bed7"))
        defer { store.settings._test_liveSystemCodexAccount = nil }
        store._setSnapshotForTesting(snapshot, provider: .codex)

        let history = store.planUtilizationHistory(for: .codex)
        let buckets = try #require(store.planUtilizationHistory[.codex])
        let weekly = try #require(findSeries(history, name: .weekly, windowMinutes: 10080))

        #expect(buckets.preferredAccountKey == providerAccountKey)
        #expect(weekly.entries.first?.capturedAt == expectedNonOpaqueStart)
        #expect(buckets.accounts[opaqueKey] != nil)
        #expect(buckets.accounts[overlappingOtherKey] != nil)
    }

    @MainActor
    @Test
    func codex_opaque_recovery_uses_normalized_dashboard_weekly_reset_when_snapshot_has_only_session_window() throws {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let formatter = ISO8601DateFormatter()
        let providerAccountKey = try #require(CodexHistoryOwnership.canonicalKey(for: .providerAccount(
            id: "0c2a5eef-a612-45bb-9796-9aa83ce1bed7")))
        let opaqueKey = "3e31a7fdc57ea26c62fd7061d25dcab74a91b0da2d8f514b07e99aad800ee897"
        let weeklyResetAt = try #require(formatter.date(from: "2026-04-08T07:57:12Z"))
        let expectedOpaqueStart = try #require(formatter.date(from: "2026-03-23T09:55:44Z"))
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: weeklyResetAt,
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: "ratulsarna@gmail.com",
                accountOrganization: nil,
                loginMethod: "plus"))

        store.planUtilizationHistory[.codex] = try UsageStorePlanUtilizationTests.loadPlanUtilizationFixture(
            named: "codex-plan-utilization-real-migration.json")
        store.openAIDashboard = OpenAIDashboardSnapshot(
            signedInEmail: "ratulsarna@gmail.com",
            codeReviewRemainingPercent: nil,
            creditEvents: [],
            dailyBreakdown: [],
            usageBreakdown: [],
            creditsPurchaseURL: nil,
            primaryLimit: RateWindow(
                usedPercent: 12,
                windowMinutes: 10080,
                resetsAt: weeklyResetAt,
                resetDescription: nil),
            secondaryLimit: nil,
            creditsRemaining: nil,
            accountPlan: "plus",
            updatedAt: weeklyResetAt)
        store.openAIDashboardAttachmentAuthorized = true
        store.settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: "ratulsarna@gmail.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: weeklyResetAt,
            identity: .providerAccount(id: "0c2a5eef-a612-45bb-9796-9aa83ce1bed7"))
        defer { store.settings._test_liveSystemCodexAccount = nil }
        store._setSnapshotForTesting(snapshot, provider: .codex)

        let history = store.planUtilizationHistory(for: .codex)
        let buckets = try #require(store.planUtilizationHistory[.codex])
        let weekly = try #require(findSeries(history, name: .weekly, windowMinutes: 10080))

        #expect(buckets.preferredAccountKey == providerAccountKey)
        #expect(weekly.entries.first?.capturedAt == expectedOpaqueStart)
        #expect(buckets.accounts[opaqueKey] == nil)
    }

    @MainActor
    @Test
    func codex_display_only_dashboard_does_not_drive_opaque_recovery_when_snapshot_has_only_session_window() throws {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let formatter = ISO8601DateFormatter()
        let providerAccountKey = try #require(CodexHistoryOwnership.canonicalKey(for: .providerAccount(
            id: "0c2a5eef-a612-45bb-9796-9aa83ce1bed7")))
        let opaqueKey = "3e31a7fdc57ea26c62fd7061d25dcab74a91b0da2d8f514b07e99aad800ee897"
        let weeklyResetAt = try #require(formatter.date(from: "2026-04-08T07:57:12Z"))
        let expectedNonOpaqueStart = try #require(formatter.date(from: "2026-03-28T06:50:16Z"))
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: weeklyResetAt,
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: "ratulsarna@gmail.com",
                accountOrganization: nil,
                loginMethod: "plus"))

        store.planUtilizationHistory[.codex] = try UsageStorePlanUtilizationTests.loadPlanUtilizationFixture(
            named: "codex-plan-utilization-real-migration.json")
        store.openAIDashboard = OpenAIDashboardSnapshot(
            signedInEmail: "ratulsarna@gmail.com",
            codeReviewRemainingPercent: nil,
            creditEvents: [],
            dailyBreakdown: [],
            usageBreakdown: [],
            creditsPurchaseURL: nil,
            primaryLimit: RateWindow(
                usedPercent: 12,
                windowMinutes: 10080,
                resetsAt: weeklyResetAt,
                resetDescription: nil),
            secondaryLimit: nil,
            creditsRemaining: nil,
            accountPlan: "plus",
            updatedAt: weeklyResetAt)
        store.openAIDashboardAttachmentAuthorized = false
        store.settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: "ratulsarna@gmail.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: weeklyResetAt,
            identity: .providerAccount(id: "0c2a5eef-a612-45bb-9796-9aa83ce1bed7"))
        defer { store.settings._test_liveSystemCodexAccount = nil }
        store._setSnapshotForTesting(snapshot, provider: .codex)

        let history = store.planUtilizationHistory(for: .codex)
        let buckets = try #require(store.planUtilizationHistory[.codex])
        let weekly = try #require(findSeries(history, name: .weekly, windowMinutes: 10080))

        #expect(buckets.preferredAccountKey == providerAccountKey)
        #expect(weekly.entries.first?.capturedAt == expectedNonOpaqueStart)
        #expect(buckets.accounts[opaqueKey] != nil)
    }

    @MainActor
    @Test
    func codex_adjacent_managed_and_live_accounts_veto_unscoped_adoption() throws {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let managedAccount = ManagedCodexAccount(
            id: UUID(),
            email: "managed@example.com",
            managedHomePath: "/tmp/managed-codex-home",
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        let snapshot = UsageStorePlanUtilizationTests.makeSnapshot(provider: .codex, email: managedAccount.email)
        let canonicalKey = try #require(
            UsageStore._planUtilizationAccountKeyForTesting(
                provider: .codex,
                snapshot: snapshot))
        let legacyEmailHash = UsageStore._codexLegacyPlanUtilizationEmailHashKeyForTesting(
            normalizedEmail: managedAccount.email)
        let bootstrap = planSeries(name: .session, windowMinutes: 300, entries: [
            planEntry(at: Date(timeIntervalSince1970: 1_699_913_600), usedPercent: 15),
        ])
        let weekly = planSeries(name: .weekly, windowMinutes: 10080, entries: [
            planEntry(at: Date(timeIntervalSince1970: 1_700_000_000), usedPercent: 20),
        ])

        store.planUtilizationHistory[.codex] = PlanUtilizationHistoryBuckets(
            unscoped: [bootstrap],
            accounts: [
                legacyEmailHash: [weekly],
            ])
        store.settings._test_activeManagedCodexAccount = managedAccount
        store.settings.codexActiveSource = .managedAccount(id: managedAccount.id)
        store.settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: "live@example.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date(),
            identity: .providerAccount(id: "live-acct"))
        defer {
            store.settings._test_activeManagedCodexAccount = nil
            store.settings._test_liveSystemCodexAccount = nil
            store.settings.codexActiveSource = .liveSystem
        }
        store._setSnapshotForTesting(snapshot, provider: .codex)

        let history = store.planUtilizationHistory(for: .codex)
        let buckets = try #require(store.planUtilizationHistory[.codex])

        #expect(history == [weekly])
        #expect(buckets.unscoped == [bootstrap])
        #expect(buckets.accounts[canonicalKey] == [weekly])
    }

    @MainActor
    @Test
    func codex_extra_saved_managed_accounts_do_not_veto_active_account_adoption() throws {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let activeManagedAccount = ManagedCodexAccount(
            id: UUID(),
            email: "managed@example.com",
            managedHomePath: "/tmp/managed-codex-home",
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        let inactiveManagedAccount = ManagedCodexAccount(
            id: UUID(),
            email: "other@example.com",
            managedHomePath: "/tmp/other-codex-home",
            createdAt: 2,
            updatedAt: 2,
            lastAuthenticatedAt: 2)
        let managedStoreURL = try #require(store.settings._test_managedCodexAccountStoreURL)
        let managedStore = FileManagedCodexAccountStore(fileURL: managedStoreURL)
        try managedStore.storeAccounts(ManagedCodexAccountSet(
            version: FileManagedCodexAccountStore.currentVersion,
            accounts: [activeManagedAccount, inactiveManagedAccount]))
        let snapshot = UsageStorePlanUtilizationTests.makeSnapshot(provider: .codex, email: activeManagedAccount.email)
        let canonicalKey = try #require(
            UsageStore._planUtilizationAccountKeyForTesting(
                provider: .codex,
                snapshot: snapshot))
        let legacyEmailHash = UsageStore._codexLegacyPlanUtilizationEmailHashKeyForTesting(
            normalizedEmail: activeManagedAccount.email)
        let bootstrap = planSeries(name: .session, windowMinutes: 300, entries: [
            planEntry(at: Date(timeIntervalSince1970: 1_699_913_600), usedPercent: 15),
        ])
        let weekly = planSeries(name: .weekly, windowMinutes: 10080, entries: [
            planEntry(at: Date(timeIntervalSince1970: 1_700_000_000), usedPercent: 20),
        ])

        store.planUtilizationHistory[.codex] = PlanUtilizationHistoryBuckets(
            unscoped: [bootstrap],
            accounts: [
                legacyEmailHash: [weekly],
            ])
        store.settings._test_activeManagedCodexAccount = activeManagedAccount
        store.settings.codexActiveSource = .managedAccount(id: activeManagedAccount.id)
        defer {
            store.settings._test_activeManagedCodexAccount = nil
            store.settings.codexActiveSource = .liveSystem
        }
        store._setSnapshotForTesting(snapshot, provider: .codex)

        let history = store.planUtilizationHistory(for: .codex)
        let buckets = try #require(store.planUtilizationHistory[.codex])

        #expect(history == [bootstrap, weekly])
        #expect(buckets.unscoped.isEmpty)
        #expect(buckets.accounts[canonicalKey] == [bootstrap, weekly])
    }

    @MainActor
    @Test
    func codex_inactive_managed_accounts_do_not_veto_live_opaque_recovery() throws {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let formatter = ISO8601DateFormatter()
        let providerAccountKey = try #require(CodexHistoryOwnership.canonicalKey(for: .providerAccount(
            id: "0c2a5eef-a612-45bb-9796-9aa83ce1bed7")))
        let managedAccount = ManagedCodexAccount(
            id: UUID(),
            email: "managed@example.com",
            managedHomePath: "/tmp/managed-codex-home",
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        let opaqueKey = "3e31a7fdc57ea26c62fd7061d25dcab74a91b0da2d8f514b07e99aad800ee897"
        let weeklyResetAt = try #require(formatter.date(from: "2026-04-08T07:57:12Z"))
        let expectedOpaqueStart = try #require(formatter.date(from: "2026-03-23T09:55:44Z"))
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 12,
                windowMinutes: 10080,
                resetsAt: weeklyResetAt,
                resetDescription: nil),
            updatedAt: weeklyResetAt,
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: "ratulsarna@gmail.com",
                accountOrganization: nil,
                loginMethod: "plus"))

        store.planUtilizationHistory[.codex] = try UsageStorePlanUtilizationTests.loadPlanUtilizationFixture(
            named: "codex-plan-utilization-real-migration.json")
        store.settings._test_activeManagedCodexAccount = managedAccount
        store.settings.codexActiveSource = .liveSystem
        store.settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: "ratulsarna@gmail.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: weeklyResetAt,
            identity: .providerAccount(id: "0c2a5eef-a612-45bb-9796-9aa83ce1bed7"))
        defer {
            store.settings._test_activeManagedCodexAccount = nil
            store.settings._test_liveSystemCodexAccount = nil
        }
        store._setSnapshotForTesting(snapshot, provider: .codex)

        let history = store.planUtilizationHistory(for: .codex)
        let buckets = try #require(store.planUtilizationHistory[.codex])
        let weekly = try #require(findSeries(history, name: .weekly, windowMinutes: 10080))

        #expect(buckets.preferredAccountKey == providerAccountKey)
        #expect(weekly.entries.first?.capturedAt == expectedOpaqueStart)
        #expect(buckets.accounts[opaqueKey] == nil)
    }

    @MainActor
    @Test
    func codex_provider_account_continuity_absorbs_matching_email_scoped_history() throws {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let normalizedEmail = "alice@example.com"
        let snapshot = UsageStorePlanUtilizationTests.makeSnapshot(provider: .codex, email: normalizedEmail)
        let providerAccountKey = try #require(
            CodexHistoryOwnership.canonicalKey(for: .providerAccount(id: "live-acct")))
        let canonicalEmailHashKey = CodexHistoryOwnership.canonicalEmailHashKey(for: normalizedEmail)
        let legacyEmailHash = UsageStore._codexLegacyPlanUtilizationEmailHashKeyForTesting(
            normalizedEmail: normalizedEmail)
        let session = planSeries(name: .session, windowMinutes: 300, entries: [
            planEntry(at: Date(timeIntervalSince1970: 1_699_913_600), usedPercent: 15),
        ])
        let weekly = planSeries(name: .weekly, windowMinutes: 10080, entries: [
            planEntry(at: Date(timeIntervalSince1970: 1_700_000_000), usedPercent: 20),
        ])

        store.planUtilizationHistory[.codex] = PlanUtilizationHistoryBuckets(accounts: [
            canonicalEmailHashKey: [session],
            legacyEmailHash: [weekly],
        ])
        store.settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: normalizedEmail,
            codexHomePath: "/Users/test/.codex",
            observedAt: Date(),
            identity: .providerAccount(id: "live-acct"))
        defer { store.settings._test_liveSystemCodexAccount = nil }
        store._setSnapshotForTesting(snapshot, provider: .codex)

        let history = store.planUtilizationHistory(for: .codex)
        let buckets = try #require(store.planUtilizationHistory[.codex])

        #expect(buckets.preferredAccountKey == providerAccountKey)
        #expect(history == [session, weekly])
        #expect(buckets.accounts[providerAccountKey] == [session, weekly])
        #expect(buckets.accounts[canonicalEmailHashKey] == nil)
        #expect(buckets.accounts[legacyEmailHash] == nil)
    }
}
