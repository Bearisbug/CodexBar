import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ClaudeOAuthCredentialsStoreTests {
    private func makeCredentialsData(accessToken: String, expiresAt: Date, refreshToken: String? = nil) -> Data {
        let millis = Int(expiresAt.timeIntervalSince1970 * 1000)
        let refreshField: String = {
            guard let refreshToken else { return "" }
            return ",\n            \"refreshToken\": \"\(refreshToken)\""
        }()
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "\(accessToken)",
            "expiresAt": \(millis),
            "scopes": ["user:profile"]\(refreshField)
          }
        }
        """
        return Data(json.utf8)
    }

    @Test
    func persistent_reference_hash_stays_stable_across_keychain_metadata_refresh() {
        let first = ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
            modifiedAt: 1,
            createdAt: 1,
            persistentRefHash: "opaque-ref")
        let refreshed = ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
            modifiedAt: 2,
            createdAt: 1,
            persistentRefHash: "opaque-ref")

        let firstHash = ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
            data: nil,
            fingerprint: first)
        {
            ClaudeOAuthCredentialsStore.claudeKeychainPersistentRefHashWithoutPrompt()
        }
        let refreshedHash = ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
            data: nil,
            fingerprint: refreshed)
        {
            ClaudeOAuthCredentialsStore.claudeKeychainPersistentRefHashWithoutPrompt()
        }

        #expect(firstHash == "opaque-ref")
        #expect(refreshedHash == firstHash)
    }

    @Test
    func loads_from_keychain_cache_before_expired_file() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try ProviderInteractionContext.$current.withValue(.background) {
            try KeychainCacheStore.withServiceOverrideForTesting(service) {
                try KeychainAccessGate.withTaskOverrideForTesting(false) {
                    KeychainCacheStore.setTestStoreForTesting(true)
                    defer { KeychainCacheStore.setTestStoreForTesting(false) }

                    ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    defer { ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting() }
                    try ClaudeOAuthCredentialsStore.withIsolatedCredentialsFileTrackingForTesting {
                        try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                            let tempDir = FileManager.default.temporaryDirectory
                                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                            let fileURL = tempDir.appendingPathComponent("credentials.json")
                            try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                                let expiredData = self.makeCredentialsData(
                                    accessToken: "expired",
                                    expiresAt: Date(timeIntervalSinceNow: -3600))
                                try expiredData.write(to: fileURL)

                                let cachedData = self.makeCredentialsData(
                                    accessToken: "cached",
                                    expiresAt: Date(timeIntervalSinceNow: 3600))
                                let cacheEntry = ClaudeOAuthCredentialsStore.CacheEntry(
                                    data: cachedData,
                                    storedAt: Date())
                                let cacheKey = KeychainCacheStore.Key.oauth(provider: .claude)
                                ClaudeOAuthCredentialsStore.invalidateCache()
                                KeychainCacheStore.store(key: cacheKey, entry: cacheEntry)
                                defer { KeychainCacheStore.clear(key: cacheKey) }
                                _ = try ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(
                                    .securityFramework)
                                {
                                    try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(
                                        .onlyOnUserAction)
                                    {
                                        try ClaudeOAuthCredentialsStore.load(
                                            environment: [:],
                                            allowKeychainPrompt: false)
                                    }
                                }
                                // Re-store to cache after file check has marked file as "seen"
                                KeychainCacheStore.store(key: cacheKey, entry: cacheEntry)
                                let creds = try ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(
                                    .securityFramework)
                                {
                                    try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(
                                        .onlyOnUserAction)
                                    {
                                        try ClaudeOAuthCredentialsStore.load(
                                            environment: [:],
                                            allowKeychainPrompt: false)
                                    }
                                }

                                #expect(creds.accessToken == "cached")
                                #expect(creds.isExpired == false)
                            }
                        }
                    }
                }
            }
        }
    }

    @Test
    func load_record_non_interactive_repair_can_be_disabled() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            KeychainCacheStore.setTestStoreForTesting(true)
            defer { KeychainCacheStore.setTestStoreForTesting(false) }

            ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
            defer { ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting() }

            try ClaudeOAuthCredentialsStore.withIsolatedCredentialsFileTrackingForTesting {
                try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                    // Ensure file-based lookup doesn't interfere (and avoid touching ~/.claude).
                    let tempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let fileURL = tempDir.appendingPathComponent("credentials.json")
                    try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                        ClaudeOAuthCredentialsStore.invalidateCache()

                        let keychainData = self.makeCredentialsData(
                            accessToken: "claude-keychain",
                            expiresAt: Date(timeIntervalSinceNow: 3600))

                        // Simulate Claude Keychain containing creds, without querying the real Keychain.
                        try ProviderInteractionContext.$current.withValue(.userInitiated) {
                            try ClaudeOAuthCredentialsStore
                                .withClaudeKeychainOverridesForTesting(data: keychainData, fingerprint: nil) {
                                    // When repair is disabled, non-interactive loads should not consult Claude's
                                    // keychain data.
                                    do {
                                        _ = try ClaudeOAuthCredentialsStore.loadRecord(
                                            environment: [:],
                                            allowKeychainPrompt: false,
                                            respectKeychainPromptCooldown: true,
                                            allowClaudeKeychainRepairWithoutPrompt: false)
                                        Issue.record("Expected ClaudeOAuthCredentialsError.notFound")
                                    } catch let error as ClaudeOAuthCredentialsError {
                                        guard case .notFound = error else {
                                            Issue.record("Expected .notFound, got \(error)")
                                            return
                                        }
                                    }

                                    // With repair enabled, we should be able to seed from the "Claude keychain"
                                    // override.
                                    let record = try ClaudeOAuthCredentialsStore.loadRecord(
                                        environment: [:],
                                        allowKeychainPrompt: false,
                                        respectKeychainPromptCooldown: true,
                                        allowClaudeKeychainRepairWithoutPrompt: true)
                                    #expect(record.credentials.accessToken == "claude-keychain")
                                }
                        }
                    }
                }
            }
        }
    }

    @Test
    func invalidates_cache_when_credentials_file_changes() throws {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }

        ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
        defer { ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting() }

        // Avoid interacting with the real Keychain in unit tests.
        try ClaudeOAuthCredentialsStore.withKeychainAccessOverrideForTesting(true) {
            try ClaudeOAuthCredentialsStore.withIsolatedCredentialsFileTrackingForTesting {
                try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                    let tempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let fileURL = tempDir.appendingPathComponent("credentials.json")
                    try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                        let first = self.makeCredentialsData(
                            accessToken: "first",
                            expiresAt: Date(timeIntervalSinceNow: 3600))
                        try first.write(to: fileURL)

                        let cacheKey = KeychainCacheStore.Key.oauth(provider: .claude)
                        let cacheEntry = ClaudeOAuthCredentialsStore.CacheEntry(data: first, storedAt: Date())
                        KeychainCacheStore.store(key: cacheKey, entry: cacheEntry)

                        _ = try ClaudeOAuthCredentialsStore.load(environment: [:])

                        let updated = self.makeCredentialsData(
                            accessToken: "second",
                            expiresAt: Date(timeIntervalSinceNow: 3600))
                        try updated.write(to: fileURL)

                        #expect(ClaudeOAuthCredentialsStore.invalidateCacheIfCredentialsFileChanged())
                        KeychainCacheStore.clear(key: cacheKey)

                        let creds = try ClaudeOAuthCredentialsStore.load(environment: [:])
                        #expect(creds.accessToken == "second")
                    }
                }
            }
        }
    }

    @Test
    func returns_expired_file_when_no_other_sources() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            try KeychainAccessGate.withTaskOverrideForTesting(true) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }

                try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                    ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    defer { ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting() }

                    let tempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let fileURL = tempDir.appendingPathComponent("credentials.json")
                    try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                        let expiredData = self.makeCredentialsData(
                            accessToken: "expired-only",
                            expiresAt: Date(timeIntervalSinceNow: -3600))
                        try expiredData.write(to: fileURL)

                        try ClaudeOAuthCredentialsStore.withKeychainAccessOverrideForTesting(true) {
                            ClaudeOAuthCredentialsStore.invalidateCache()
                            let creds = try ClaudeOAuthCredentialsStore.load(environment: [:])

                            #expect(creds.accessToken == "expired-only")
                            #expect(creds.isExpired == true)
                        }
                    }
                }
            }
        }
    }

    @Test
    func load_with_auto_refresh_expired_claude_CLI_owner_throws_delegated_refresh() async throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try await KeychainCacheStore.withServiceOverrideForTesting(service) {
            KeychainCacheStore.setTestStoreForTesting(true)
            defer { KeychainCacheStore.setTestStoreForTesting(false) }

            ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
            defer { ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting() }

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let fileURL = tempDir.appendingPathComponent("credentials.json")
            await ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                await ClaudeOAuthCredentialsStore.withKeychainAccessOverrideForTesting(true) {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    let cacheKey = KeychainCacheStore.Key.oauth(provider: .claude)
                    defer { KeychainCacheStore.clear(key: cacheKey) }

                    let expiredData = self.makeCredentialsData(
                        accessToken: "expired-claude-cli-owner",
                        expiresAt: Date(timeIntervalSinceNow: -3600),
                        refreshToken: "refresh-token")
                    KeychainCacheStore.store(
                        key: cacheKey,
                        entry: ClaudeOAuthCredentialsStore.CacheEntry(
                            data: expiredData,
                            storedAt: Date(),
                            owner: .claudeCLI))

                    do {
                        _ = try await ClaudeOAuthCredentialsStore.loadWithAutoRefresh(
                            environment: [:],
                            allowKeychainPrompt: false,
                            respectKeychainPromptCooldown: true)
                        Issue.record("Expected delegated refresh error for Claude CLI-owned credentials")
                    } catch let error as ClaudeOAuthCredentialsError {
                        guard case .refreshDelegatedToClaudeCLI = error else {
                            Issue.record("Expected .refreshDelegatedToClaudeCLI, got \(error)")
                            return
                        }
                    } catch {
                        Issue.record("Expected ClaudeOAuthCredentialsError, got \(error)")
                    }
                }
            }
        }
    }

    @Test
    func load_with_auto_refresh_expired_codexbar_owner_uses_direct_refresh_path() async throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try await KeychainCacheStore.withServiceOverrideForTesting(service) {
            KeychainCacheStore.setTestStoreForTesting(true)
            defer { KeychainCacheStore.setTestStoreForTesting(false) }

            ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
            defer { ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting() }

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let fileURL = tempDir.appendingPathComponent("credentials.json")
            await ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                await ClaudeOAuthCredentialsStore.withKeychainAccessOverrideForTesting(true) {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    let cacheKey = KeychainCacheStore.Key.oauth(provider: .claude)
                    defer { KeychainCacheStore.clear(key: cacheKey) }

                    let expiredData = self.makeCredentialsData(
                        accessToken: "expired-codexbar-owner",
                        expiresAt: Date(timeIntervalSinceNow: -3600),
                        refreshToken: "refresh-token")
                    KeychainCacheStore.store(
                        key: cacheKey,
                        entry: ClaudeOAuthCredentialsStore.CacheEntry(
                            data: expiredData,
                            storedAt: Date(),
                            owner: .codexbar))

                    await ClaudeOAuthRefreshFailureGate.$shouldAttemptOverride.withValue(false) {
                        do {
                            _ = try await ClaudeOAuthCredentialsStore.loadWithAutoRefresh(
                                environment: [:],
                                allowKeychainPrompt: false,
                                respectKeychainPromptCooldown: true)
                            Issue.record("Expected refresh failure for CodexBar-owned direct refresh path")
                        } catch let error as ClaudeOAuthCredentialsError {
                            guard case .refreshFailed = error else {
                                Issue.record("Expected .refreshFailed, got \(error)")
                                return
                            }
                        } catch {
                            Issue.record("Expected ClaudeOAuthCredentialsError, got \(error)")
                        }
                    }
                }
            }
        }
    }

    @Test
    func load_record_legacy_cache_entry_without_owner_defaults_to_claude_CLI_owner() throws {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }

        ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
        defer { ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting() }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("credentials.json")
        try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
            try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                try ClaudeOAuthCredentialsStore.withKeychainAccessOverrideForTesting(true) {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    let cacheKey = KeychainCacheStore.Key.oauth(provider: .claude)
                    defer { KeychainCacheStore.clear(key: cacheKey) }

                    let validData = self.makeCredentialsData(
                        accessToken: "legacy-owner",
                        expiresAt: Date(timeIntervalSinceNow: 3600),
                        refreshToken: "refresh-token")
                    KeychainCacheStore.store(
                        key: cacheKey,
                        entry: ClaudeOAuthCredentialsStore.CacheEntry(
                            data: validData,
                            storedAt: Date()))

                    let record = try ClaudeOAuthCredentialsStore.loadRecord(
                        environment: [:],
                        allowKeychainPrompt: false,
                        respectKeychainPromptCooldown: true)
                    #expect(record.owner == .claudeCLI)
                    #expect(record.source == .cacheKeychain)
                }
            }
        }
    }

    @Test
    func has_cached_credentials_returns_false_for_expired_unrefreshable_codexbar_cache_entry() throws {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }

        ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
        defer { ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting() }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("credentials.json")
        ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
            ClaudeOAuthCredentialsStore.invalidateCache()

            let expiredData = self.makeCredentialsData(
                accessToken: "expired-no-refresh",
                expiresAt: Date(timeIntervalSinceNow: -3600),
                refreshToken: nil)
            let cacheEntry = ClaudeOAuthCredentialsStore.CacheEntry(
                data: expiredData,
                storedAt: Date(),
                owner: .codexbar)
            let cacheKey = KeychainCacheStore.Key.oauth(provider: .claude)
            KeychainCacheStore.store(key: cacheKey, entry: cacheEntry)

            #expect(ClaudeOAuthCredentialsStore.hasCachedCredentials() == false)
        }
    }

    @Test
    func has_cached_credentials_returns_true_for_expired_refreshable_cache_entry() throws {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }

        ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
        defer { ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting() }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("credentials.json")
        ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
            ClaudeOAuthCredentialsStore.invalidateCache()

            let expiredData = self.makeCredentialsData(
                accessToken: "expired-refreshable",
                expiresAt: Date(timeIntervalSinceNow: -3600),
                refreshToken: "refresh")
            let cacheEntry = ClaudeOAuthCredentialsStore.CacheEntry(data: expiredData, storedAt: Date())
            let cacheKey = KeychainCacheStore.Key.oauth(provider: .claude)
            KeychainCacheStore.store(key: cacheKey, entry: cacheEntry)

            #expect(ClaudeOAuthCredentialsStore.hasCachedCredentials() == true)
        }
    }

    @Test
    func has_cached_credentials_returns_true_for_expired_claude_CLI_backed_credentials_file() throws {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }

        ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
        defer { ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting() }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("credentials.json")
        try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
            ClaudeOAuthCredentialsStore.invalidateCache()

            let expiredData = self.makeCredentialsData(
                accessToken: "expired-file-no-refresh",
                expiresAt: Date(timeIntervalSinceNow: -3600),
                refreshToken: nil)
            try expiredData.write(to: fileURL)

            #expect(ClaudeOAuthCredentialsStore.hasCachedCredentials() == true)
        }
    }

    @Test
    func syncs_cache_when_claude_keychain_fingerprint_changes_and_token_differs() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            try KeychainAccessGate.withTaskOverrideForTesting(false) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }

                ClaudeOAuthKeychainAccessGate.resetForTesting()
                defer { ClaudeOAuthKeychainAccessGate.resetForTesting() }

                ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                defer { ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting() }

                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let fileURL = tempDir.appendingPathComponent("credentials.json")
                try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    ClaudeOAuthCredentialsStore._resetClaudeKeychainChangeTrackingForTesting()
                    defer {
                        ClaudeOAuthCredentialsStore.invalidateCache()
                        ClaudeOAuthCredentialsStore._resetClaudeKeychainChangeTrackingForTesting()
                    }

                    // Avoid cross-suite interference from UserDefaults fingerprint persistence.
                    let fingerprintStore = ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprintStore()

                    let cacheKey = KeychainCacheStore.Key.oauth(provider: .claude)
                    let cachedData = self.makeCredentialsData(
                        accessToken: "cached-token",
                        expiresAt: Date(timeIntervalSinceNow: 3600))
                    KeychainCacheStore.store(
                        key: cacheKey,
                        entry: ClaudeOAuthCredentialsStore.CacheEntry(data: cachedData, storedAt: Date()))

                    let fingerprint1 = ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
                        modifiedAt: 1,
                        createdAt: 1,
                        persistentRefHash: "ref1")

                    let first = try ProviderInteractionContext.$current.withValue(.userInitiated) {
                        try ClaudeOAuthCredentialsStore.withClaudeKeychainFingerprintStoreOverrideForTesting(
                            fingerprintStore)
                        {
                            try ClaudeOAuthKeychainAccessGate.withShouldAllowPromptOverrideForTesting(true) {
                                try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                    data: cachedData,
                                    fingerprint: fingerprint1)
                                {
                                    try ClaudeOAuthCredentialsStore.load(environment: [:], allowKeychainPrompt: false)
                                }
                            }
                        }
                    }
                    #expect(first.accessToken == "cached-token")
                    #expect(fingerprintStore.fingerprint == fingerprint1)

                    ClaudeOAuthCredentialsStore._resetClaudeKeychainChangeThrottleForTesting()

                    let fingerprint2 = ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
                        modifiedAt: 2,
                        createdAt: 2,
                        persistentRefHash: "ref2")

                    let keychainData = self.makeCredentialsData(
                        accessToken: "keychain-token",
                        expiresAt: Date(timeIntervalSinceNow: 3600))

                    let second = try ProviderInteractionContext.$current.withValue(.userInitiated) {
                        try ClaudeOAuthCredentialsStore.withClaudeKeychainFingerprintStoreOverrideForTesting(
                            fingerprintStore)
                        {
                            try ClaudeOAuthKeychainAccessGate.withShouldAllowPromptOverrideForTesting(true) {
                                try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                    data: keychainData,
                                    fingerprint: fingerprint2)
                                {
                                    try ClaudeOAuthCredentialsStore.load(environment: [:], allowKeychainPrompt: false)
                                }
                            }
                        }
                    }
                    #expect(second.accessToken == "keychain-token")
                    #expect(fingerprintStore.fingerprint == fingerprint2)

                    switch KeychainCacheStore.load(key: cacheKey, as: ClaudeOAuthCredentialsStore.CacheEntry.self) {
                    case let .found(entry):
                        let parsed = try ClaudeOAuthCredentials.parse(data: entry.data)
                        #expect(parsed.accessToken == "keychain-token")
                    default:
                        #expect(Bool(false))
                    }
                }
            }
        }
    }

    @Test
    func does_not_sync_in_background_when_cache_valid_and_prompt_mode_only_on_user_action() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            try KeychainAccessGate.withTaskOverrideForTesting(false) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }

                ClaudeOAuthKeychainAccessGate.resetForTesting()
                defer { ClaudeOAuthKeychainAccessGate.resetForTesting() }

                ClaudeOAuthCredentialsStore.invalidateCache()
                ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                defer {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    ClaudeOAuthCredentialsStore._resetClaudeKeychainChangeTrackingForTesting()
                }

                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let fileURL = tempDir.appendingPathComponent("credentials.json")

                try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                    ClaudeOAuthCredentialsStore._resetClaudeKeychainChangeTrackingForTesting()

                    let fingerprintStore = ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprintStore()
                    let fingerprint1 = ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
                        modifiedAt: 1,
                        createdAt: 1,
                        persistentRefHash: "ref1")
                    fingerprintStore.fingerprint = fingerprint1

                    let cacheKey = KeychainCacheStore.Key.oauth(provider: .claude)
                    let cachedData = self.makeCredentialsData(
                        accessToken: "cached-token",
                        expiresAt: Date(timeIntervalSinceNow: 3600))
                    KeychainCacheStore.store(
                        key: cacheKey,
                        entry: ClaudeOAuthCredentialsStore.CacheEntry(
                            data: cachedData,
                            storedAt: Date(),
                            owner: .claudeCLI))

                    ClaudeOAuthCredentialsStore._resetClaudeKeychainChangeThrottleForTesting()

                    let fingerprint2 = ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
                        modifiedAt: 2,
                        createdAt: 2,
                        persistentRefHash: "ref2")
                    let keychainData = self.makeCredentialsData(
                        accessToken: "keychain-token",
                        expiresAt: Date(timeIntervalSinceNow: 3600))

                    let creds = try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.onlyOnUserAction) {
                        try ProviderInteractionContext.$current.withValue(.background) {
                            try ClaudeOAuthCredentialsStore.withClaudeKeychainFingerprintStoreOverrideForTesting(
                                fingerprintStore)
                            {
                                try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                    data: keychainData,
                                    fingerprint: fingerprint2)
                                {
                                    try ClaudeOAuthCredentialsStore.load(environment: [:], allowKeychainPrompt: false)
                                }
                            }
                        }
                    }

                    #expect(creds.accessToken == "cached-token")
                    #expect(fingerprintStore.fingerprint == fingerprint1)

                    switch KeychainCacheStore.load(key: cacheKey, as: ClaudeOAuthCredentialsStore.CacheEntry.self) {
                    case let .found(entry):
                        let parsed = try ClaudeOAuthCredentials.parse(data: entry.data)
                        #expect(parsed.accessToken == "cached-token")
                    default:
                        #expect(Bool(false))
                    }
                }
            }
        }
    }

    @Test
    func seed_aligns_claude_keychain_fingerprint_so_freshness_sync_skips_item_read() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            try KeychainAccessGate.withTaskOverrideForTesting(false) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }

                ClaudeOAuthKeychainAccessGate.resetForTesting()
                defer { ClaudeOAuthKeychainAccessGate.resetForTesting() }

                ClaudeOAuthCredentialsStore.invalidateCache()
                ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                defer {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    ClaudeOAuthCredentialsStore._resetClaudeKeychainChangeTrackingForTesting()
                }

                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let fileURL = tempDir.appendingPathComponent("credentials.json")

                try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                    ClaudeOAuthCredentialsStore._resetClaudeKeychainChangeTrackingForTesting()

                    // Stale fingerprint from before the account switch rewrote the item.
                    let fingerprintStore = ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprintStore()
                    fingerprintStore.fingerprint = ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
                        modifiedAt: 1,
                        createdAt: 1,
                        persistentRefHash: "ref-before-switch")
                    let rewrittenFingerprint = ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
                        modifiedAt: 2,
                        createdAt: 2,
                        persistentRefHash: "ref-after-switch")

                    let seededData = self.makeCredentialsData(
                        accessToken: "seeded-token",
                        expiresAt: Date(timeIntervalSinceNow: 3600))
                    // Distinct keychain payload: a freshness-sync re-read would surface it,
                    // so the loads below prove the recreated item is never touched.
                    let keychainData = self.makeCredentialsData(
                        accessToken: "keychain-token",
                        expiresAt: Date(timeIntervalSinceNow: 3600))

                    // Seeding runs inside the switch transaction (background context,
                    // default prompt policy): alignment must not depend on prompt gates.
                    try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.onlyOnUserAction) {
                        try ProviderInteractionContext.$current.withValue(.background) {
                            try ClaudeOAuthCredentialsStore.withClaudeKeychainFingerprintStoreOverrideForTesting(
                                fingerprintStore)
                            {
                                try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                    data: keychainData,
                                    fingerprint: rewrittenFingerprint)
                                {
                                    ClaudeOAuthCredentialsStore.seedCacheWithClaudeKeychainPayload(seededData)
                                }
                            }
                        }
                    }
                    #expect(fingerprintStore.fingerprint == rewrittenFingerprint)

                    ClaudeOAuthCredentialsStore._resetClaudeKeychainChangeThrottleForTesting()

                    let creds = try ProviderInteractionContext.$current.withValue(.userInitiated) {
                        try ClaudeOAuthCredentialsStore.withClaudeKeychainFingerprintStoreOverrideForTesting(
                            fingerprintStore)
                        {
                            try ClaudeOAuthKeychainAccessGate.withShouldAllowPromptOverrideForTesting(true) {
                                try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                    data: keychainData,
                                    fingerprint: rewrittenFingerprint)
                                {
                                    try ClaudeOAuthCredentialsStore.load(environment: [:], allowKeychainPrompt: false)
                                }
                            }
                        }
                    }
                    #expect(creds.accessToken == "seeded-token")
                    #expect(fingerprintStore.fingerprint == rewrittenFingerprint)
                }
            }
        }
    }

    @Test
    func does_not_sync_when_claude_keychain_fingerprint_unchanged() throws {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }

        try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
            try ClaudeOAuthCredentialsStore.withIsolatedCredentialsFileTrackingForTesting {
                ClaudeOAuthCredentialsStore.invalidateCache()
                ClaudeOAuthCredentialsStore._resetClaudeKeychainChangeTrackingForTesting()
                defer {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    ClaudeOAuthCredentialsStore._resetClaudeKeychainChangeTrackingForTesting()
                }

                let cacheKey = KeychainCacheStore.Key.oauth(provider: .claude)
                let cachedData = self.makeCredentialsData(
                    accessToken: "cached-token",
                    expiresAt: Date(timeIntervalSinceNow: 3600))
                KeychainCacheStore.store(
                    key: cacheKey,
                    entry: ClaudeOAuthCredentialsStore.CacheEntry(data: cachedData, storedAt: Date()))

                let fingerprint = ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
                    modifiedAt: 1,
                    createdAt: 1,
                    persistentRefHash: "ref1")
                let first = try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                    data: cachedData,
                    fingerprint: fingerprint,
                    operation: {
                        try ClaudeOAuthCredentialsStore.load(environment: [:], allowKeychainPrompt: false)
                    })
                #expect(first.accessToken == "cached-token")

                ClaudeOAuthCredentialsStore._resetClaudeKeychainChangeThrottleForTesting()
                let keychainData = self.makeCredentialsData(
                    accessToken: "keychain-token",
                    expiresAt: Date(timeIntervalSinceNow: 3600))
                let second = try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                    data: keychainData,
                    fingerprint: fingerprint,
                    operation: {
                        try ClaudeOAuthCredentialsStore.load(environment: [:], allowKeychainPrompt: false)
                    })
                #expect(second.accessToken == "cached-token")

                switch KeychainCacheStore.load(key: cacheKey, as: ClaudeOAuthCredentialsStore.CacheEntry.self) {
                case let .found(entry):
                    let parsed = try ClaudeOAuthCredentials.parse(data: entry.data)
                    #expect(parsed.accessToken == "cached-token")
                default:
                    #expect(Bool(false))
                }
            }
        }
    }

    @Test
    func does_not_sync_when_keychain_credentials_expired_but_cache_valid() throws {
        KeychainCacheStore.setTestStoreForTesting(true)
        defer { KeychainCacheStore.setTestStoreForTesting(false) }

        try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
            try ClaudeOAuthCredentialsStore.withIsolatedCredentialsFileTrackingForTesting {
                ClaudeOAuthCredentialsStore.invalidateCache()
                ClaudeOAuthCredentialsStore._resetClaudeKeychainChangeTrackingForTesting()
                defer {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    ClaudeOAuthCredentialsStore._resetClaudeKeychainChangeTrackingForTesting()
                }

                let cacheKey = KeychainCacheStore.Key.oauth(provider: .claude)
                let cachedData = self.makeCredentialsData(
                    accessToken: "cached-token",
                    expiresAt: Date(timeIntervalSinceNow: 3600))
                KeychainCacheStore.store(
                    key: cacheKey,
                    entry: ClaudeOAuthCredentialsStore.CacheEntry(data: cachedData, storedAt: Date()))

                let first = try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                    data: cachedData,
                    fingerprint: ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
                        modifiedAt: 1,
                        createdAt: 1,
                        persistentRefHash: "ref1"),
                    operation: {
                        try ClaudeOAuthCredentialsStore.load(environment: [:], allowKeychainPrompt: false)
                    })
                #expect(first.accessToken == "cached-token")

                ClaudeOAuthCredentialsStore._resetClaudeKeychainChangeThrottleForTesting()

                let expiredKeychainData = self.makeCredentialsData(
                    accessToken: "expired-keychain-token",
                    expiresAt: Date(timeIntervalSinceNow: -3600))
                let second = try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                    data: expiredKeychainData,
                    fingerprint: ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
                        modifiedAt: 2,
                        createdAt: 2,
                        persistentRefHash: "ref2"),
                    operation: {
                        try ClaudeOAuthCredentialsStore.load(environment: [:], allowKeychainPrompt: false)
                    })
                #expect(second.accessToken == "cached-token")

                switch KeychainCacheStore.load(key: cacheKey, as: ClaudeOAuthCredentialsStore.CacheEntry.self) {
                case let .found(entry):
                    let parsed = try ClaudeOAuthCredentials.parse(data: entry.data)
                    #expect(parsed.accessToken == "cached-token")
                default:
                    #expect(Bool(false))
                }
            }
        }
    }

    @Test
    func respects_prompt_cooldown_gate_when_disabled_prompting() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            KeychainCacheStore.setTestStoreForTesting(true)
            defer { KeychainCacheStore.setTestStoreForTesting(false) }

            ClaudeOAuthKeychainAccessGate.resetForTesting()
            defer { ClaudeOAuthKeychainAccessGate.resetForTesting() }

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let fileURL = tempDir.appendingPathComponent("credentials.json")
            try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                    try ClaudeOAuthCredentialsStore.withIsolatedCredentialsFileTrackingForTesting {
                        ClaudeOAuthCredentialsStore.invalidateCache()
                        ClaudeOAuthCredentialsStore._resetClaudeKeychainChangeTrackingForTesting()
                        defer {
                            ClaudeOAuthCredentialsStore.invalidateCache()
                            ClaudeOAuthCredentialsStore._resetClaudeKeychainChangeTrackingForTesting()
                        }

                        let cacheKey = KeychainCacheStore.Key.oauth(provider: .claude)
                        let cachedData = self.makeCredentialsData(
                            accessToken: "cached-token",
                            expiresAt: Date(timeIntervalSinceNow: 3600))
                        KeychainCacheStore.store(
                            key: cacheKey,
                            entry: ClaudeOAuthCredentialsStore.CacheEntry(data: cachedData, storedAt: Date()))

                        let first = try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                            data: cachedData,
                            fingerprint: ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
                                modifiedAt: 1,
                                createdAt: 1,
                                persistentRefHash: "ref1"),
                            operation: {
                                try ClaudeOAuthCredentialsStore.load(environment: [:], allowKeychainPrompt: false)
                            })
                        #expect(first.accessToken == "cached-token")

                        ClaudeOAuthCredentialsStore._resetClaudeKeychainChangeThrottleForTesting()
                        ClaudeOAuthKeychainAccessGate.recordDenied(now: Date())

                        let keychainData = self.makeCredentialsData(
                            accessToken: "keychain-token",
                            expiresAt: Date(timeIntervalSinceNow: 3600))
                        let second = try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                            data: keychainData,
                            fingerprint: ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
                                modifiedAt: 2,
                                createdAt: 2,
                                persistentRefHash: "ref2"),
                            operation: {
                                try ClaudeOAuthCredentialsStore.load(
                                    environment: [:],
                                    allowKeychainPrompt: false,
                                    respectKeychainPromptCooldown: true)
                            })
                        #expect(second.accessToken == "cached-token")

                        switch KeychainCacheStore.load(key: cacheKey, as: ClaudeOAuthCredentialsStore.CacheEntry.self) {
                        case let .found(entry):
                            let parsed = try ClaudeOAuthCredentials.parse(data: entry.data)
                            #expect(parsed.accessToken == "cached-token")
                        default:
                            #expect(Bool(false))
                        }
                    }
                }
            }
        }
    }

    @Test
    func sync_from_claude_keychain_without_prompt_respects_backoff_in_background() {
        ProviderInteractionContext.$current.withValue(.background) {
            KeychainAccessGate.withTaskOverrideForTesting(true) {
                ClaudeOAuthCredentialsStore.withKeychainAccessOverrideForTesting(true) {
                    let store = ClaudeOAuthCredentialsStore.ClaudeKeychainOverrideStore(
                        data: self.makeCredentialsData(
                            accessToken: "override-token",
                            expiresAt: Date(timeIntervalSinceNow: 3600)),
                        fingerprint: ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
                            modifiedAt: 1,
                            createdAt: 1,
                            persistentRefHash: "deadbeefdead"))

                    let deniedStore = ClaudeOAuthKeychainAccessGate.DeniedUntilStore()
                    deniedStore.deniedUntil = Date(timeIntervalSinceNow: 3600)

                    ClaudeOAuthKeychainAccessGate.withDeniedUntilStoreOverrideForTesting(deniedStore) {
                        ClaudeOAuthCredentialsStore.withMutableClaudeKeychainOverrideStoreForTesting(store) {
                            #expect(ClaudeOAuthCredentialsStore
                                .syncFromClaudeKeychainWithoutPrompt(now: Date()) == false)
                        }
                    }
                }
            }
        }
    }

    @Test
    func testing_override_snapshot_forwards_mutable_Claude_keychain_override_store_across_detached_task() async {
        let fingerprint = ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
            modifiedAt: 11,
            createdAt: 7,
            persistentRefHash: "snapshot-store")
        let store = ClaudeOAuthCredentialsStore.ClaudeKeychainOverrideStore(
            data: nil,
            fingerprint: fingerprint)

        let forwarded = await ClaudeOAuthCredentialsStore.withMutableClaudeKeychainOverrideStoreForTesting(store) {
            let snapshot = ClaudeOAuthCredentialsStore.currentTestingOverridesSnapshotForTask

            return await Task.detached {
                ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.always) {
                    ClaudeOAuthCredentialsStore.withTestingOverridesSnapshotForTask(snapshot) {
                        ClaudeOAuthCredentialsStore.currentClaudeKeychainFingerprintWithoutPromptForAuthGate()
                    }
                }
            }.value
        }

        #expect(forwarded == fingerprint)
    }
}

#if os(macOS)
extension ClaudeOAuthCredentialsStoreTests {
    private func withMissingCredentialsFile<T>(operation: () throws -> T) throws -> T {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        // Deliberately leave this URL empty: this is the missing-credentials-file bug trigger.
        let fileURL = tempDirectory.appendingPathComponent("credentials.json")
        return try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
            try operation()
        }
    }

    private func withIsolatedOAuthCache<T>(operation: () throws -> T) throws -> T {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        return try KeychainCacheStore.withServiceOverrideForTesting(service) {
            KeychainCacheStore.setTestStoreForTesting(true)
            defer { KeychainCacheStore.setTestStoreForTesting(false) }
            return try KeychainAccessGate.withTaskOverrideForTesting(false) {
                try ClaudeOAuthCredentialsStore.withKeychainAccessOverrideForTesting(false) {
                    try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                        try ClaudeOAuthCredentialsStore.withIsolatedCredentialsFileTrackingForTesting {
                            try operation()
                        }
                    }
                }
            }
        }
    }

    @Test
    func never_mode_repairs_a_missing_credentials_file_from_a_valid_no_UI_Keychain_read() throws {
        try self.withIsolatedOAuthCache {
            try self.withMissingCredentialsFile {
                let keychainData = self.makeCredentialsData(
                    accessToken: "test-token-placeholder",
                    expiresAt: Date(timeIntervalSinceNow: 3600))

                let record = try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.never) {
                    try ProviderInteractionContext.$current.withValue(.background) {
                        try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                            data: keychainData,
                            fingerprint: nil)
                        {
                            try ClaudeOAuthCredentialsStore.loadRecord(
                                environment: [:],
                                allowKeychainPrompt: false,
                                respectKeychainPromptCooldown: false,
                                allowClaudeKeychainRepairWithoutPrompt: true)
                        }
                    }
                }

                #expect(record.credentials.accessToken == "test-token-placeholder")
                #expect(record.source == .claudeKeychain)
                #expect(record.owner == .claudeCLI)
            }
        }
    }

    @Test
    func never_mode_skips_the_experimental_security_CLI_before_no_UI_Keychain_repair() throws {
        try self.withIsolatedOAuthCache {
            try self.withMissingCredentialsFile {
                let noUIData = self.makeCredentialsData(
                    accessToken: "test-token-placeholder",
                    expiresAt: Date(timeIntervalSinceNow: 3600))
                let securityCLIData = self.makeCredentialsData(
                    accessToken: "decoy-token",
                    expiresAt: Date(timeIntervalSinceNow: 3600))
                final class ReadCounter: @unchecked Sendable {
                    var count = 0
                }
                let securityCLIReads = ReadCounter()

                let record = try ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(
                    .securityCLIExperimental)
                {
                    try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.never) {
                        try ProviderInteractionContext.$current.withValue(.background) {
                            try ClaudeOAuthCredentialsStore.withSecurityCLIReadOverrideForTesting(
                                .dynamic { _ in
                                    securityCLIReads.count += 1
                                    return securityCLIData
                                }) {
                                    try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                        data: noUIData,
                                        fingerprint: nil)
                                    {
                                        try ClaudeOAuthCredentialsStore.loadRecord(
                                            environment: [:],
                                            allowKeychainPrompt: false,
                                            respectKeychainPromptCooldown: false,
                                            allowClaudeKeychainRepairWithoutPrompt: true)
                                    }
                                }
                        }
                    }
                }

                #expect(record.credentials.accessToken == "test-token-placeholder")
                #expect(record.source == .claudeKeychain)
                #expect(securityCLIReads.count < 1)
            }
        }
    }

    @Test
    func never_mode_still_blocks_an_interactive_Keychain_read_even_with_a_valid_item_present() throws {
        try self.withIsolatedOAuthCache {
            try self.withMissingCredentialsFile {
                let keychainData = self.makeCredentialsData(
                    accessToken: "test-token-placeholder",
                    expiresAt: Date(timeIntervalSinceNow: 3600))

                do {
                    try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.never) {
                        try ProviderInteractionContext.$current.withValue(.background) {
                            try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                data: keychainData,
                                fingerprint: nil)
                            {
                                try ClaudeOAuthCredentialsStore.load(environment: [:], allowKeychainPrompt: true)
                            }
                        }
                    }
                    Issue.record("Expected .notFound, but no error was thrown")
                } catch let error as ClaudeOAuthCredentialsError {
                    guard case .notFound = error else {
                        Issue.record("Expected .notFound, got \(String(describing: error))")
                        return
                    }
                } catch {
                    Issue.record("Expected ClaudeOAuthCredentialsError, got \(error)")
                }
            }
        }
    }

    @Test
    func never_mode_without_any_Keychain_item_still_fails_closed() throws {
        try self.withIsolatedOAuthCache {
            try self.withMissingCredentialsFile {
                // A registered empty override prevents any fallback to real SecItem probes.
                let emptyKeychain = ClaudeOAuthCredentialsStore.ClaudeKeychainOverrideStore(
                    data: nil,
                    fingerprint: nil)
                do {
                    try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.never) {
                        try ProviderInteractionContext.$current.withValue(.background) {
                            try ClaudeOAuthCredentialsStore
                                .withMutableClaudeKeychainOverrideStoreForTesting(emptyKeychain) {
                                    try ClaudeOAuthCredentialsStore.loadRecord(
                                        environment: [:],
                                        allowKeychainPrompt: false,
                                        respectKeychainPromptCooldown: false,
                                        allowClaudeKeychainRepairWithoutPrompt: true)
                                }
                        }
                    }
                    Issue.record("Expected .notFound, but no error was thrown")
                } catch let error as ClaudeOAuthCredentialsError {
                    guard case .notFound = error else {
                        Issue.record("Expected .notFound, got \(String(describing: error))")
                        return
                    }
                } catch {
                    Issue.record("Expected ClaudeOAuthCredentialsError, got \(error)")
                }
            }
        }
    }

    @Test
    func global_Keychain_disable_blocks_no_UI_repair_in_never_mode() throws {
        try self.withIsolatedOAuthCache {
            try self.withMissingCredentialsFile {
                let keychainData = self.makeCredentialsData(
                    accessToken: "test-token-placeholder",
                    expiresAt: Date(timeIntervalSinceNow: 3600))

                do {
                    try KeychainAccessGate.withTaskOverrideForTesting(true) {
                        try ClaudeOAuthCredentialsStore.withKeychainAccessOverrideForTesting(true) {
                            try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.never) {
                                try ProviderInteractionContext.$current.withValue(.background) {
                                    try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                        data: keychainData,
                                        fingerprint: nil)
                                    {
                                        try ClaudeOAuthCredentialsStore.loadRecord(
                                            environment: [:],
                                            allowKeychainPrompt: false,
                                            respectKeychainPromptCooldown: false,
                                            allowClaudeKeychainRepairWithoutPrompt: true)
                                    }
                                }
                            }
                        }
                    }
                    Issue.record("Expected .notFound, but no error was thrown")
                } catch let error as ClaudeOAuthCredentialsError {
                    guard case .notFound = error else {
                        Issue.record("Expected .notFound, got \(String(describing: error))")
                        return
                    }
                } catch {
                    Issue.record("Expected ClaudeOAuthCredentialsError, got \(error)")
                }
            }
        }
    }
}
#endif
