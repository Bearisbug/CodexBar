import Foundation
import Testing
@testable import CodexBarCore

#if os(macOS)
@Suite(.serialized)
struct ClaudeOAuthCredentialsStoreIsolatedSecurityCLITests {
    @Test
    func safety_blocks_security_CLI_access_to_the_login_keychain() {
        let blockedEnvironment = [KeychainTestSafety.suppressAccessEnvironmentKey: "1"]
        #expect(ClaudeOAuthCredentialsStore.securityCLIReadArguments(
            account: nil,
            environment: blockedEnvironment) == nil)

        let explicitOptIn = [
            KeychainTestSafety.suppressAccessEnvironmentKey: "1",
            KeychainTestSafety.allowAccessEnvironmentKey: "1",
        ]
        let expectedArguments = [
            "find-generic-password",
            "-s",
            "Claude Code-credentials",
            "-w",
        ]
        #expect(ClaudeOAuthCredentialsStore.securityCLIReadArguments(
            account: nil,
            environment: explicitOptIn) == expectedArguments)
    }

    @Test
    func isolated_security_CLI_keychain_requires_global_keychain_disable() {
        let keychainPath = "/tmp/codexbar-fixtures/verify.keychain-db"
        let isolatedEnvironment = [
            KeychainAccessGate.disableAccessEnvironmentKey: "1",
            ClaudeOAuthCredentialsStore.isolatedSecurityCLIKeychainEnvironmentKey: keychainPath,
        ]
        let expectedArguments = [
            "find-generic-password",
            "-s",
            "Claude Code-credentials",
            "-w",
            keychainPath,
        ]

        #expect(KeychainAccessGate.isDisabledByEnvironment(isolatedEnvironment))
        #expect(ClaudeOAuthCredentialsStore.securityCLIReadArguments(
            account: nil,
            environment: isolatedEnvironment) == expectedArguments)
        #expect(ClaudeOAuthCredentialsStore.securityCLIReadArguments(
            account: nil,
            environment: [
                ClaudeOAuthCredentialsStore.isolatedSecurityCLIKeychainEnvironmentKey: keychainPath,
            ]) == nil)
        #expect(ClaudeOAuthCredentialsStore.securityCLIReadArguments(
            account: nil,
            environment: [KeychainAccessGate.disableAccessEnvironmentKey: "1"]) == nil)
        #expect(ClaudeOAuthCredentialsStore.securityCLIReadArguments(
            account: nil,
            environment: [
                KeychainAccessGate.disableAccessEnvironmentKey: "1",
                ClaudeOAuthCredentialsStore.isolatedSecurityCLIKeychainEnvironmentKey: "relative.keychain-db",
            ]) == nil)
    }

    @Test
    func isolated_security_CLI_keychain_remains_readable_while_other_keychain_access_is_disabled() {
        let mcpOnlyPayload = Data(#"{"mcpOAuth":{"plugin:test":{"accessToken":"synthetic"}}}"#.utf8)
        let environment = [
            KeychainAccessGate.disableAccessEnvironmentKey: "1",
            ClaudeOAuthCredentialsStore.isolatedSecurityCLIKeychainEnvironmentKey: "/tmp/verify.keychain-db",
        ]

        let isMcpOnly = ClaudeOAuthCredentialsStore.withSecurityCLIReadOverrideForTesting(.data(mcpOnlyPayload)) {
            ClaudeOAuthCredentialsStore.isMcpOAuthOnlyClaudeKeychainPayloadPresent(
                interaction: .background,
                readStrategy: .securityCLIExperimental,
                keychainAccessDisabled: true,
                environment: environment)
        }
        #expect(isMcpOnly)

        let blockedWithoutIsolatedKeychain = ClaudeOAuthCredentialsStore
            .withSecurityCLIReadOverrideForTesting(.data(mcpOnlyPayload)) {
                ClaudeOAuthCredentialsStore.isMcpOAuthOnlyClaudeKeychainPayloadPresent(
                    interaction: .background,
                    readStrategy: .securityCLIExperimental,
                    keychainAccessDisabled: true,
                    environment: [KeychainAccessGate.disableAccessEnvironmentKey: "1"])
            }
        #expect(blockedWithoutIsolatedKeychain == false)
    }

    @Test
    func never_prompt_mode_still_detects_MCP_only_payload_via_experimental_security_CLI_reader() {
        let mcpOnlyPayload = Data(#"{"mcpOAuth":{"plugin:test":{"accessToken":"synthetic"}}}"#.utf8)
        let environment = [
            KeychainAccessGate.disableAccessEnvironmentKey: "1",
            ClaudeOAuthCredentialsStore.isolatedSecurityCLIKeychainEnvironmentKey: "/tmp/verify.keychain-db",
        ]

        let isMcpOnly = ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.never) {
            ClaudeOAuthCredentialsStore.withSecurityCLIReadOverrideForTesting(.data(mcpOnlyPayload)) {
                ClaudeOAuthCredentialsStore.isMcpOAuthOnlyClaudeKeychainPayloadPresent(
                    interaction: .background,
                    readStrategy: .securityCLIExperimental,
                    keychainAccessDisabled: true,
                    environment: environment)
            }
        }
        #expect(!isMcpOnly)

        let blockedViaSecurityFramework = ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.never) {
            ClaudeOAuthCredentialsStore.withSecurityCLIReadOverrideForTesting(.data(mcpOnlyPayload)) {
                ClaudeOAuthCredentialsStore.isMcpOAuthOnlyClaudeKeychainPayloadPresent(
                    interaction: .background,
                    readStrategy: .securityFramework,
                    keychainAccessDisabled: false,
                    environment: [:])
            }
        }
        #expect(!blockedViaSecurityFramework)
    }
}
#endif
