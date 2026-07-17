import Foundation

/// App-level Clash Verge connection settings shared by all native Claude accounts.
/// Design: `docs/claude-native-multi-account-clash.md` (ENT-ClashConnection).
public struct ClashConnectionSettings: Codable, Equatable, Sendable {
    public static let defaultSocketPath = "/tmp/verge/verge-mihomo.sock"
    public static let defaultGroupName = "GLOBAL"

    public var socketPath: String
    public var defaultGroup: String

    public init(
        socketPath: String = Self.defaultSocketPath,
        defaultGroup: String = Self.defaultGroupName)
    {
        self.socketPath = socketPath
        self.defaultGroup = defaultGroup
    }
}

/// One natively managed Claude subscription account.
/// Design: `docs/claude-native-multi-account-clash.md` (ENT-ClaudeAccount).
public struct ClaudeManagedAccount: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var email: String
    public var displayName: String?
    public var subscriptionType: String?
    public var customLabel: String?
    /// Clash binding: both nil (no proxy sync) or both set. `clashGroup` falls back to
    /// `ClashConnectionSettings.defaultGroup` when nil while `clashNode` is set.
    public var clashGroup: String?
    public var clashNode: String?
    public var isActive: Bool
    public var lastUsed: Date?

    public init(
        id: UUID = UUID(),
        email: String,
        displayName: String? = nil,
        subscriptionType: String? = nil,
        customLabel: String? = nil,
        clashGroup: String? = nil,
        clashNode: String? = nil,
        isActive: Bool = false,
        lastUsed: Date? = nil)
    {
        self.id = id
        self.email = Self.normalizeEmail(email)
        self.displayName = displayName
        self.subscriptionType = subscriptionType
        self.customLabel = customLabel
        self.clashGroup = clashGroup
        self.clashNode = clashNode
        self.isActive = isActive
        self.lastUsed = lastUsed
    }

    /// User-facing title: non-empty custom label wins, otherwise the email.
    public var displayTitle: String {
        if let label = self.customLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        return self.email
    }

    public static func normalizeEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            email: container.decode(String.self, forKey: .email),
            displayName: container.decodeIfPresent(String.self, forKey: .displayName),
            subscriptionType: container.decodeIfPresent(String.self, forKey: .subscriptionType),
            customLabel: container.decodeIfPresent(String.self, forKey: .customLabel),
            clashGroup: container.decodeIfPresent(String.self, forKey: .clashGroup),
            clashNode: container.decodeIfPresent(String.self, forKey: .clashNode),
            isActive: container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false,
            lastUsed: container.decodeIfPresent(Date.self, forKey: .lastUsed))
    }
}

/// Persisted account list plus Clash connection settings.
public struct ClaudeManagedAccountSet: Codable, Equatable, Sendable {
    public let version: Int
    public var clash: ClashConnectionSettings
    public var accounts: [ClaudeManagedAccount]

    public init(
        version: Int,
        clash: ClashConnectionSettings = ClashConnectionSettings(),
        accounts: [ClaudeManagedAccount])
    {
        self.version = version
        self.clash = clash
        self.accounts = Self.sanitizedAccounts(accounts)
    }

    public func account(id: UUID) -> ClaudeManagedAccount? {
        self.accounts.first { $0.id == id }
    }

    public func account(email: String) -> ClaudeManagedAccount? {
        let normalized = ClaudeManagedAccount.normalizeEmail(email)
        return self.accounts.first { $0.email == normalized }
    }

    public var activeAccount: ClaudeManagedAccount? {
        self.accounts.first(where: \.isActive)
    }

    /// Marks exactly one account active (or none when `id` is nil / unknown).
    public mutating func setActiveAccount(id: UUID?) {
        self.accounts = self.accounts.map { account in
            var updated = account
            updated.isActive = account.id == id
            return updated
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            version: container.decode(Int.self, forKey: .version),
            clash: container.decodeIfPresent(ClashConnectionSettings.self, forKey: .clash)
                ?? ClashConnectionSettings(),
            accounts: container.decode([ClaudeManagedAccount].self, forKey: .accounts))
    }

    private static func sanitizedAccounts(_ accounts: [ClaudeManagedAccount]) -> [ClaudeManagedAccount] {
        var seenIDs: Set<UUID> = []
        var seenEmails: Set<String> = []
        var sanitized: [ClaudeManagedAccount] = []
        sanitized.reserveCapacity(accounts.count)
        for account in accounts {
            guard seenIDs.insert(account.id).inserted else { continue }
            guard seenEmails.insert(account.email).inserted else { continue }
            sanitized.append(account)
        }
        return sanitized
    }
}
