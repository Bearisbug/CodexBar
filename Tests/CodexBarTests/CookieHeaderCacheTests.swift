import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CookieHeaderCacheTests {
    private struct WrongEntry: Codable {
        let value: String
    }

    @Test
    func stores_and_loads_entry() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }

        let provider: UsageProvider = .codex
        let storedAt = Date(timeIntervalSince1970: 0)
        CookieHeaderCache.store(
            provider: provider,
            cookieHeader: "auth=abc",
            sourceLabel: "Chrome",
            now: storedAt)

        let loaded = CookieHeaderCache.load(provider: provider)
        defer { CookieHeaderCache.clear(provider: provider) }

        #expect(loaded?.cookieHeader == "auth=abc")
        #expect(loaded?.sourceLabel == "Chrome")
        #expect(loaded?.storedAt == storedAt)
    }

    @Test
    func conditional_mutation_does_not_overwrite_or_clear_a_newer_entry() {
        self.withIsolatedCookieCache {
            CookieHeaderCache.store(
                provider: .claude,
                cookieHeader: "sessionKey=sk-ant-initial",
                sourceLabel: "Chrome")
            let loaded = CookieHeaderCache.load(provider: .claude)
            #expect(loaded != nil)
            guard let initial = loaded else { return }

            let renewed = CookieHeaderCache.storeIfCurrent(
                provider: .claude,
                expected: initial,
                cookieHeader: "sessionKey=sk-ant-newer",
                sourceLabel: "Chrome")
            let staleStore = CookieHeaderCache.storeIfCurrent(
                provider: .claude,
                expected: initial,
                cookieHeader: "sessionKey=sk-ant-older",
                sourceLabel: "Chrome")
            let staleClear = CookieHeaderCache.clearIfCurrent(provider: .claude, expected: initial)

            #expect(renewed)
            #expect(!staleStore)
            #expect(!staleClear)
            #expect(CookieHeaderCache.load(provider: .claude)?.cookieHeader == "sessionKey=sk-ant-newer")
        }
    }

    @Test
    func conditional_clear_failure_still_permits_replacing_the_same_entry() {
        self.withIsolatedCookieCache {
            CookieHeaderCache.store(
                provider: .claude,
                cookieHeader: "sessionKey=sk-ant-stale",
                sourceLabel: "Chrome")
            let loaded = CookieHeaderCache.load(provider: .claude)
            #expect(loaded != nil)
            guard let stale = loaded else { return }

            let cleared = KeychainCacheStore.withClearFailureStatusOverrideForTesting(errSecInteractionNotAllowed) {
                CookieHeaderCache.clearIfCurrent(provider: .claude, expected: stale)
            }
            let replaced = CookieHeaderCache.storeIfCurrent(
                provider: .claude,
                expected: stale,
                cookieHeader: "sessionKey=sk-ant-fresh",
                sourceLabel: "Safari")

            #expect(!cleared)
            #expect(replaced)
            #expect(CookieHeaderCache.load(provider: .claude)?.cookieHeader == "sessionKey=sk-ant-fresh")
        }
    }

    @Test
    func conditional_mutation_recognizes_a_legacy_entry_after_migration_failure() {
        self.withIsolatedCookieCache {
            let legacy = CookieHeaderCache.Entry(
                cookieHeader: "sessionKey=sk-ant-legacy",
                storedAt: Date(timeIntervalSince1970: 1),
                sourceLabel: "Chrome")
            CookieHeaderCache.store(legacy, to: CookieHeaderCache.legacyURLForTesting(provider: .claude))

            let loaded = KeychainCacheStore.withStoreFailureStatusOverrideForTesting(errSecInteractionNotAllowed) {
                CookieHeaderCache.load(provider: .claude)
            }
            #expect(loaded?.cookieHeader == legacy.cookieHeader)
            guard let loaded else { return }

            let cleared = CookieHeaderCache.clearIfCurrent(provider: .claude, expected: loaded)
            let replaced = CookieHeaderCache.storeIfCurrent(
                provider: .claude,
                expected: nil,
                cookieHeader: "sessionKey=sk-ant-fresh",
                sourceLabel: "Safari")

            #expect(cleared)
            #expect(replaced)
            #expect(CookieHeaderCache.load(provider: .claude)?.cookieHeader == "sessionKey=sk-ant-fresh")
        }
    }

    @Test
    func stores_separate_codex_entries_per_managed_account_scope() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }

        let provider: UsageProvider = .codex
        let accountA = UUID()
        let accountB = UUID()

        CookieHeaderCache.store(
            provider: provider,
            scope: .managedAccount(accountA),
            cookieHeader: "auth=account-a",
            sourceLabel: "Chrome")
        CookieHeaderCache.store(
            provider: provider,
            scope: .managedAccount(accountB),
            cookieHeader: "auth=account-b",
            sourceLabel: "Safari")
        defer {
            CookieHeaderCache.clear(provider: provider, scope: .managedAccount(accountA))
            CookieHeaderCache.clear(provider: provider, scope: .managedAccount(accountB))
        }

        #expect(CookieHeaderCache.load(provider: provider, scope: .managedAccount(accountA))?
            .cookieHeader == "auth=account-a")
        #expect(CookieHeaderCache.load(provider: provider, scope: .managedAccount(accountB))?
            .cookieHeader == "auth=account-b")
        #expect(CookieHeaderCache.load(provider: provider)?.cookieHeader == nil)
    }

    @Test
    func profile_home_scopes_isolate_same_email_sessions_without_exposing_paths() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }

        let provider: UsageProvider = .codex
        let profileA = CookieHeaderCache.Scope.profileHome("/tmp/codex-profile-a")
        let profileB = CookieHeaderCache.Scope.profileHome("/tmp/codex-profile-b")
        CookieHeaderCache.store(
            provider: provider,
            scope: profileA,
            cookieHeader: "auth=profile-a",
            sourceLabel: "Chrome")
        CookieHeaderCache.store(
            provider: provider,
            scope: profileB,
            cookieHeader: "auth=profile-b",
            sourceLabel: "Chrome")
        defer {
            CookieHeaderCache.clear(provider: provider, scope: profileA)
            CookieHeaderCache.clear(provider: provider, scope: profileB)
        }

        #expect(CookieHeaderCache.load(provider: provider, scope: profileA)?.cookieHeader == "auth=profile-a")
        #expect(CookieHeaderCache.load(provider: provider, scope: profileB)?.cookieHeader == "auth=profile-b")
        #expect(CookieHeaderCache.load(provider: provider) == nil)
        #expect(profileA.isolationIdentifier != profileB.isolationIdentifier)
        #expect(!profileA.isolationIdentifier.contains("codex-profile-a"))
    }

    @Test
    func provider_global_scope_remains_available_without_managed_account() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }

        let provider: UsageProvider = .codex

        CookieHeaderCache.store(
            provider: provider,
            cookieHeader: "auth=system",
            sourceLabel: "Chrome")
        defer { CookieHeaderCache.clear(provider: provider) }

        #expect(CookieHeaderCache.load(provider: provider)?.cookieHeader == "auth=system")
        #expect(CookieHeaderCache.load(provider: provider, scope: .managedAccount(UUID())) == nil)
    }

    @Test
    func claude_cookie_scopes_isolate_browser_cache_from_managed_accounts() {
        self.withIsolatedCookieCache {
            let accountA = UUID()
            let accountB = UUID()

            CookieHeaderCache.store(
                provider: .claude,
                cookieHeader: "sessionKey=sk-ant-browser",
                sourceLabel: "Safari")
            CookieHeaderCache.store(
                provider: .claude,
                scope: .managedAccount(accountA),
                cookieHeader: "sessionKey=sk-ant-account-a",
                sourceLabel: "Chrome")
            CookieHeaderCache.store(
                provider: .claude,
                scope: .managedAccount(accountB),
                cookieHeader: "sessionKey=sk-ant-account-b",
                sourceLabel: "Edge")

            #expect(CookieHeaderCache.load(provider: .claude)?.cookieHeader == "sessionKey=sk-ant-browser")
            #expect(CookieHeaderCache.load(provider: .claude, scope: .managedAccount(accountA))?
                .cookieHeader == "sessionKey=sk-ant-account-a")
            #expect(CookieHeaderCache.load(provider: .claude, scope: .managedAccount(accountB))?
                .cookieHeader == "sessionKey=sk-ant-account-b")

            CookieHeaderCache.clear(provider: .claude)
            #expect(CookieHeaderCache.load(provider: .claude) == nil)
            #expect(CookieHeaderCache.load(provider: .claude, scope: .managedAccount(accountA))?
                .cookieHeader == "sessionKey=sk-ant-account-a")
            #expect(CookieHeaderCache.load(provider: .claude, scope: .managedAccount(accountB))?
                .cookieHeader == "sessionKey=sk-ant-account-b")

            CookieHeaderCache.clear(provider: .claude, scope: .managedAccount(accountA))
            #expect(CookieHeaderCache.load(provider: .claude, scope: .managedAccount(accountA)) == nil)
            #expect(CookieHeaderCache.load(provider: .claude, scope: .managedAccount(accountB))?
                .cookieHeader == "sessionKey=sk-ant-account-b")
        }
    }

    @Test
    func claude_unreadable_managed_store_sentinel_is_isolated_from_account_cookies() {
        self.withIsolatedCookieCache {
            let accountID = UUID()

            CookieHeaderCache.store(
                provider: .claude,
                cookieHeader: "sessionKey=sk-ant-global",
                sourceLabel: "Safari")
            CookieHeaderCache.store(
                provider: .claude,
                scope: .managedAccount(accountID),
                cookieHeader: "sessionKey=sk-ant-account",
                sourceLabel: "Chrome")
            CookieHeaderCache.store(
                provider: .claude,
                scope: .managedStoreUnreadable,
                cookieHeader: "sessionKey=sk-ant-unreadable-store",
                sourceLabel: "Unreadable managed account store")

            CookieHeaderCache.clear(provider: .claude, scope: .managedAccount(accountID))
            #expect(CookieHeaderCache.load(provider: .claude, scope: .managedAccount(accountID)) == nil)
            #expect(CookieHeaderCache.load(provider: .claude)?.cookieHeader == "sessionKey=sk-ant-global")
            #expect(CookieHeaderCache.load(provider: .claude, scope: .managedStoreUnreadable)?
                .cookieHeader == "sessionKey=sk-ant-unreadable-store")

            CookieHeaderCache.clear(provider: .claude)
            #expect(CookieHeaderCache.load(provider: .claude) == nil)
            #expect(CookieHeaderCache.load(provider: .claude, scope: .managedStoreUnreadable)?
                .cookieHeader == "sessionKey=sk-ant-unreadable-store")

            let cleared = CookieHeaderCache.clearAllScopesDetailed(provider: .claude)
            #expect(cleared == CookieHeaderCache.ClearSummary(clearedCount: 1, failedCount: 0))
            #expect(CookieHeaderCache.load(provider: .claude, scope: .managedStoreUnreadable) == nil)
        }
    }

    @Test
    func claude_clear_all_scopes_does_not_remove_other_provider_cookie_caches() {
        self.withIsolatedCookieCache {
            let claudeAccount = UUID()
            let codexAccount = UUID()

            CookieHeaderCache.store(
                provider: .claude,
                cookieHeader: "sessionKey=sk-ant-claude-global",
                sourceLabel: "Safari")
            CookieHeaderCache.store(
                provider: .claude,
                scope: .managedAccount(claudeAccount),
                cookieHeader: "sessionKey=sk-ant-claude-account",
                sourceLabel: "Chrome")
            CookieHeaderCache.store(provider: .codex, cookieHeader: "auth=codex-global", sourceLabel: "Chrome")
            CookieHeaderCache.store(
                provider: .codex,
                scope: .managedAccount(codexAccount),
                cookieHeader: "auth=codex-account",
                sourceLabel: "Safari")
            CookieHeaderCache.store(provider: .perplexity, cookieHeader: "pplx=web", sourceLabel: "Chrome")

            let cleared = CookieHeaderCache.clearAllScopesDetailed(provider: .claude)

            #expect(cleared == CookieHeaderCache.ClearSummary(clearedCount: 2, failedCount: 0))
            #expect(CookieHeaderCache.load(provider: .claude) == nil)
            #expect(CookieHeaderCache.load(provider: .claude, scope: .managedAccount(claudeAccount)) == nil)
            #expect(CookieHeaderCache.load(provider: .codex)?.cookieHeader == "auth=codex-global")
            #expect(CookieHeaderCache.load(provider: .codex, scope: .managedAccount(codexAccount))?
                .cookieHeader == "auth=codex-account")
            #expect(CookieHeaderCache.load(provider: .perplexity)?.cookieHeader == "pplx=web")
        }
    }

    @Test
    func migrates_legacy_file_to_keychain() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }

        let legacyBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        CookieHeaderCache.setLegacyBaseURLOverrideForTesting(legacyBase)
        defer { CookieHeaderCache.setLegacyBaseURLOverrideForTesting(nil) }

        let provider: UsageProvider = .codex
        let storedAt = Date(timeIntervalSince1970: 0)
        let entry = CookieHeaderCache.Entry(
            cookieHeader: "auth=legacy",
            storedAt: storedAt,
            sourceLabel: "Legacy")
        let legacyURL = legacyBase.appendingPathComponent("\(provider.rawValue)-cookie.json")

        CookieHeaderCache.store(entry, to: legacyURL)
        #expect(FileManager.default.fileExists(atPath: legacyURL.path) == true)

        let loaded = CookieHeaderCache.load(provider: provider)
        defer { CookieHeaderCache.clear(provider: provider) }

        #expect(loaded?.cookieHeader == "auth=legacy")
        #expect(loaded?.sourceLabel == "Legacy")
        #expect(loaded?.storedAt == storedAt)
        #expect(FileManager.default.fileExists(atPath: legacyURL.path) == false)

        let loadedAgain = CookieHeaderCache.load(provider: provider)
        #expect(loadedAgain?.cookieHeader == "auth=legacy")
    }

    @Test
    func serialized_load_migrates_legacy_file_to_keychain() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }

        let legacyBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        CookieHeaderCache.setLegacyBaseURLOverrideForTesting(legacyBase)
        defer { CookieHeaderCache.setLegacyBaseURLOverrideForTesting(nil) }

        let provider: UsageProvider = .codex
        let legacyURL = legacyBase.appendingPathComponent("\(provider.rawValue)-cookie.json")
        CookieHeaderCache.store(
            CookieHeaderCache.Entry(
                cookieHeader: "auth=legacy",
                storedAt: Date(timeIntervalSince1970: 0),
                sourceLabel: "Legacy"),
            to: legacyURL)

        let loaded = CookieHeaderCache.loadSerialized(provider: provider)
        defer { CookieHeaderCache.clear(provider: provider) }

        #expect(loaded?.cookieHeader == "auth=legacy")
        #expect(FileManager.default.fileExists(atPath: legacyURL.path) == false)
        #expect(CookieHeaderCache.load(provider: provider)?.cookieHeader == "auth=legacy")
    }

    #if os(macOS)
    @Test
    func temporary_keychain_unavailability_returns_nil_without_migrating_legacy_file() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }

        let legacyBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        CookieHeaderCache.setLegacyBaseURLOverrideForTesting(legacyBase)
        defer { CookieHeaderCache.setLegacyBaseURLOverrideForTesting(nil) }

        let provider: UsageProvider = .codex
        let legacyURL = legacyBase.appendingPathComponent("\(provider.rawValue)-cookie.json")
        CookieHeaderCache.store(
            CookieHeaderCache.Entry(
                cookieHeader: "auth=legacy",
                storedAt: Date(timeIntervalSince1970: 0),
                sourceLabel: "Legacy"),
            to: legacyURL)
        #expect(FileManager.default.fileExists(atPath: legacyURL.path) == true)

        let loaded = KeychainCacheStore.withLoadFailureStatusOverrideForTesting(errSecInteractionNotAllowed) {
            CookieHeaderCache.load(provider: provider)
        }

        #expect(loaded == nil)
        #expect(FileManager.default.fileExists(atPath: legacyURL.path) == true)

        switch KeychainCacheStore.load(key: .cookie(provider: provider), as: CookieHeaderCache.Entry.self) {
        case .missing:
            #expect(true)
        case .found, .temporarilyUnavailable, .invalid:
            #expect(Bool(false), "Expected temporary miss not to migrate legacy cache")
        }
    }
    #endif

    @Test
    func invalid_keychain_cache_is_cleared() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }

        let legacyBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        CookieHeaderCache.setLegacyBaseURLOverrideForTesting(legacyBase)
        defer { CookieHeaderCache.setLegacyBaseURLOverrideForTesting(nil) }

        let provider: UsageProvider = .codex
        let key = KeychainCacheStore.Key.cookie(provider: provider)
        KeychainCacheStore.store(key: key, entry: WrongEntry(value: "not-a-cookie-entry"))

        #expect(CookieHeaderCache.load(provider: provider) == nil)

        switch KeychainCacheStore.load(key: key, as: CookieHeaderCache.Entry.self) {
        case .missing:
            #expect(true)
        case .found, .temporarilyUnavailable, .invalid:
            #expect(Bool(false), "Expected invalid cookie cache to be cleared")
        }
    }

    @Test
    func clear_all_scopes_removes_global_scoped_invalid_and_legacy_cookie_entries() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }

        let legacyBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        CookieHeaderCache.setLegacyBaseURLOverrideForTesting(legacyBase)
        defer { CookieHeaderCache.setLegacyBaseURLOverrideForTesting(nil) }

        let provider: UsageProvider = .codex
        let accountID = UUID()
        CookieHeaderCache.store(provider: provider, cookieHeader: "auth=global", sourceLabel: "Chrome")
        CookieHeaderCache.store(
            provider: provider,
            scope: .managedAccount(accountID),
            cookieHeader: "auth=scoped",
            sourceLabel: "Chrome")
        KeychainCacheStore.store(
            key: .cookie(provider: provider, scopeIdentifier: "managed-store-unreadable"),
            entry: WrongEntry(value: "invalid"))
        CookieHeaderCache.store(
            CookieHeaderCache.Entry(
                cookieHeader: "auth=legacy",
                storedAt: Date(timeIntervalSince1970: 0),
                sourceLabel: "Legacy"),
            to: CookieHeaderCache.legacyURLForTesting(provider: provider))

        let cleared = CookieHeaderCache.clearAllScopesDetailed(provider: provider)

        #expect(cleared == CookieHeaderCache.ClearSummary(clearedCount: 4, failedCount: 0))
        #expect(!CookieHeaderCache.hasKeychainEntryForTesting(provider: provider))
        #expect(!CookieHeaderCache.hasKeychainEntryForTesting(provider: provider, scope: .managedAccount(accountID)))
        #expect(!CookieHeaderCache.hasKeychainEntryForTesting(provider: provider, scope: .managedStoreUnreadable))
        #expect(!CookieHeaderCache.hasLegacyEntryForTesting(provider: provider))
    }

    @Test
    func loadForDisplay_memoizes_keychain_lookups() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }
        CookieHeaderCache.resetDisplayCacheForTesting()
        defer { CookieHeaderCache.resetDisplayCacheForTesting() }

        let provider: UsageProvider = .codex
        CookieHeaderCache.store(provider: provider, cookieHeader: "auth=abc", sourceLabel: "Chrome")

        #expect(CookieHeaderCache.loadForDisplay(provider: provider)?.cookieHeader == "auth=abc")

        // Remove the backing entry without going through CookieHeaderCache: the strict load
        // sees the change, the display path keeps serving the memoized snapshot.
        KeychainCacheStore.clear(key: .cookie(provider: provider))
        #expect(CookieHeaderCache.load(provider: provider) == nil)
        #expect(CookieHeaderCache.loadForDisplay(provider: provider)?.cookieHeader == "auth=abc")
    }

    @Test
    func loadForDisplay_memoizes_missing_entries() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }
        CookieHeaderCache.resetDisplayCacheForTesting()
        defer { CookieHeaderCache.resetDisplayCacheForTesting() }

        let provider: UsageProvider = .codex
        #expect(CookieHeaderCache.loadForDisplay(provider: provider) == nil)

        KeychainCacheStore.store(
            key: .cookie(provider: provider),
            entry: CookieHeaderCache.Entry(
                cookieHeader: "auth=behind-the-back",
                storedAt: Date(timeIntervalSince1970: 0),
                sourceLabel: "Chrome"))
        defer { KeychainCacheStore.clear(key: .cookie(provider: provider)) }
        #expect(CookieHeaderCache.loadForDisplay(provider: provider) == nil)
    }

    @Test
    func loadForDisplay_migrates_legacy_cache_asynchronously() async throws {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }
        CookieHeaderCache.resetDisplayCacheForTesting()
        defer { CookieHeaderCache.resetDisplayCacheForTesting() }

        let legacyBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        CookieHeaderCache.setLegacyBaseURLOverrideForTesting(legacyBase)
        defer { CookieHeaderCache.setLegacyBaseURLOverrideForTesting(nil) }

        let provider: UsageProvider = .codex
        CookieHeaderCache.store(
            CookieHeaderCache.Entry(
                cookieHeader: "auth=legacy-display",
                storedAt: Date(timeIntervalSince1970: 0),
                sourceLabel: "Legacy"),
            to: CookieHeaderCache.legacyURLForTesting(provider: provider))

        #expect(CookieHeaderCache.loadForDisplay(provider: provider)?.cookieHeader == "auth=legacy-display")
        for _ in 0..<500 {
            if !CookieHeaderCache.hasLegacyEntryForTesting(provider: provider),
               CookieHeaderCache.hasKeychainEntryForTesting(provider: provider)
            {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!CookieHeaderCache.hasLegacyEntryForTesting(provider: provider))
        #expect(CookieHeaderCache.hasKeychainEntryForTesting(provider: provider))
        CookieHeaderCache.clear(provider: provider)
    }

    @Test
    func delayed_legacy_migration_cannot_restore_a_cleared_cache() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }
        CookieHeaderCache.resetDisplayCacheForTesting()
        defer { CookieHeaderCache.resetDisplayCacheForTesting() }

        let legacyBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        CookieHeaderCache.setLegacyBaseURLOverrideForTesting(legacyBase)
        defer { CookieHeaderCache.setLegacyBaseURLOverrideForTesting(nil) }

        let provider: UsageProvider = .codex
        CookieHeaderCache.store(
            CookieHeaderCache.Entry(
                cookieHeader: "auth=legacy-display",
                storedAt: Date(timeIntervalSince1970: 0),
                sourceLabel: "Legacy"),
            to: CookieHeaderCache.legacyURLForTesting(provider: provider))

        CookieHeaderCache.clear(provider: provider)
        #expect(CookieHeaderCache.migrateLegacyEntryIfNeededForTesting(provider: provider) == nil)
        #expect(!CookieHeaderCache.hasLegacyEntryForTesting(provider: provider))
        #expect(!CookieHeaderCache.hasKeychainEntryForTesting(provider: provider))
    }

    @Test
    func legacy_URL_override_supports_concurrent_teardown_reads() {
        let legacyBases = [
            FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
        ]
        defer { CookieHeaderCache.setLegacyBaseURLOverrideForTesting(nil) }

        DispatchQueue.concurrentPerform(iterations: 5000) { index in
            if index.isMultiple(of: 3) {
                CookieHeaderCache.setLegacyBaseURLOverrideForTesting(legacyBases[index % legacyBases.count])
            } else if index.isMultiple(of: 5) {
                CookieHeaderCache.setLegacyBaseURLOverrideForTesting(nil)
            } else {
                _ = CookieHeaderCache.legacyURLForTesting(provider: .codex)
            }
        }

        CookieHeaderCache.setLegacyBaseURLOverrideForTesting(legacyBases[0])
        #expect(
            CookieHeaderCache.legacyURLForTesting(provider: .codex)
                == legacyBases[0].appendingPathComponent("codex-cookie.json"))
    }

    #if os(macOS)
    @Test
    func loadForDisplay_throttles_temporary_keychain_unavailability_then_retries() async throws {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }
        CookieHeaderCache.resetDisplayCacheForTesting()
        defer { CookieHeaderCache.resetDisplayCacheForTesting() }
        CookieHeaderCache.setDisplayUnavailableRetryIntervalOverrideForTesting(0.05)
        defer { CookieHeaderCache.setDisplayUnavailableRetryIntervalOverrideForTesting(nil) }

        let provider: UsageProvider = .codex
        KeychainCacheStore.store(
            key: .cookie(provider: provider),
            entry: CookieHeaderCache.Entry(
                cookieHeader: "auth=available-after-retry",
                storedAt: Date(timeIntervalSince1970: 0),
                sourceLabel: "Chrome"))

        let unavailable = KeychainCacheStore.withLoadFailureStatusOverrideForTesting(errSecInteractionNotAllowed) {
            CookieHeaderCache.loadForDisplay(provider: provider)
        }

        #expect(unavailable == nil)
        #expect(CookieHeaderCache.loadForDisplay(provider: provider) == nil)

        try await Task.sleep(for: .milliseconds(60))
        var retried: CookieHeaderCache.Entry?
        for _ in 0..<500 {
            retried = CookieHeaderCache.loadForDisplay(provider: provider)
            if retried != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(retried?.cookieHeader == "auth=available-after-retry")
    }

    @Test
    func temporary_first_display_read_returns_a_concurrent_store() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }
        CookieHeaderCache.resetDisplayCacheForTesting()
        defer { CookieHeaderCache.resetDisplayCacheForTesting() }

        let provider: UsageProvider = .codex
        _ = CookieHeaderCache.beginDisplayReadGenerationForTesting(provider: provider)
        CookieHeaderCache.store(provider: provider, cookieHeader: "auth=concurrent", sourceLabel: "Chrome")

        #expect(CookieHeaderCache.currentDisplayEntryForTesting(provider: provider)?
            .cookieHeader == "auth=concurrent")
    }

    @Test
    func failed_keychain_mutations_preserve_the_display_snapshot() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }
        CookieHeaderCache.resetDisplayCacheForTesting()
        defer { CookieHeaderCache.resetDisplayCacheForTesting() }

        let provider: UsageProvider = .codex
        CookieHeaderCache.store(provider: provider, cookieHeader: "auth=old", sourceLabel: "Chrome")
        #expect(CookieHeaderCache.loadForDisplay(provider: provider)?.cookieHeader == "auth=old")

        KeychainCacheStore.withStoreFailureStatusOverrideForTesting(errSecInteractionNotAllowed) {
            CookieHeaderCache.store(provider: provider, cookieHeader: "auth=new", sourceLabel: "Safari")
        }
        #expect(CookieHeaderCache.loadForDisplay(provider: provider)?.cookieHeader == "auth=old")

        let cleared = KeychainCacheStore.withClearFailureStatusOverrideForTesting(errSecInteractionNotAllowed) {
            CookieHeaderCache.clearDetailed(provider: provider)
        }
        #expect(cleared == CookieHeaderCache.ClearSummary(clearedCount: 0, failedCount: 1))
        #expect(CookieHeaderCache.loadForDisplay(provider: provider)?.cookieHeader == "auth=old")
        #expect(CookieHeaderCache.load(provider: provider)?.cookieHeader == "auth=old")
    }

    @Test
    func legacy_removal_invalidates_a_snapshot_after_failed_keychain_clear() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }
        CookieHeaderCache.resetDisplayCacheForTesting()
        defer { CookieHeaderCache.resetDisplayCacheForTesting() }

        KeychainCacheStore.withServiceOverrideForTesting("legacy-clear-\(UUID().uuidString)") {
            let legacyBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            CookieHeaderCache.setLegacyBaseURLOverrideForTesting(legacyBase)
            defer { CookieHeaderCache.setLegacyBaseURLOverrideForTesting(nil) }

            let provider: UsageProvider = .codex
            CookieHeaderCache.store(
                CookieHeaderCache.Entry(
                    cookieHeader: "auth=legacy",
                    storedAt: Date(timeIntervalSince1970: 0),
                    sourceLabel: "Legacy"),
                to: CookieHeaderCache.legacyURLForTesting(provider: provider))

            let displayed = KeychainCacheStore.withStoreFailureStatusOverrideForTesting(errSecInteractionNotAllowed) {
                CookieHeaderCache.loadForDisplay(provider: provider)
            }
            #expect(displayed?.cookieHeader == "auth=legacy")

            let cleared = KeychainCacheStore.withClearFailureStatusOverrideForTesting(errSecInteractionNotAllowed) {
                CookieHeaderCache.clearDetailed(provider: provider)
            }

            #expect(cleared == CookieHeaderCache.ClearSummary(clearedCount: 1, failedCount: 1))
            #expect(!CookieHeaderCache.hasLegacyEntryForTesting(provider: provider))
            #expect(CookieHeaderCache.loadForDisplay(provider: provider) == nil)
        }
    }

    @Test
    func clear_all_reports_keychain_enumeration_failure() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }

        let summary = KeychainCacheStore.withKeysFailureStatusOverrideForTesting(errSecInteractionNotAllowed) {
            CookieHeaderCache.clearAllDetailed()
        }

        #expect(summary.failedCount >= 1)
    }

    @Test
    func clear_reports_legacy_file_deletion_failure() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }

        let legacyBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        CookieHeaderCache.setLegacyBaseURLOverrideForTesting(legacyBase)
        defer { CookieHeaderCache.setLegacyBaseURLOverrideForTesting(nil) }

        let provider: UsageProvider = .codex
        CookieHeaderCache.store(
            CookieHeaderCache.Entry(
                cookieHeader: "auth=legacy",
                storedAt: Date(timeIntervalSince1970: 0),
                sourceLabel: "Legacy"),
            to: CookieHeaderCache.legacyURLForTesting(provider: provider))

        let summary = CookieHeaderCache.withLegacyRemovalFailureForTesting {
            CookieHeaderCache.clearDetailed(provider: provider)
        }

        #expect(summary.failedCount == 1)
        #expect(CookieHeaderCache.hasLegacyEntryForTesting(provider: provider))
    }
    #endif

    @Test
    func store_and_clear_update_the_display_snapshot_immediately() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }
        CookieHeaderCache.resetDisplayCacheForTesting()
        defer { CookieHeaderCache.resetDisplayCacheForTesting() }

        let provider: UsageProvider = .codex
        CookieHeaderCache.store(provider: provider, cookieHeader: "auth=first", sourceLabel: "Chrome")
        #expect(CookieHeaderCache.loadForDisplay(provider: provider)?.cookieHeader == "auth=first")

        CookieHeaderCache.store(provider: provider, cookieHeader: "auth=second", sourceLabel: "Safari")
        #expect(CookieHeaderCache.loadForDisplay(provider: provider)?.cookieHeader == "auth=second")

        CookieHeaderCache.clear(provider: provider)
        #expect(CookieHeaderCache.loadForDisplay(provider: provider) == nil)
    }

    @Test
    func stale_refresh_cannot_overwrite_a_newer_store() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }
        CookieHeaderCache.resetDisplayCacheForTesting()
        defer { CookieHeaderCache.resetDisplayCacheForTesting() }

        let provider: UsageProvider = .codex
        CookieHeaderCache.store(provider: provider, cookieHeader: "auth=old", sourceLabel: "Chrome")
        #expect(CookieHeaderCache.loadForDisplay(provider: provider)?.cookieHeader == "auth=old")

        // A refresh scheduled now races with a store that lands before it commits.
        let staleGeneration = CookieHeaderCache.beginDisplayReadGenerationForTesting(provider: provider)
        let staleEntry = CookieHeaderCache.load(provider: provider)
        CookieHeaderCache.store(provider: provider, cookieHeader: "auth=new", sourceLabel: "Safari")

        let committed = CookieHeaderCache.commitDisplaySnapshotIfCurrentForTesting(
            provider: provider,
            entry: staleEntry,
            generation: staleGeneration)

        #expect(committed?.cookieHeader == "auth=new")
        #expect(CookieHeaderCache.loadForDisplay(provider: provider)?.cookieHeader == "auth=new")
    }

    @Test
    func stale_refresh_cannot_resurrect_a_cleared_snapshot() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }
        CookieHeaderCache.resetDisplayCacheForTesting()
        defer { CookieHeaderCache.resetDisplayCacheForTesting() }

        let provider: UsageProvider = .codex
        CookieHeaderCache.store(provider: provider, cookieHeader: "auth=secret", sourceLabel: "Chrome")
        #expect(CookieHeaderCache.loadForDisplay(provider: provider)?.cookieHeader == "auth=secret")

        let staleGeneration = CookieHeaderCache.beginDisplayReadGenerationForTesting(provider: provider)
        let staleEntry = CookieHeaderCache.load(provider: provider)
        CookieHeaderCache.clear(provider: provider)

        let committed = CookieHeaderCache.commitDisplaySnapshotIfCurrentForTesting(
            provider: provider,
            entry: staleEntry,
            generation: staleGeneration)

        #expect(committed == nil)
        #expect(CookieHeaderCache.loadForDisplay(provider: provider) == nil)
    }

    @Test
    func stale_refresh_cannot_survive_clear_all() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }
        CookieHeaderCache.resetDisplayCacheForTesting()
        defer { CookieHeaderCache.resetDisplayCacheForTesting() }

        let provider: UsageProvider = .codex
        CookieHeaderCache.store(provider: provider, cookieHeader: "auth=secret", sourceLabel: "Chrome")
        #expect(CookieHeaderCache.loadForDisplay(provider: provider)?.cookieHeader == "auth=secret")

        let staleGeneration = CookieHeaderCache.beginDisplayReadGenerationForTesting(provider: provider)
        let staleEntry = CookieHeaderCache.load(provider: provider)
        CookieHeaderCache.clearAll()

        CookieHeaderCache.commitDisplaySnapshotIfCurrentForTesting(
            provider: provider,
            entry: staleEntry,
            generation: staleGeneration)

        #expect(CookieHeaderCache.loadForDisplay(provider: provider) == nil)
    }

    @Test
    func clear_all_invalidates_an_in_flight_first_display_population() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }
        CookieHeaderCache.resetDisplayCacheForTesting()
        defer { CookieHeaderCache.resetDisplayCacheForTesting() }

        let provider: UsageProvider = .codex
        KeychainCacheStore.store(
            key: .cookie(provider: provider),
            entry: CookieHeaderCache.Entry(
                cookieHeader: "auth=secret",
                storedAt: Date(timeIntervalSince1970: 0),
                sourceLabel: "Chrome"))

        // A first display load registers its key, then reads the Keychain outside the lock.
        let staleGeneration = CookieHeaderCache.beginDisplayReadGenerationForTesting(provider: provider)
        let staleEntry = CookieHeaderCache.load(provider: provider)
        CookieHeaderCache.clearAll()

        let committed = CookieHeaderCache.commitDisplaySnapshotIfCurrentForTesting(
            provider: provider,
            entry: staleEntry,
            generation: staleGeneration)

        #expect(committed == nil)
        #expect(CookieHeaderCache.loadForDisplay(provider: provider) == nil)
    }

    @Test
    func stale_display_snapshot_revalidates_off_the_calling_path() async throws {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }
        CookieHeaderCache.resetDisplayCacheForTesting()
        defer { CookieHeaderCache.resetDisplayCacheForTesting() }
        CookieHeaderCache.setDisplayStalenessIntervalOverrideForTesting(0)
        defer { CookieHeaderCache.setDisplayStalenessIntervalOverrideForTesting(nil) }

        let provider: UsageProvider = .codex
        KeychainCacheStore.store(
            key: .cookie(provider: provider),
            entry: CookieHeaderCache.Entry(
                cookieHeader: "auth=old",
                storedAt: Date(timeIntervalSince1970: 0),
                sourceLabel: "Chrome"))
        #expect(CookieHeaderCache.loadForDisplay(provider: provider)?.cookieHeader == "auth=old")

        KeychainCacheStore.store(
            key: .cookie(provider: provider),
            entry: CookieHeaderCache.Entry(
                cookieHeader: "auth=new",
                storedAt: Date(timeIntervalSince1970: 1),
                sourceLabel: "Chrome"))

        // The stale lookup returns the old snapshot and schedules a revalidation.
        _ = CookieHeaderCache.loadForDisplay(provider: provider)
        var refreshed = false
        for _ in 0..<200 {
            if CookieHeaderCache.loadForDisplay(provider: provider)?.cookieHeader == "auth=new" {
                refreshed = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(refreshed)
    }

    @Test
    func clear_all_removes_every_provider_cookie_key_without_decoding_entries() {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }

        KeychainCacheStore.withServiceOverrideForTesting("cookie-clear-all-\(UUID().uuidString)") {
            CookieHeaderCache.store(provider: .claude, cookieHeader: "auth=claude", sourceLabel: "Chrome")
            CookieHeaderCache.store(
                provider: .codex,
                scope: .managedAccount(UUID()),
                cookieHeader: "auth=codex",
                sourceLabel: "Chrome")
            KeychainCacheStore.store(
                key: .cookie(provider: .cursor),
                entry: WrongEntry(value: "invalid"))

            let cleared = CookieHeaderCache.clearAllDetailed()

            #expect(cleared.clearedCount >= 3)
            #expect(cleared.failedCount == 0)
            #expect(KeychainCacheStore.keys(category: "cookie").isEmpty)
        }
    }

    private func withIsolatedCookieCache<T>(_ operation: () -> T) -> T {
        KeychainCacheStore.withServiceOverrideForTesting("cookie-isolation-\(UUID().uuidString)") {
            let legacyBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            CookieHeaderCache.setLegacyBaseURLOverrideForTesting(legacyBase)
            defer { CookieHeaderCache.setLegacyBaseURLOverrideForTesting(nil) }
            KeychainCacheStore.setTestStoreForTesting(true)
            defer { KeychainCacheStore.setTestStoreForTesting(false) }
            CookieHeaderCache.resetDisplayCacheForTesting()
            defer { CookieHeaderCache.resetDisplayCacheForTesting() }
            return operation()
        }
    }
}
