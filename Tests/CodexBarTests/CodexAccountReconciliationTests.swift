import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
struct CodexAccountReconciliationTests {
    @MainActor
    private static func makeSettings(suite: String) throws -> SettingsStore {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "providerDetectionCompleted")
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.providerDetectionCompleted = true
        return settings
    }

    @Test
    @MainActor
    func settings_store_exposes_codex_reconciliation_accessors_using_managed_and_live_overrides() throws {
        let suite = "CodexAccountReconciliationTests-settings-store"
        let settings = try Self.makeSettings(suite: suite)
        let managed = ManagedCodexAccount(
            id: UUID(),
            email: "managed@example.com",
            managedHomePath: "/tmp/managed-home",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
        let live = ObservedSystemCodexAccount(
            email: "system@example.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date())
        settings._test_activeManagedCodexAccount = managed
        settings._test_liveSystemCodexAccount = live
        settings.codexActiveSource = .managedAccount(id: managed.id)
        defer {
            settings._test_activeManagedCodexAccount = nil
            settings._test_liveSystemCodexAccount = nil
        }

        let snapshot = settings.codexAccountReconciliationSnapshot
        let projection = settings.codexVisibleAccountProjection

        #expect(settings.codexActiveSource == .managedAccount(id: managed.id))
        #expect(snapshot.storedAccounts.map(\.id) == [managed.id])
        #expect(snapshot.storedAccounts.map(\.email) == [managed.email])
        #expect(snapshot.activeStoredAccount?.id == managed.id)
        #expect(snapshot.activeStoredAccount?.email == managed.email)
        #expect(snapshot.liveSystemAccount?.email == live.email)
        #expect(snapshot.liveSystemAccount?.codexHomePath == live.codexHomePath)
        #expect(snapshot.liveSystemAccount?.observedAt == live.observedAt)
        #expect(snapshot.liveSystemAccount?.identity == .emailOnly(normalizedEmail: "system@example.com"))
        #expect(snapshot.matchingStoredAccountForLiveSystemAccount == nil)
        #expect(snapshot.activeSource == .managedAccount(id: managed.id))
        #expect(snapshot.hasUnreadableAddedAccountStore == false)
        #expect(Set(projection.visibleAccounts.map(\.email)) == ["managed@example.com", "system@example.com"])
        #expect(settings.codexVisibleAccounts == projection.visibleAccounts)
        #expect(projection.activeVisibleAccountID == "managed@example.com")
        #expect(projection.liveVisibleAccountID == "system@example.com")
    }

    @Test
    @MainActor
    func settings_store_managed_override_does_not_leak_ambient_live_system_account() throws {
        let suite = "CodexAccountReconciliationTests-managed-only"
        let settings = try Self.makeSettings(suite: suite)
        let managed = ManagedCodexAccount(
            id: UUID(),
            email: "managed@example.com",
            managedHomePath: "/tmp/managed-home",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
        settings._test_activeManagedCodexAccount = managed
        settings.codexActiveSource = .managedAccount(id: managed.id)
        defer {
            settings._test_activeManagedCodexAccount = nil
        }

        let snapshot = settings.codexAccountReconciliationSnapshot
        let projection = settings.codexVisibleAccountProjection

        #expect(settings.codexActiveSource == .managedAccount(id: managed.id))
        #expect(snapshot.liveSystemAccount == nil)
        #expect(snapshot.matchingStoredAccountForLiveSystemAccount == nil)
        #expect(snapshot.activeSource == .managedAccount(id: managed.id))
        #expect(projection.visibleAccounts.map(\.email) == ["managed@example.com"])
        #expect(projection.activeVisibleAccountID == "managed@example.com")
        #expect(projection.liveVisibleAccountID == nil)
    }

    @Test
    @MainActor
    func settings_store_reconciliation_environment_override_drives_live_observation_with_synthetic_store() throws {
        let suite = "CodexAccountReconciliationTests-environment-only"
        let settings = try Self.makeSettings(suite: suite)
        let ambientHome = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true)
        try Self.writeCodexAuthFile(homeURL: ambientHome, email: "ambient@example.com", plan: "pro")
        settings._test_codexReconciliationEnvironment = ["CODEX_HOME": ambientHome.path]
        defer {
            settings._test_codexReconciliationEnvironment = nil
            try? FileManager.default.removeItem(at: ambientHome)
        }

        let snapshot = settings.codexAccountReconciliationSnapshot
        let projection = settings.codexVisibleAccountProjection

        #expect(settings.codexActiveSource == .liveSystem)
        #expect(snapshot.storedAccounts.isEmpty)
        #expect(snapshot.activeStoredAccount == nil)
        #expect(snapshot.liveSystemAccount?.email == "ambient@example.com")
        #expect(snapshot.liveSystemAccount?.codexHomePath == ambientHome.path)
        #expect(snapshot.matchingStoredAccountForLiveSystemAccount == nil)
        #expect(snapshot.activeSource == .liveSystem)
        #expect(projection.visibleAccounts.map(\.email) == ["ambient@example.com"])
        #expect(projection.activeVisibleAccountID == "ambient@example.com")
        #expect(projection.liveVisibleAccountID == "ambient@example.com")
    }

    @Test
    @MainActor
    func settings_store_can_reuse_short_lived_codex_reconciliation_snapshot() throws {
        let suite = "CodexAccountReconciliationTests-short-lived-cache"
        let settings = try Self.makeSettings(suite: suite)
        let ambientHome = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true)
        try Self.writeCodexAuthFile(homeURL: ambientHome, email: "cached@example.com", plan: "pro")
        settings._test_codexReconciliationEnvironment = ["CODEX_HOME": ambientHome.path]
        SettingsStore.codexAccountReconciliationSnapshotCacheIntervalOverrideForTesting = 60
        defer {
            SettingsStore.codexAccountReconciliationSnapshotCacheIntervalOverrideForTesting = nil
            settings._test_codexReconciliationEnvironment = nil
            try? FileManager.default.removeItem(at: ambientHome)
        }

        let first = settings.codexAccountReconciliationSnapshot
        try FileManager.default.removeItem(at: ambientHome)
        let cached = settings.codexAccountReconciliationSnapshot
        settings.invalidateCodexAccountReconciliationSnapshotCache()
        let refreshed = settings.codexAccountReconciliationSnapshot

        #expect(first.liveSystemAccount?.email == "cached@example.com")
        #expect(cached.liveSystemAccount?.email == "cached@example.com")
        #expect(refreshed.liveSystemAccount == nil)
    }

    @Test
    @MainActor
    func codex_active_source_write_invalidates_short_lived_reconciliation_snapshot() throws {
        let suite = "CodexAccountReconciliationTests-active-source-cache-invalidation"
        let settings = try Self.makeSettings(suite: suite)
        let ambientHome = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true)
        try Self.writeCodexAuthFile(homeURL: ambientHome, email: "before@example.com", plan: "pro")
        settings._test_codexReconciliationEnvironment = ["CODEX_HOME": ambientHome.path]
        SettingsStore.codexAccountReconciliationSnapshotCacheIntervalOverrideForTesting = 60
        defer {
            SettingsStore.codexAccountReconciliationSnapshotCacheIntervalOverrideForTesting = nil
            settings._test_codexReconciliationEnvironment = nil
            try? FileManager.default.removeItem(at: ambientHome)
        }

        #expect(settings.codexAccountReconciliationSnapshot.liveSystemAccount?.email == "before@example.com")
        try Self.writeCodexAuthFile(homeURL: ambientHome, email: "after@example.com", plan: "pro")
        settings.codexActiveSource = .liveSystem

        #expect(settings.codexAccountReconciliationSnapshot.liveSystemAccount?.email == "after@example.com")
    }

    @Test
    @MainActor
    func managed_account_changes_invalidate_short_lived_reconciliation_snapshot() throws {
        let suite = "CodexAccountReconciliationTests-managed-change-cache-invalidation"
        let settings = try Self.makeSettings(suite: suite)
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-managed-store-\(UUID().uuidString).json")
        try Self.writeManagedCodexStore(
            ManagedCodexAccountSet(version: FileManagedCodexAccountStore.currentVersion, accounts: []),
            to: storeURL)
        let stored = ManagedCodexAccount(
            id: UUID(),
            email: "stored@example.com",
            managedHomePath: "/tmp/stored-managed-home",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
        settings._test_managedCodexAccountStoreURL = storeURL
        settings.codexActiveSource = .managedAccount(id: stored.id)
        SettingsStore.codexAccountReconciliationSnapshotCacheIntervalOverrideForTesting = 60
        defer {
            SettingsStore.codexAccountReconciliationSnapshotCacheIntervalOverrideForTesting = nil
            settings._test_managedCodexAccountStoreURL = nil
            try? FileManager.default.removeItem(at: storeURL)
        }

        #expect(settings.codexAccountReconciliationSnapshot.storedAccounts.isEmpty)
        try Self.writeManagedCodexStore(
            ManagedCodexAccountSet(version: FileManagedCodexAccountStore.currentVersion, accounts: [stored]),
            to: storeURL)
        settings.refreshCodexAccountReconciliationAfterManagedAccountsDidChange()

        #expect(settings.codexAccountReconciliationSnapshot.storedAccounts.map(\.id) == [stored.id])
    }

    @Test
    @MainActor
    func settings_store_home_path_override_also_keeps_reconciliation_hermetic() throws {
        let suite = "CodexAccountReconciliationTests-home-path-only"
        let settings = try Self.makeSettings(suite: suite)
        settings._test_activeManagedCodexRemoteHomePath = "/tmp/managed-route-home"
        settings._test_liveSystemCodexAccount = nil
        settings._test_codexReconciliationEnvironment = nil
        defer {
            settings._test_activeManagedCodexRemoteHomePath = nil
            settings._test_liveSystemCodexAccount = nil
            settings._test_codexReconciliationEnvironment = nil
        }

        let snapshot = settings.codexAccountReconciliationSnapshot
        let projection = settings.codexVisibleAccountProjection

        #expect(snapshot.storedAccounts.isEmpty)
        #expect(snapshot.activeStoredAccount == nil)
        #expect(snapshot.liveSystemAccount == nil)
        #expect(snapshot.matchingStoredAccountForLiveSystemAccount == nil)
        #expect(projection.visibleAccounts.isEmpty)
        #expect(projection.activeVisibleAccountID == nil)
        #expect(projection.liveVisibleAccountID == nil)
    }

    @Test
    @MainActor
    func settings_store_home_path_override_keeps_active_source_hermetic_without_persisted_source() throws {
        let suite = "CodexAccountReconciliationTests-home-path-hermetic-source"
        let settings = try Self.makeSettings(suite: suite)
        let ambient = ManagedCodexAccount(
            id: UUID(),
            email: "ambient-managed@example.com",
            managedHomePath: "/tmp/ambient-managed-home",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
        let accounts = ManagedCodexAccountSet(
            version: FileManagedCodexAccountStore.currentVersion,
            accounts: [ambient])
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-managed-store-\(UUID().uuidString).json")
        try Self.writeManagedCodexStore(accounts, to: storeURL)

        settings._test_managedCodexAccountStoreURL = storeURL
        settings._test_activeManagedCodexRemoteHomePath = "/tmp/managed-route-home"
        defer {
            settings._test_managedCodexAccountStoreURL = nil
            settings._test_activeManagedCodexRemoteHomePath = nil
            try? FileManager.default.removeItem(at: storeURL)
        }

        let snapshot = settings.codexAccountReconciliationSnapshot

        #expect(settings.codexActiveSource == .liveSystem)
        #expect(settings.providerConfig(for: .codex)?.codexActiveSource == nil)
        #expect(snapshot.storedAccounts.map(\.id) == [ambient.id])
        #expect(snapshot.storedAccounts.map(\.email) == [ambient.email])
        #expect(snapshot.activeStoredAccount == nil)
        #expect(snapshot.activeSource == .liveSystem)
    }

    @Test
    @MainActor
    func settings_store_normal_reconciliation_path_honors_persisted_active_source() throws {
        let suite = "CodexAccountReconciliationTests-normal-path-active-source"
        let settings = try Self.makeSettings(suite: suite)
        let persistedSource = CodexActiveSource.managedAccount(id: UUID())
        settings.codexActiveSource = persistedSource

        let snapshot = settings.codexAccountReconciliationSnapshot

        #expect(snapshot.activeSource == persistedSource)
    }

    @Test
    @MainActor
    func settings_store_debug_managed_store_U_R_L_override_loads_on_disk_accounts() throws {
        let suite = "CodexAccountReconciliationTests-debug-store-url"
        let settings = try Self.makeSettings(suite: suite)
        let stored = ManagedCodexAccount(
            id: UUID(),
            email: "stored@example.com",
            managedHomePath: "/tmp/stored-managed-home",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
        let accounts = ManagedCodexAccountSet(
            version: FileManagedCodexAccountStore.currentVersion,
            accounts: [stored])
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-managed-store-\(UUID().uuidString).json")
        try Self.writeManagedCodexStore(accounts, to: storeURL)

        settings._test_managedCodexAccountStoreURL = storeURL
        settings.codexActiveSource = .managedAccount(id: stored.id)
        defer {
            settings._test_managedCodexAccountStoreURL = nil
            try? FileManager.default.removeItem(at: storeURL)
        }

        let snapshot = settings.codexAccountReconciliationSnapshot

        #expect(snapshot.storedAccounts.map(\.id) == [stored.id])
        #expect(snapshot.storedAccounts.map(\.email) == [stored.email])
        #expect(snapshot.activeStoredAccount?.id == stored.id)
        #expect(snapshot.activeStoredAccount?.email == stored.email)
        #expect(snapshot.activeSource == .managedAccount(id: stored.id))
    }

    @Test
    func live_only_visible_account_is_active_when_active_source_is_live_system() {
        let live = ObservedSystemCodexAccount(
            email: "live@example.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date())
        let projection = CodexVisibleAccountProjection.make(from: CodexAccountReconciliationSnapshot(
            storedAccounts: [],
            activeStoredAccount: nil,
            liveSystemAccount: live,
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .liveSystem,
            hasUnreadableAddedAccountStore: false))

        #expect(projection.visibleAccounts.map(\.email) == ["live@example.com"])
        #expect(projection.activeVisibleAccountID == "live@example.com")
        #expect(projection.liveVisibleAccountID == "live@example.com")
    }

    @Test
    func workspace_hydration_changes_snapshot_equality_and_visible_display_state() {
        let accountID = UUID()
        let baseAccount = ManagedCodexAccount(
            id: accountID,
            email: "user@example.com",
            providerAccountID: "account-live",
            managedHomePath: "/tmp/managed-a",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
        let hydratedAccount = ManagedCodexAccount(
            id: accountID,
            email: "user@example.com",
            providerAccountID: "account-live",
            workspaceLabel: "Team Alpha",
            workspaceAccountID: "account-live",
            managedHomePath: "/tmp/managed-a",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
        let baseSnapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [baseAccount],
            activeStoredAccount: baseAccount,
            liveSystemAccount: nil,
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .managedAccount(id: accountID),
            hasUnreadableAddedAccountStore: false)
        let hydratedSnapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [hydratedAccount],
            activeStoredAccount: hydratedAccount,
            liveSystemAccount: nil,
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .managedAccount(id: accountID),
            hasUnreadableAddedAccountStore: false)

        let baseProjection = CodexVisibleAccountProjection.make(from: baseSnapshot)
        let hydratedProjection = CodexVisibleAccountProjection.make(from: hydratedSnapshot)

        #expect(baseSnapshot != hydratedSnapshot)
        #expect(baseProjection.visibleAccounts.first?.displayName == "user@example.com")
        #expect(hydratedProjection.visibleAccounts.first?.displayName == "user@example.com — Team Alpha")
    }

    @Test
    func matching_live_system_account_does_not_duplicate_stored_identity() {
        let stored = ManagedCodexAccount(
            id: UUID(),
            email: "user@example.com",
            managedHomePath: "/tmp/managed-a",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
        let accounts = ManagedCodexAccountSet(version: 1, accounts: [stored])
        let live = ObservedSystemCodexAccount(
            email: "USER@example.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date())
        let reconciler = DefaultCodexAccountReconciler(
            storeLoader: { accounts },
            systemObserver: StubSystemObserver(account: live),
            activeSource: .managedAccount(id: stored.id),
            baseEnvironment: [:])

        let projection = reconciler.loadVisibleAccounts()

        #expect(projection.visibleAccounts.count == 1)
        #expect(projection.activeVisibleAccountID == "user@example.com")
        #expect(projection.liveVisibleAccountID == "user@example.com")
    }

    @Test
    func matching_live_system_account_prefers_live_workspace_label_and_keeps_stored_fallback() {
        let stored = ManagedCodexAccount(
            id: UUID(),
            email: "user@example.com",
            providerAccountID: "account-live",
            workspaceLabel: "Saved Team",
            workspaceAccountID: "account-live",
            managedHomePath: "/tmp/managed-a",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
        let liveWithLabel = ObservedSystemCodexAccount(
            email: "USER@example.com",
            workspaceLabel: "Live Team",
            workspaceAccountID: "account-live",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date(),
            identity: .providerAccount(id: "account-live"))
        let labeledSnapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [stored],
            activeStoredAccount: stored,
            liveSystemAccount: liveWithLabel,
            matchingStoredAccountForLiveSystemAccount: stored,
            activeSource: .managedAccount(id: stored.id),
            hasUnreadableAddedAccountStore: false,
            storedAccountRuntimeIdentities: [stored.id: .providerAccount(id: "account-live")],
            storedAccountRuntimeEmails: [stored.id: "user@example.com"])
        let liveWithoutLabel = ObservedSystemCodexAccount(
            email: "USER@example.com",
            workspaceLabel: nil,
            workspaceAccountID: "account-live",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date(),
            identity: .providerAccount(id: "account-live"))
        let fallbackSnapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [stored],
            activeStoredAccount: stored,
            liveSystemAccount: liveWithoutLabel,
            matchingStoredAccountForLiveSystemAccount: stored,
            activeSource: .managedAccount(id: stored.id),
            hasUnreadableAddedAccountStore: false,
            storedAccountRuntimeIdentities: [stored.id: .providerAccount(id: "account-live")],
            storedAccountRuntimeEmails: [stored.id: "user@example.com"])
        let liveWithEmptyLabel = ObservedSystemCodexAccount(
            email: "USER@example.com",
            workspaceLabel: "   \n\t  ",
            workspaceAccountID: "account-live",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date(),
            identity: .providerAccount(id: "account-live"))
        let emptyLabelSnapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [stored],
            activeStoredAccount: stored,
            liveSystemAccount: liveWithEmptyLabel,
            matchingStoredAccountForLiveSystemAccount: stored,
            activeSource: .managedAccount(id: stored.id),
            hasUnreadableAddedAccountStore: false,
            storedAccountRuntimeIdentities: [stored.id: .providerAccount(id: "account-live")],
            storedAccountRuntimeEmails: [stored.id: "user@example.com"])

        let labeledProjection = CodexVisibleAccountProjection.make(from: labeledSnapshot)
        let fallbackProjection = CodexVisibleAccountProjection.make(from: fallbackSnapshot)
        let emptyLabelProjection = CodexVisibleAccountProjection.make(from: emptyLabelSnapshot)

        #expect(labeledProjection.visibleAccounts.count == 1)
        #expect(labeledProjection.visibleAccounts.first?.workspaceLabel == "Live Team")
        #expect(labeledProjection.visibleAccounts.first?.displayName == "user@example.com — Live Team")
        #expect(fallbackProjection.visibleAccounts.count == 1)
        #expect(fallbackProjection.visibleAccounts.first?.workspaceLabel == "Saved Team")
        #expect(fallbackProjection.visibleAccounts.first?.displayName == "user@example.com — Saved Team")
        #expect(emptyLabelProjection.visibleAccounts.count == 1)
        #expect(emptyLabelProjection.visibleAccounts.first?.workspaceLabel == "Saved Team")
        #expect(emptyLabelProjection.visibleAccounts.first?.displayName == "user@example.com — Saved Team")
    }

    @Test
    func matching_live_system_account_resolves_merged_row_selection_to_live_system() {
        let stored = ManagedCodexAccount(
            id: UUID(),
            email: "user@example.com",
            managedHomePath: "/tmp/managed-a",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
        let live = ObservedSystemCodexAccount(
            email: "USER@example.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date())
        let snapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [stored],
            activeStoredAccount: stored,
            liveSystemAccount: live,
            matchingStoredAccountForLiveSystemAccount: stored,
            activeSource: .managedAccount(id: stored.id),
            hasUnreadableAddedAccountStore: false)

        let resolution = CodexActiveSourceResolver.resolve(from: snapshot)
        let projection = CodexVisibleAccountProjection.make(from: snapshot)

        #expect(resolution.persistedSource == .managedAccount(id: stored.id))
        #expect(resolution.resolvedSource == .liveSystem)
        #expect(resolution.requiresPersistenceCorrection)
        #expect(projection.activeVisibleAccountID == "user@example.com")
        #expect(projection.source(forVisibleAccountID: "user@example.com") == .liveSystem)
    }

    @Test
    func provider_account_does_not_collapse_with_email_only_live_account_on_same_email() throws {
        let managedHome = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true)
        defer { try? FileManager.default.removeItem(at: managedHome) }
        try Self.writeCodexAuthFile(
            homeURL: managedHome,
            email: "user@example.com",
            plan: "pro",
            accountID: "account-managed")

        let stored = ManagedCodexAccount(
            id: UUID(),
            email: "user@example.com",
            managedHomePath: managedHome.path,
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
        let accounts = ManagedCodexAccountSet(version: 1, accounts: [stored])
        let live = ObservedSystemCodexAccount(
            email: "USER@example.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date(),
            identity: .emailOnly(normalizedEmail: "user@example.com"))
        let reconciler = DefaultCodexAccountReconciler(
            storeLoader: { accounts },
            systemObserver: StubSystemObserver(account: live),
            activeSource: .managedAccount(id: stored.id),
            baseEnvironment: [:])

        let snapshot = reconciler.loadSnapshot()
        let resolution = CodexActiveSourceResolver.resolve(from: snapshot)
        let projection = CodexVisibleAccountProjection.make(from: snapshot)

        #expect(snapshot.matchingStoredAccountForLiveSystemAccount == nil)
        #expect(resolution.resolvedSource == .managedAccount(id: stored.id))
        #expect(projection.visibleAccounts.count == 2)
        #expect(Set(projection.visibleAccounts.map(\.email)) == Set(["user@example.com"]))
        #expect(Set(projection.visibleAccounts.map(\.id)).count == 2)
        #expect(projection.activeVisibleAccountID == projection.visibleAccounts
            .first { $0.selectionSource == .managedAccount(id: stored.id) }?.id)
        #expect(projection.liveVisibleAccountID == projection.visibleAccounts
            .first { $0.selectionSource == .liveSystem }?.id)
    }

    @Test
    func missing_managed_source_resolves_to_live_system_when_live_account_exists() {
        let live = ObservedSystemCodexAccount(
            email: "live@example.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date())
        let missingID = UUID()
        let snapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [],
            activeStoredAccount: nil,
            liveSystemAccount: live,
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .managedAccount(id: missingID),
            hasUnreadableAddedAccountStore: false)

        let resolution = CodexActiveSourceResolver.resolve(from: snapshot)

        #expect(resolution.persistedSource == .managedAccount(id: missingID))
        #expect(resolution.resolvedSource == .liveSystem)
        #expect(resolution.requiresPersistenceCorrection)
    }

    @Test
    func unreadable_managed_source_resolves_to_live_system_when_live_account_exists() {
        let live = ObservedSystemCodexAccount(
            email: "live@example.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date())
        let unreadableID = UUID()
        let snapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [],
            activeStoredAccount: nil,
            liveSystemAccount: live,
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .managedAccount(id: unreadableID),
            hasUnreadableAddedAccountStore: true)

        let resolution = CodexActiveSourceResolver.resolve(from: snapshot)

        #expect(resolution.persistedSource == .managedAccount(id: unreadableID))
        #expect(resolution.resolvedSource == .liveSystem)
        #expect(resolution.requiresPersistenceCorrection)
    }

    @Test
    func managed_account_remains_active_when_active_source_stays_managed_while_live_account_changes() {
        let managed = ManagedCodexAccount(
            id: UUID(),
            email: "managed@example.com",
            managedHomePath: "/tmp/managed-home",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
        let live = ObservedSystemCodexAccount(
            email: "system@example.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date())
        let projection = CodexVisibleAccountProjection.make(from: CodexAccountReconciliationSnapshot(
            storedAccounts: [managed],
            activeStoredAccount: managed,
            liveSystemAccount: live,
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .managedAccount(id: managed.id),
            hasUnreadableAddedAccountStore: false))

        #expect(Set(projection.visibleAccounts.map(\.email)) == [
            "managed@example.com",
            "system@example.com",
        ])
        #expect(projection.activeVisibleAccountID == "managed@example.com")
        #expect(projection.liveVisibleAccountID == "system@example.com")
    }

    @Test
    func live_system_account_that_differs_from_active_stored_account_remains_visible() {
        let active = ManagedCodexAccount(
            id: UUID(),
            email: "managed@example.com",
            managedHomePath: "/tmp/managed-a",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
        let accounts = ManagedCodexAccountSet(version: 1, accounts: [active])
        let live = ObservedSystemCodexAccount(
            email: "system@example.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date())
        let reconciler = DefaultCodexAccountReconciler(
            storeLoader: { accounts },
            systemObserver: StubSystemObserver(account: live),
            activeSource: .managedAccount(id: active.id),
            baseEnvironment: [:])

        let projection = reconciler.loadVisibleAccounts()

        #expect(Set(projection.visibleAccounts.map(\.email)) == ["managed@example.com", "system@example.com"])
        #expect(projection.activeVisibleAccountID == "managed@example.com")
        #expect(projection.liveVisibleAccountID == "system@example.com")
    }

    @Test
    func inactive_stored_account_still_appears_as_visible() {
        let active = ManagedCodexAccount(
            id: UUID(),
            email: "active@example.com",
            managedHomePath: "/tmp/managed-a",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
        let inactive = ManagedCodexAccount(
            id: UUID(),
            email: "inactive@example.com",
            managedHomePath: "/tmp/managed-b",
            createdAt: 4,
            updatedAt: 5,
            lastAuthenticatedAt: 6)
        let accounts = ManagedCodexAccountSet(
            version: 1,
            accounts: [active, inactive])
        let live = ObservedSystemCodexAccount(
            email: "system@example.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date())
        let reconciler = DefaultCodexAccountReconciler(
            storeLoader: { accounts },
            systemObserver: StubSystemObserver(account: live),
            activeSource: .managedAccount(id: active.id),
            baseEnvironment: [:])

        let projection = reconciler.loadVisibleAccounts()

        #expect(Set(projection.visibleAccounts.map(\.email)) == [
            "active@example.com",
            "inactive@example.com",
            "system@example.com",
        ])
        #expect(projection.activeVisibleAccountID == "active@example.com")
        #expect(projection.liveVisibleAccountID == "system@example.com")
    }

    @Test
    func unreadable_account_store_still_exposes_live_system_account_and_degraded_flag() {
        let live = ObservedSystemCodexAccount(
            email: "live@example.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date())
        let reconciler = DefaultCodexAccountReconciler(
            storeLoader: { throw FileManagedCodexAccountStoreError.unsupportedVersion(999) },
            systemObserver: StubSystemObserver(account: live),
            baseEnvironment: [:])

        let projection = reconciler.loadVisibleAccounts()

        #expect(projection.visibleAccounts.map(\.email) == ["live@example.com"])
        #expect(projection.activeVisibleAccountID == "live@example.com")
        #expect(projection.liveVisibleAccountID == "live@example.com")
        #expect(projection.hasUnreadableAddedAccountStore)
    }

    @Test
    func whitespace_only_live_email_is_ignored() {
        let accounts = ManagedCodexAccountSet(version: 1, accounts: [])
        let live = ObservedSystemCodexAccount(
            email: "   \n\t  ",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date())
        let reconciler = DefaultCodexAccountReconciler(
            storeLoader: { accounts },
            systemObserver: StubSystemObserver(account: live),
            baseEnvironment: [:])

        let projection = reconciler.loadVisibleAccounts()

        #expect(projection.visibleAccounts.isEmpty)
        #expect(projection.activeVisibleAccountID == nil)
        #expect(projection.liveVisibleAccountID == nil)
    }

    @Test
    @MainActor
    func settings_store_can_override_active_source_to_live_system() throws {
        let suite = "CodexAccountReconciliationTests-live-source-override"
        let settings = try Self.makeSettings(suite: suite)
        let managed = ManagedCodexAccount(
            id: UUID(),
            email: "managed@example.com",
            managedHomePath: "/tmp/managed-home",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
        let live = ObservedSystemCodexAccount(
            email: "system@example.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date())
        settings._test_activeManagedCodexAccount = managed
        settings._test_liveSystemCodexAccount = live
        settings.codexActiveSource = .liveSystem
        defer {
            settings._test_activeManagedCodexAccount = nil
            settings._test_liveSystemCodexAccount = nil
        }

        let snapshot = settings.codexAccountReconciliationSnapshot
        let projection = settings.codexVisibleAccountProjection

        #expect(settings.codexActiveSource == .liveSystem)
        #expect(snapshot.activeSource == .liveSystem)
        #expect(projection.activeVisibleAccountID == "system@example.com")
        #expect(projection.liveVisibleAccountID == "system@example.com")
    }

    @Test
    @MainActor
    func selecting_merged_visible_account_persists_live_system_source() throws {
        let suite = "CodexAccountReconciliationTests-select-merged-visible-account"
        let settings = try Self.makeSettings(suite: suite)
        let managed = ManagedCodexAccount(
            id: UUID(),
            email: "same@example.com",
            managedHomePath: "/tmp/managed-home",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
        let live = ObservedSystemCodexAccount(
            email: "SAME@example.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date())
        settings._test_activeManagedCodexAccount = managed
        settings._test_liveSystemCodexAccount = live
        settings.codexActiveSource = .managedAccount(id: managed.id)
        defer {
            settings._test_activeManagedCodexAccount = nil
            settings._test_liveSystemCodexAccount = nil
        }

        let didSelect = settings.selectCodexVisibleAccount(id: "same@example.com")

        #expect(didSelect)
        #expect(settings.codexActiveSource == .liveSystem)
        #expect(settings.codexResolvedActiveSource == .liveSystem)
    }

    @Test
    @MainActor
    func selecting_authenticated_managed_account_prefers_live_system_when_visible_row_is_merged() throws {
        let suite = "CodexAccountReconciliationTests-select-authenticated-managed-merged"
        let settings = try Self.makeSettings(suite: suite)
        let managed = ManagedCodexAccount(
            id: UUID(),
            email: "same@example.com",
            managedHomePath: "/tmp/managed-home",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
        let live = ObservedSystemCodexAccount(
            email: "SAME@example.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date())
        settings._test_activeManagedCodexAccount = managed
        settings._test_liveSystemCodexAccount = live
        settings.codexActiveSource = .managedAccount(id: UUID())
        defer {
            settings._test_activeManagedCodexAccount = nil
            settings._test_liveSystemCodexAccount = nil
        }

        settings.selectAuthenticatedManagedCodexAccount(managed)

        #expect(settings.codexActiveSource == .liveSystem)
        #expect(settings.codexResolvedActiveSource == .liveSystem)
    }

    @Test
    @MainActor
    func selecting_authenticated_managed_account_keeps_managed_source_for_split_identity_rows() throws {
        let suite = "CodexAccountReconciliationTests-select-authenticated-managed-split"
        let settings = try Self.makeSettings(suite: suite)
        let managedHome = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true)
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            settings._test_managedCodexAccountStoreURL = nil
            settings._test_liveSystemCodexAccount = nil
            try? FileManager.default.removeItem(at: managedHome)
            try? FileManager.default.removeItem(at: storeURL)
        }

        try Self.writeCodexAuthFile(
            homeURL: managedHome,
            email: "same@example.com",
            plan: "pro",
            accountID: "account-managed")
        let managed = ManagedCodexAccount(
            id: UUID(),
            email: "same@example.com",
            managedHomePath: managedHome.path,
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
        try Self.writeManagedCodexStore(
            ManagedCodexAccountSet(version: FileManagedCodexAccountStore.currentVersion, accounts: [managed]),
            to: storeURL)

        settings._test_managedCodexAccountStoreURL = storeURL
        settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: "SAME@example.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date(),
            identity: .emailOnly(normalizedEmail: "same@example.com"))
        settings.codexActiveSource = .liveSystem

        let projection = settings.codexVisibleAccountProjection
        #expect(projection.visibleAccounts.count == 2)

        settings.selectAuthenticatedManagedCodexAccount(managed)

        #expect(settings.codexActiveSource == .managedAccount(id: managed.id))
        #expect(settings.codexResolvedActiveSource == .managedAccount(id: managed.id))
    }
}

private struct StubSystemObserver: CodexSystemAccountObserving {
    let account: ObservedSystemCodexAccount?

    func loadSystemAccount(environment _: [String: String]) throws -> ObservedSystemCodexAccount? {
        self.account
    }
}

extension CodexAccountReconciliationTests {
    private static func writeManagedCodexStore(_ accounts: ManagedCodexAccountSet, to storeURL: URL) throws {
        let store = FileManagedCodexAccountStore(fileURL: storeURL)
        try store.storeAccounts(accounts)
    }

    private static func writeCodexAuthFile(
        homeURL: URL,
        email: String,
        plan: String,
        accountID: String? = nil) throws
    {
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        var tokens: [String: Any] = [
            "accessToken": "access-token",
            "refreshToken": "refresh-token",
            "idToken": Self.fakeJWT(email: email, plan: plan, accountID: accountID),
        ]
        if let accountID {
            tokens["account_id"] = accountID
        }
        let auth = ["tokens": tokens]
        let data = try JSONSerialization.data(withJSONObject: auth)
        try data.write(to: homeURL.appendingPathComponent("auth.json"))
    }

    private static func fakeJWT(email: String, plan: String, accountID: String? = nil) -> String {
        let header = (try? JSONSerialization.data(withJSONObject: ["alg": "none"])) ?? Data()
        var payloadObject: [String: Any] = [
            "email": email,
            "chatgpt_plan_type": plan,
        ]
        if let accountID {
            payloadObject["https://api.openai.com/auth"] = [
                "chatgpt_account_id": accountID,
            ]
        }
        let payload = (try? JSONSerialization.data(withJSONObject: payloadObject)) ?? Data()

        func base64URL(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
        }

        return "\(base64URL(header)).\(base64URL(payload))."
    }
}
