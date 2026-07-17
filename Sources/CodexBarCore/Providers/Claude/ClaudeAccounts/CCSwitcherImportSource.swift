import Foundation
#if os(macOS)
import Security
#endif

/// One CCSwitcher account row decoded from its preferences plist
/// (`com.ccswitcher.accounts`, a JSON-encoded array stored as data).
public struct CCSwitcherAccountRecord: Decodable, Equatable, Sendable {
    public let id: UUID
    public let email: String
    public let displayName: String?
    public let provider: String
    public let subscriptionType: String?
    public let customLabel: String?
    public let clashProxyName: String?
    public let clashProxyGroupName: String?
    public let isActive: Bool?
    public let lastUsed: Date?

    public init(
        id: UUID,
        email: String,
        displayName: String? = nil,
        provider: String,
        subscriptionType: String? = nil,
        customLabel: String? = nil,
        clashProxyName: String? = nil,
        clashProxyGroupName: String? = nil,
        isActive: Bool? = nil,
        lastUsed: Date? = nil)
    {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.provider = provider
        self.subscriptionType = subscriptionType
        self.customLabel = customLabel
        self.clashProxyName = clashProxyName
        self.clashProxyGroupName = clashProxyGroupName
        self.isActive = isActive
        self.lastUsed = lastUsed
    }
}

/// One CCSwitcher credential backup (`{token, oauthAccount}`) keyed by account UUID.
public struct CCSwitcherBackupRecord: Equatable, Sendable {
    public let token: String
    public let oauthAccountJSON: Data

    public init(token: String, oauthAccountJSON: Data) {
        self.token = token
        self.oauthAccountJSON = oauthAccountJSON
    }
}

public enum CCSwitcherImportError: LocalizedError, Equatable, Sendable {
    case sourceMissing
    case keychainDenied(status: Int32)
    case malformedData(detail: String)

    public var errorDescription: String? {
        switch self {
        case .sourceMissing:
            "No CCSwitcher data was found on this Mac."
        case let .keychainDenied(status):
            "macOS denied access to the CCSwitcher credential backups (status \(status)). "
                + "Click Allow on the keychain prompt to import them."
        case let .malformedData(detail):
            "CCSwitcher data could not be parsed. (\(detail))"
        }
    }
}

public protocol CCSwitcherImportReading: Sendable {
    /// Reads account metadata from the CCSwitcher preferences plist (no keychain access).
    func readAccounts() throws -> [CCSwitcherAccountRecord]
    /// Reads credential backups from CCSwitcher's keychain item. Triggers a one-time
    /// system keychain ACL prompt; call only from the user-initiated import action.
    func readBackups() throws -> [String: CCSwitcherBackupRecord]
}

/// Read-only access to CCSwitcher's on-disk data (never mutates the source).
public struct SystemCCSwitcherImportSource: CCSwitcherImportReading {
    public static let claudeProviderName = "Claude Code"
    public static let accountsDefaultsKey = "com.ccswitcher.accounts"
    public static let backupKeychainService = "me.xueshi.ccswitcher.backups"
    public static let backupKeychainAccount = "all-accounts"

    private let plistURL: URL

    public init(plistURL: URL = Self.defaultPlistURL()) {
        self.plistURL = plistURL
    }

    public static func defaultPlistURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/me.xueshi.ccswitcher.plist")
    }

    public func readAccounts() throws -> [CCSwitcherAccountRecord] {
        guard FileManager.default.fileExists(atPath: self.plistURL.path) else {
            throw CCSwitcherImportError.sourceMissing
        }
        let plistData: Data
        do {
            plistData = try Data(contentsOf: self.plistURL)
        } catch {
            throw CCSwitcherImportError.malformedData(detail: error.localizedDescription)
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
              let root = plist as? [String: Any]
        else {
            throw CCSwitcherImportError.malformedData(detail: "preferences plist is not a dictionary")
        }
        guard let accountsData = root[Self.accountsDefaultsKey] as? Data else {
            throw CCSwitcherImportError.sourceMissing
        }
        return try Self.decodeAccounts(accountsData)
    }

    public func readBackups() throws -> [String: CCSwitcherBackupRecord] {
        #if os(macOS)
        // Deliberately no KeychainNoUIQuery here: the ACL prompt is the expected,
        // user-approved path into CCSwitcher's backup item (design doc §12 import flow).
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.backupKeychainService,
            kSecAttrAccount as String: Self.backupKeychainAccount,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        let status = KeychainSecurity.copyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw CCSwitcherImportError.malformedData(detail: "backup keychain item is empty")
            }
            return try Self.decodeBackups(data)
        case errSecItemNotFound:
            return [:]
        default:
            throw CCSwitcherImportError.keychainDenied(status: status)
        }
        #else
        return [:]
        #endif
    }

    static func decodeAccounts(_ data: Data) throws -> [CCSwitcherAccountRecord] {
        do {
            // CCSwitcher encodes with Foundation defaults: dates are seconds since
            // the reference epoch, which is exactly JSONDecoder's default strategy.
            return try JSONDecoder().decode([CCSwitcherAccountRecord].self, from: data)
        } catch {
            throw CCSwitcherImportError.malformedData(detail: "accounts JSON: \(error.localizedDescription)")
        }
    }

    static func decodeBackups(_ data: Data) throws -> [String: CCSwitcherBackupRecord] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CCSwitcherImportError.malformedData(detail: "backups JSON is not a dictionary")
        }
        var backups: [String: CCSwitcherBackupRecord] = [:]
        for (accountID, value) in root {
            guard let entry = value as? [String: Any],
                  let token = entry["token"] as? String,
                  let oauthAccount = entry["oauthAccount"] as? [String: Any],
                  let oauthAccountJSON = try? JSONSerialization.data(
                      withJSONObject: oauthAccount,
                      options: [.sortedKeys])
            else {
                continue
            }
            backups[accountID.uppercased()] = CCSwitcherBackupRecord(
                token: token,
                oauthAccountJSON: oauthAccountJSON)
        }
        return backups
    }
}
