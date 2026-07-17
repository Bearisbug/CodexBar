import Foundation

/// Credential snapshot for one native Claude account (ENT-CredentialBackup).
///
/// `credentialsBlob` is the verbatim `Claude Code-credentials` keychain item payload;
/// `oauthAccountJSON` is the verbatim serialized `oauthAccount` object from `~/.claude.json`.
/// Both are swapped as-is; only `claudeAiOauth.accessToken` is ever parsed out (for validation).
public struct ClaudeCredentialBackup: Codable, Equatable, Sendable {
    public let credentialsBlob: String
    public let oauthAccountJSON: Data
    public let capturedAt: Date

    public init(credentialsBlob: String, oauthAccountJSON: Data, capturedAt: Date) {
        self.credentialsBlob = credentialsBlob
        self.oauthAccountJSON = oauthAccountJSON
        self.capturedAt = capturedAt
    }
}

public protocol ClaudeCredentialBackupStoring: Sendable {
    func load(accountID: UUID) -> ClaudeCredentialBackup?
    @discardableResult
    func store(_ backup: ClaudeCredentialBackup, accountID: UUID) -> Bool
    func clear(accountID: UUID)
}

/// Keychain-backed backup store (one entry per account) built on `KeychainCacheStore`.
public struct KeychainClaudeCredentialBackupStore: ClaudeCredentialBackupStoring {
    public static let category = "claude-account-backup"

    public init() {}

    public func load(accountID: UUID) -> ClaudeCredentialBackup? {
        switch KeychainCacheStore.load(key: Self.key(for: accountID), as: ClaudeCredentialBackup.self) {
        case let .found(backup):
            backup
        case .missing, .temporarilyUnavailable, .invalid:
            nil
        }
    }

    @discardableResult
    public func store(_ backup: ClaudeCredentialBackup, accountID: UUID) -> Bool {
        KeychainCacheStore.storeResult(key: Self.key(for: accountID), entry: backup)
    }

    public func clear(accountID: UUID) {
        KeychainCacheStore.clear(key: Self.key(for: accountID))
    }

    private static func key(for accountID: UUID) -> KeychainCacheStore.Key {
        KeychainCacheStore.Key(category: self.category, identifier: accountID.uuidString)
    }
}
