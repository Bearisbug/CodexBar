import Foundation

/// The live system credential position: the `Claude Code-credentials` keychain item
/// plus the `oauthAccount` block inside `~/.claude.json`.
public struct ClaudeSystemCredentials: Equatable, Sendable {
    public let credentialsBlob: String
    public let oauthAccountJSON: Data
    public let emailAddress: String?

    public init(credentialsBlob: String, oauthAccountJSON: Data, emailAddress: String?) {
        self.credentialsBlob = credentialsBlob
        self.oauthAccountJSON = oauthAccountJSON
        self.emailAddress = emailAddress
    }
}

public enum ClaudeSystemCredentialError: LocalizedError, Equatable, Sendable {
    case keychainReadFailed(detail: String)
    case keychainWriteFailed(detail: String)
    case claudeConfigUnreadable(detail: String)
    case oauthAccountMissing
    case claudeConfigWriteFailed(detail: String)

    public var errorDescription: String? {
        switch self {
        case let .keychainReadFailed(detail):
            "Could not read the Claude Code keychain credentials. Run `claude` once to sign in. (\(detail))"
        case let .keychainWriteFailed(detail):
            "Could not write the Claude Code keychain credentials. (\(detail))"
        case let .claudeConfigUnreadable(detail):
            "Could not read ~/.claude.json. Run `claude` once to create it. (\(detail))"
        case .oauthAccountMissing:
            "~/.claude.json has no oauthAccount block. Run `claude` once to sign in."
        case let .claudeConfigWriteFailed(detail):
            "Could not update ~/.claude.json. (\(detail))"
        }
    }
}

public protocol ClaudeSystemCredentialAccessing: Sendable {
    /// Reads the full live credential position. May trigger a user-visible keychain
    /// prompt; call only from user-initiated flows.
    func readCurrent() async throws -> ClaudeSystemCredentials
    /// Reads only the identity email from `~/.claude.json` (never touches the keychain).
    func readIdentityEmail() throws -> String?
    /// Replaces the live credential position atomically (keychain item + oauthAccount block).
    func write(credentialsBlob: String, oauthAccountJSON: Data) async throws
}

/// Real implementation backed by `/usr/bin/security` for both reads and writes
/// (matching CCSwitcher and the Claude CLI's item ownership, see ADR-004), plus an
/// atomic `~/.claude.json` rewrite that preserves every other key in the file.
public struct ClaudeSystemCredentialStore: ClaudeSystemCredentialAccessing {
    public typealias SecurityRunner = @Sendable (_ arguments: [String], _ toleratesFailure: Bool) async throws
        -> String

    public static let keychainService = "Claude Code-credentials"

    private let claudeConfigURL: URL
    private let keychainAccountName: String
    private let runSecurity: SecurityRunner

    public init(
        claudeConfigURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json"),
        keychainAccountName: String = NSUserName(),
        runSecurity: SecurityRunner? = nil)
    {
        self.claudeConfigURL = claudeConfigURL
        self.keychainAccountName = keychainAccountName
        self.runSecurity = runSecurity ?? Self.defaultSecurityRunner
    }

    public func readCurrent() async throws -> ClaudeSystemCredentials {
        let blob: String
        do {
            blob = try await self.runSecurity([
                "find-generic-password",
                "-s", Self.keychainService,
                "-a", self.keychainAccountName,
                "-w",
            ], false).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw ClaudeSystemCredentialError.keychainReadFailed(detail: error.localizedDescription)
        }
        guard !blob.isEmpty else {
            throw ClaudeSystemCredentialError.keychainReadFailed(detail: "keychain item is empty")
        }
        let oauthAccount = try self.readOAuthAccountObject()
        let oauthAccountJSON = try Self.serializeOAuthAccount(oauthAccount)
        return ClaudeSystemCredentials(
            credentialsBlob: blob,
            oauthAccountJSON: oauthAccountJSON,
            emailAddress: oauthAccount["emailAddress"] as? String)
    }

    public func readIdentityEmail() throws -> String? {
        try self.readOAuthAccountObject()["emailAddress"] as? String
    }

    /// Writes through the `security` CLI so the item stays owned by the security tool —
    /// exactly the ownership the Claude CLI and CCSwitcher expect, keeping their reads
    /// prompt-free. The write updates the item in place, so its ACL survives the switch.
    public func write(credentialsBlob: String, oauthAccountJSON: Data) async throws {
        // `-U` updates an existing generic password in place: `cdat` is preserved and only
        // `mdat` advances. Deleting the item first would destroy its ACL — including any
        // "Always Allow" the user granted — so every switch would re-prompt for keychain
        // access. `-U` also creates the item when it is missing, so no delete is needed.
        do {
            _ = try await self.runSecurity([
                "add-generic-password",
                "-s", Self.keychainService,
                "-a", self.keychainAccountName,
                "-w", credentialsBlob,
                "-U",
            ], false)
        } catch {
            throw ClaudeSystemCredentialError.keychainWriteFailed(detail: error.localizedDescription)
        }
        try self.writeOAuthAccount(oauthAccountJSON: oauthAccountJSON)
    }

    // MARK: - ~/.claude.json plumbing

    private func readClaudeConfigObject() throws -> [String: Any] {
        let data: Data
        do {
            data = try Data(contentsOf: self.claudeConfigURL)
        } catch {
            throw ClaudeSystemCredentialError.claudeConfigUnreadable(detail: error.localizedDescription)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeSystemCredentialError.claudeConfigUnreadable(detail: "top-level JSON is not an object")
        }
        return object
    }

    private func readOAuthAccountObject() throws -> [String: Any] {
        guard let oauthAccount = try self.readClaudeConfigObject()["oauthAccount"] as? [String: Any] else {
            throw ClaudeSystemCredentialError.oauthAccountMissing
        }
        return oauthAccount
    }

    private func writeOAuthAccount(oauthAccountJSON: Data) throws {
        guard let oauthAccount = try? JSONSerialization.jsonObject(with: oauthAccountJSON) as? [String: Any]
        else {
            throw ClaudeSystemCredentialError.claudeConfigWriteFailed(detail: "backup oauthAccount is malformed")
        }
        var config = try self.readClaudeConfigObject()
        config["oauthAccount"] = oauthAccount
        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: self.claudeConfigURL, options: [.atomic])
        } catch {
            throw ClaudeSystemCredentialError.claudeConfigWriteFailed(detail: error.localizedDescription)
        }
    }

    static func serializeOAuthAccount(_ object: [String: Any]) throws -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        } catch {
            throw ClaudeSystemCredentialError.claudeConfigUnreadable(detail: "oauthAccount is not serializable")
        }
    }

    /// Keychain prompts (item ACL) can appear during these calls, so they run without
    /// a read timeout: the user answers the prompt at their own pace.
    @Sendable
    private static func defaultSecurityRunner(
        arguments: [String],
        toleratesFailure: Bool) async throws -> String
    {
        let result = try await SubprocessRunner.runToCompletion(
            binary: "/usr/bin/security",
            arguments: arguments,
            environment: [:],
            acceptsNonZeroExit: toleratesFailure,
            label: "claude-accounts security")
        return result.stdout
    }
}
