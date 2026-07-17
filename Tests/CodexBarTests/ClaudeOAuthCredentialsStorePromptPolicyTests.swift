import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ClaudeOAuthCredentialsStorePromptPolicyTests {
    @Test
    func keychain_prompt_notify_preserves_its_void_function_signature() {
        let notify: (KeychainPromptContext) -> Void = KeychainPromptHandler.notify
        _ = notify
    }

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
    func does_not_read_claude_keychain_in_background_when_prompt_mode_only_on_user_action() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            try KeychainAccessGate.withTaskOverrideForTesting(false) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }

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

                    let fingerprint = ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
                        modifiedAt: 1,
                        createdAt: 1,
                        persistentRefHash: "ref1")
                    let keychainData = self.makeCredentialsData(
                        accessToken: "keychain-token",
                        expiresAt: Date(timeIntervalSinceNow: 3600))

                    do {
                        _ = try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.onlyOnUserAction) {
                            try ProviderInteractionContext.$current.withValue(.background) {
                                try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                    data: keychainData,
                                    fingerprint: fingerprint)
                                {
                                    try ClaudeOAuthCredentialsStore.load(environment: [:], allowKeychainPrompt: false)
                                }
                            }
                        }
                        Issue.record("Expected ClaudeOAuthCredentialsError.notFound")
                    } catch let error as ClaudeOAuthCredentialsError {
                        guard case .notFound = error else {
                            Issue.record("Expected .notFound, got \(error)")
                            return
                        }
                    }
                }
            }
        }
    }

    @Test
    func can_read_claude_keychain_on_user_action_when_prompt_mode_only_on_user_action() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            try KeychainAccessGate.withTaskOverrideForTesting(false) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }

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

                    let fingerprint = ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
                        modifiedAt: 1,
                        createdAt: 1,
                        persistentRefHash: "ref1")
                    let keychainData = self.makeCredentialsData(
                        accessToken: "keychain-token",
                        expiresAt: Date(timeIntervalSinceNow: 3600))

                    let creds = try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.onlyOnUserAction) {
                        try ProviderInteractionContext.$current.withValue(.userInitiated) {
                            try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                data: keychainData,
                                fingerprint: fingerprint)
                            {
                                try ClaudeOAuthCredentialsStore.load(environment: [:], allowKeychainPrompt: false)
                            }
                        }
                    }

                    #expect(creds.accessToken == "keychain-token")
                }
            }
        }
    }

    @Test
    func user_initiated_claude_keychain_reads_respect_pre_alert_acknowledgement_cooldown() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            try KeychainAccessGate.withTaskOverrideForTesting(false) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }

                try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    defer {
                        ClaudeOAuthCredentialsStore.invalidateCache()
                        ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    }

                    let tempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let fileURL = tempDir.appendingPathComponent("credentials.json")
                    try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                        let keychainData = self.makeCredentialsData(
                            accessToken: "keychain-token",
                            expiresAt: Date(timeIntervalSinceNow: 3600))

                        var preAlertHits = 0
                        let preflightOverride: (String, String?) -> KeychainAccessPreflight.Outcome = { _, _ in
                            .allowed
                        }
                        let promptHandler: (KeychainPromptContext) -> Void = { _ in
                            preAlertHits += 1
                        }
                        let credentials = try KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting(
                            preflightOverride,
                            operation: {
                                try KeychainPromptHandler.withHandlerForTesting(promptHandler, operation: {
                                    try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(
                                        .onlyOnUserAction)
                                    {
                                        try ProviderInteractionContext.$current.withValue(.userInitiated) {
                                            try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                                data: keychainData,
                                                fingerprint: nil)
                                            {
                                                let first = try ClaudeOAuthCredentialsStore.load(
                                                    environment: [:],
                                                    allowKeychainPrompt: true)
                                                ClaudeOAuthCredentialsStore.invalidateCache()
                                                let second = try ClaudeOAuthCredentialsStore.load(
                                                    environment: [:],
                                                    allowKeychainPrompt: true)
                                                return (first, second)
                                            }
                                        }
                                    }
                                })
                            })

                        #expect(credentials.0.accessToken == "keychain-token")
                        #expect(credentials.1.accessToken == "keychain-token")
                        #expect(preAlertHits == 1)
                    }
                }
            }
        }
    }

    @Test
    func shows_pre_alert_when_claude_keychain_likely_requires_interaction() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            try KeychainAccessGate.withTaskOverrideForTesting(false) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }

                try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    defer {
                        ClaudeOAuthCredentialsStore.invalidateCache()
                        ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    }

                    let tempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let fileURL = tempDir.appendingPathComponent("credentials.json")
                    try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                        let keychainData = self.makeCredentialsData(
                            accessToken: "keychain-token",
                            expiresAt: Date(timeIntervalSinceNow: 3600))

                        var preAlertHits = 0
                        let preflightOverride: (String, String?) -> KeychainAccessPreflight.Outcome = { _, _ in
                            .interactionRequired
                        }
                        let promptHandler: (KeychainPromptContext) -> Void = { _ in
                            preAlertHits += 1
                        }
                        let creds = try KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting(
                            preflightOverride,
                            operation: {
                                try KeychainPromptHandler.withHandlerForTesting(promptHandler, operation: {
                                    try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(
                                        .onlyOnUserAction)
                                    {
                                        try ProviderInteractionContext.$current.withValue(.userInitiated) {
                                            try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                                data: keychainData,
                                                fingerprint: nil)
                                            {
                                                try ClaudeOAuthCredentialsStore.load(
                                                    environment: [:],
                                                    allowKeychainPrompt: true)
                                            }
                                        }
                                    }
                                })
                            })

                        #expect(creds.accessToken == "keychain-token")
                        #expect(preAlertHits == 1)
                    }
                }
            }
        }
    }

    @Test
    func shows_pre_alert_when_claude_keychain_preflight_fails() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            try KeychainAccessGate.withTaskOverrideForTesting(false) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }

                try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    defer {
                        ClaudeOAuthCredentialsStore.invalidateCache()
                        ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    }

                    let tempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let fileURL = tempDir.appendingPathComponent("credentials.json")
                    try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                        let keychainData = self.makeCredentialsData(
                            accessToken: "keychain-token",
                            expiresAt: Date(timeIntervalSinceNow: 3600))

                        var preAlertHits = 0
                        let preflightOverride: (String, String?) -> KeychainAccessPreflight.Outcome = { _, _ in
                            .failure(-1)
                        }
                        let promptHandler: (KeychainPromptContext) -> Void = { _ in
                            preAlertHits += 1
                        }
                        let creds = try KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting(
                            preflightOverride,
                            operation: {
                                try KeychainPromptHandler.withHandlerForTesting(promptHandler, operation: {
                                    try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(
                                        .onlyOnUserAction)
                                    {
                                        try ProviderInteractionContext.$current.withValue(.userInitiated) {
                                            try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                                data: keychainData,
                                                fingerprint: nil)
                                            {
                                                try ClaudeOAuthCredentialsStore.load(
                                                    environment: [:],
                                                    allowKeychainPrompt: true)
                                            }
                                        }
                                    }
                                })
                            })

                        #expect(creds.accessToken == "keychain-token")
                        #expect(preAlertHits == 1)
                    }
                }
            }
        }
    }

    @Test
    func experimental_reader_skips_pre_alert_when_security_CLI_read_succeeds() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            try KeychainAccessGate.withTaskOverrideForTesting(false) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }

                try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    defer {
                        ClaudeOAuthCredentialsStore.invalidateCache()
                        ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    }

                    let tempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let fileURL = tempDir.appendingPathComponent("credentials.json")
                    try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                        let securityData = self.makeCredentialsData(
                            accessToken: "security-token",
                            expiresAt: Date(timeIntervalSinceNow: 3600))

                        var preAlertHits = 0
                        let preflightOverride: (String, String?) -> KeychainAccessPreflight.Outcome = { _, _ in
                            .interactionRequired
                        }
                        let promptHandler: (KeychainPromptContext) -> Void = { _ in
                            preAlertHits += 1
                        }
                        let creds = try KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting(
                            preflightOverride,
                            operation: {
                                try KeychainPromptHandler.withHandlerForTesting(promptHandler, operation: {
                                    try ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(
                                        .securityCLIExperimental)
                                    {
                                        try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.always) {
                                            try ProviderInteractionContext.$current.withValue(.userInitiated) {
                                                try ClaudeOAuthCredentialsStore.withSecurityCLIReadOverrideForTesting(
                                                    .data(securityData))
                                                {
                                                    try ClaudeOAuthCredentialsStore.load(
                                                        environment: [:],
                                                        allowKeychainPrompt: true)
                                                }
                                            }
                                        }
                                    }
                                })
                            })

                        #expect(creds.accessToken == "security-token")
                        #expect(preAlertHits == 0)
                    }
                }
            }
        }
    }

    @Test
    func experimental_reader_shows_pre_alert_when_security_CLI_fails_and_fallback_needs_interaction() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            try KeychainAccessGate.withTaskOverrideForTesting(false) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }

                try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    defer {
                        ClaudeOAuthCredentialsStore.invalidateCache()
                        ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    }

                    let tempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let fileURL = tempDir.appendingPathComponent("credentials.json")
                    try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                        let fallbackData = self.makeCredentialsData(
                            accessToken: "fallback-token",
                            expiresAt: Date(timeIntervalSinceNow: 3600))

                        var preAlertHits = 0
                        let preflightOverride: (String, String?) -> KeychainAccessPreflight.Outcome = { _, _ in
                            .interactionRequired
                        }
                        let promptHandler: (KeychainPromptContext) -> Void = { _ in
                            preAlertHits += 1
                        }
                        let creds = try KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting(
                            preflightOverride,
                            operation: {
                                try KeychainPromptHandler.withHandlerForTesting(promptHandler, operation: {
                                    try ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(
                                        .securityCLIExperimental)
                                    {
                                        try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.always) {
                                            try ProviderInteractionContext.$current.withValue(.userInitiated) {
                                                try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                                    data: fallbackData,
                                                    fingerprint: nil)
                                                {
                                                    try ClaudeOAuthCredentialsStore
                                                        .withSecurityCLIReadOverrideForTesting(.timedOut) {
                                                            try ClaudeOAuthCredentialsStore.load(
                                                                environment: [:],
                                                                allowKeychainPrompt: true)
                                                        }
                                                }
                                            }
                                        }
                                    }
                                })
                            })

                        #expect(creds.accessToken == "fallback-token")
                        #expect(preAlertHits == 1)
                    }
                }
            }
        }
    }

    @Test
    func experimental_reader_does_not_fallback_in_background_when_stored_mode_only_on_user_action() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            try KeychainAccessGate.withTaskOverrideForTesting(false) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }

                try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    defer {
                        ClaudeOAuthCredentialsStore.invalidateCache()
                        ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    }

                    let tempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let fileURL = tempDir.appendingPathComponent("credentials.json")
                    try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                        let fallbackData = self.makeCredentialsData(
                            accessToken: "fallback-token",
                            expiresAt: Date(timeIntervalSinceNow: 3600))

                        var preAlertHits = 0
                        let preflightOverride: (String, String?) -> KeychainAccessPreflight.Outcome = { _, _ in
                            .interactionRequired
                        }
                        let promptHandler: (KeychainPromptContext) -> Void = { _ in
                            preAlertHits += 1
                        }

                        do {
                            _ = try KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting(
                                preflightOverride,
                                operation: {
                                    try KeychainPromptHandler.withHandlerForTesting(promptHandler, operation: {
                                        try ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(
                                            .securityCLIExperimental)
                                        {
                                            try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(
                                                .onlyOnUserAction)
                                            {
                                                try ProviderInteractionContext.$current.withValue(.background) {
                                                    try ClaudeOAuthCredentialsStore
                                                        .withClaudeKeychainOverridesForTesting(
                                                            data: fallbackData,
                                                            fingerprint: nil)
                                                        {
                                                            try ClaudeOAuthCredentialsStore
                                                                .withSecurityCLIReadOverrideForTesting(.timedOut) {
                                                                    try ClaudeOAuthCredentialsStore.load(
                                                                        environment: [:],
                                                                        allowKeychainPrompt: true,
                                                                        respectKeychainPromptCooldown: true)
                                                                }
                                                        }
                                                }
                                            }
                                        }
                                    })
                                })
                            Issue.record("Expected ClaudeOAuthCredentialsError.notFound")
                        } catch let error as ClaudeOAuthCredentialsError {
                            guard case .notFound = error else {
                                Issue.record("Expected .notFound, got \(error)")
                                return
                            }
                        }

                        #expect(preAlertHits == 0)
                    }
                }
            }
        }
    }

    @Test
    func experimental_reader_does_not_fallback_when_stored_mode_never() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            try KeychainAccessGate.withTaskOverrideForTesting(false) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }

                try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    defer {
                        ClaudeOAuthCredentialsStore.invalidateCache()
                        ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    }

                    let tempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let fileURL = tempDir.appendingPathComponent("credentials.json")
                    try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                        let fallbackData = self.makeCredentialsData(
                            accessToken: "fallback-token",
                            expiresAt: Date(timeIntervalSinceNow: 3600))

                        var preAlertHits = 0
                        let preflightOverride: (String, String?) -> KeychainAccessPreflight.Outcome = { _, _ in
                            .interactionRequired
                        }
                        let promptHandler: (KeychainPromptContext) -> Void = { _ in
                            preAlertHits += 1
                        }

                        do {
                            _ = try KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting(
                                preflightOverride,
                                operation: {
                                    try KeychainPromptHandler.withHandlerForTesting(promptHandler, operation: {
                                        try ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(
                                            .securityCLIExperimental)
                                        {
                                            try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.never) {
                                                try ProviderInteractionContext.$current.withValue(.userInitiated) {
                                                    try ClaudeOAuthCredentialsStore
                                                        .withClaudeKeychainOverridesForTesting(
                                                            data: fallbackData,
                                                            fingerprint: nil)
                                                        {
                                                            try ClaudeOAuthCredentialsStore
                                                                .withSecurityCLIReadOverrideForTesting(.timedOut) {
                                                                    try ClaudeOAuthCredentialsStore.load(
                                                                        environment: [:],
                                                                        allowKeychainPrompt: true)
                                                                }
                                                        }
                                                }
                                            }
                                        }
                                    })
                                })
                            Issue.record("Expected ClaudeOAuthCredentialsError.notFound")
                        } catch let error as ClaudeOAuthCredentialsError {
                            guard case .notFound = error else {
                                Issue.record("Expected .notFound, got \(error)")
                                return
                            }
                        }

                        #expect(preAlertHits == 0)
                    }
                }
            }
        }
    }

    @Test
    func experimental_reader_non_interactive_fallback_blocked_in_background_when_stored_mode_only_on_user_action()
        throws
    {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            try KeychainAccessGate.withTaskOverrideForTesting(false) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }

                try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    defer {
                        ClaudeOAuthCredentialsStore.invalidateCache()
                        ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    }

                    let tempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let fileURL = tempDir.appendingPathComponent("credentials.json")
                    try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                        let fallbackData = self.makeCredentialsData(
                            accessToken: "fallback-token-only-on-user-action",
                            expiresAt: Date(timeIntervalSinceNow: 3600))
                        let preflightOverride: (String, String?) -> KeychainAccessPreflight.Outcome = { _, _ in
                            .allowed
                        }

                        do {
                            _ = try KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting(
                                preflightOverride,
                                operation: {
                                    try ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(
                                        .securityCLIExperimental)
                                    {
                                        try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(
                                            .onlyOnUserAction)
                                        {
                                            try ProviderInteractionContext.$current.withValue(.background) {
                                                try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                                    data: fallbackData,
                                                    fingerprint: nil)
                                                {
                                                    try ClaudeOAuthCredentialsStore
                                                        .withSecurityCLIReadOverrideForTesting(.timedOut) {
                                                            try ClaudeOAuthCredentialsStore.load(
                                                                environment: [:],
                                                                allowKeychainPrompt: false,
                                                                respectKeychainPromptCooldown: true)
                                                        }
                                                }
                                            }
                                        }
                                    }
                                })
                            Issue.record("Expected ClaudeOAuthCredentialsError.notFound")
                        } catch let error as ClaudeOAuthCredentialsError {
                            guard case .notFound = error else {
                                Issue.record("Expected .notFound, got \(error)")
                                return
                            }
                        }
                    }
                }
            }
        }
    }

    @Test
    func experimental_reader_allows_fallback_in_background_when_stored_mode_always() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            try KeychainAccessGate.withTaskOverrideForTesting(false) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }

                try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    defer {
                        ClaudeOAuthCredentialsStore.invalidateCache()
                        ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    }

                    let tempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let fileURL = tempDir.appendingPathComponent("credentials.json")
                    try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                        let fallbackData = self.makeCredentialsData(
                            accessToken: "fallback-token",
                            expiresAt: Date(timeIntervalSinceNow: 3600))

                        var preAlertHits = 0
                        let preflightOverride: (String, String?) -> KeychainAccessPreflight.Outcome = { _, _ in
                            .interactionRequired
                        }
                        let promptHandler: (KeychainPromptContext) -> Void = { _ in
                            preAlertHits += 1
                        }

                        let creds = try KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting(
                            preflightOverride,
                            operation: {
                                try KeychainPromptHandler.withHandlerForTesting(promptHandler, operation: {
                                    try ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(
                                        .securityCLIExperimental)
                                    {
                                        try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.always) {
                                            try ProviderInteractionContext.$current.withValue(.background) {
                                                try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                                    data: fallbackData,
                                                    fingerprint: nil)
                                                {
                                                    try ClaudeOAuthCredentialsStore
                                                        .withSecurityCLIReadOverrideForTesting(.timedOut) {
                                                            try ClaudeOAuthCredentialsStore.load(
                                                                environment: [:],
                                                                allowKeychainPrompt: true,
                                                                respectKeychainPromptCooldown: false)
                                                        }
                                                }
                                            }
                                        }
                                    }
                                })
                            })

                        #expect(creds.accessToken == "fallback-token")
                        #expect(preAlertHits == 1)
                    }
                }
            }
        }
    }
}
