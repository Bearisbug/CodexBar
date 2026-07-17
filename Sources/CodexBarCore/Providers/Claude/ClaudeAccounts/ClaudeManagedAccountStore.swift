import Foundation

public enum FileClaudeManagedAccountStoreError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
}

public protocol ClaudeManagedAccountStoring: Sendable {
    func load() throws -> ClaudeManagedAccountSet
    func store(_ set: ClaudeManagedAccountSet) throws
}

/// Atomic JSON file store for native Claude accounts, mirroring
/// `FileManagedCodexAccountStore` (see ADR-006 in the design doc).
public struct FileClaudeManagedAccountStore: ClaudeManagedAccountStoring, @unchecked Sendable {
    public static let currentVersion = 1

    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL = Self.defaultURL(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> ClaudeManagedAccountSet {
        guard self.fileManager.fileExists(atPath: self.fileURL.path) else {
            return Self.emptyAccountSet()
        }
        let data = try Data(contentsOf: self.fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let set = try decoder.decode(ClaudeManagedAccountSet.self, from: data)
        guard (1...Self.currentVersion).contains(set.version) else {
            throw FileClaudeManagedAccountStoreError.unsupportedVersion(set.version)
        }
        return set
    }

    public func store(_ set: ClaudeManagedAccountSet) throws {
        let normalized = ClaudeManagedAccountSet(
            version: Self.currentVersion,
            clash: set.clash,
            accounts: set.accounts)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(normalized)
        let directory = self.fileURL.deletingLastPathComponent()
        if !self.fileManager.fileExists(atPath: directory.path) {
            try self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try data.write(to: self.fileURL, options: [.atomic])
        try self.applySecurePermissionsIfNeeded()
    }

    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("CodexBar", isDirectory: true)
            .appendingPathComponent("managed-claude-accounts.json")
    }

    private func applySecurePermissionsIfNeeded() throws {
        #if os(macOS)
        try self.fileManager.setAttributes([
            .posixPermissions: NSNumber(value: Int16(0o600)),
        ], ofItemAtPath: self.fileURL.path)
        #endif
    }

    private static func emptyAccountSet() -> ClaudeManagedAccountSet {
        ClaudeManagedAccountSet(version: self.currentVersion, accounts: [])
    }
}
