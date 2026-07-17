import Foundation

public struct CCSwitcherImportSummary: Equatable, Sendable {
    public let imported: Int
    public let skipped: Int
    public let missingBackup: Int
    public let keychainDenied: Bool

    public init(imported: Int, skipped: Int, missingBackup: Int, keychainDenied: Bool) {
        self.imported = imported
        self.skipped = skipped
        self.missingBackup = missingBackup
        self.keychainDenied = keychainDenied
    }
}

/// Error taxonomy of the switch/capture/import transactions.
/// Cases map 1:1 to the design doc's §14 error table (ERR-*).
public enum ClaudeAccountServiceError: LocalizedError, Equatable, Sendable {
    case switchInProgress
    case accountNotFound
    case backupMissing
    case clashUnreachable(detail: String)
    case clashGroupMissing(group: String)
    case clashNodeMissing(group: String, node: String)
    case captureFailed(detail: String)
    case captureInvalid
    case switchWriteFailed(detail: String, rolledBack: Bool)
    case switchValidateFailed(detail: String, rolledBack: Bool)
    case importSourceMissing
    case storeFailed(detail: String)

    public var errorDescription: String? {
        switch self {
        case .switchInProgress:
            "Another account switch is already running."
        case .accountNotFound:
            "This Claude account no longer exists."
        case .backupMissing:
            "This account has no credential backup yet. Sign in with `claude /login`, "
                + "then use \u{201C}Add current account\u{201D} to capture it."
        case let .clashUnreachable(detail):
            "Switch aborted: \(detail) Credentials were not touched."
        case let .clashGroupMissing(group):
            "Switch aborted: Clash proxy group '\(group)' does not exist. Credentials were not touched."
        case let .clashNodeMissing(group, node):
            "Switch aborted: Clash node '\(node)' is not in group '\(group)'. "
                + "Rebind the account, credentials were not touched."
        case let .captureFailed(detail):
            "Could not capture the current Claude credentials: \(detail)"
        case .captureInvalid:
            "The current Claude keychain item has no claudeAiOauth credentials. "
                + "Run `claude /login` to repair it, then retry."
        case let .switchWriteFailed(detail, rolledBack):
            Self.appendRollbackHint(
                "Writing the target credentials failed: \(detail)",
                rolledBack: rolledBack)
        case let .switchValidateFailed(detail, rolledBack):
            Self.appendRollbackHint(
                "The target account failed validation: \(detail)",
                rolledBack: rolledBack)
        case .importSourceMissing:
            CCSwitcherImportError.sourceMissing.errorDescription
        case let .storeFailed(detail):
            "Could not persist the Claude account list: \(detail)"
        }
    }

    private static func appendRollbackHint(_ message: String, rolledBack: Bool) -> String {
        if rolledBack {
            return message + " The previous account was restored."
        }
        return message + " Automatic rollback also failed — run `claude /login` to restore a signed-in state."
    }
}

/// Orchestrates the native Claude multi-account transactions (capture, switch, import)
/// exactly as modeled by the design doc's §11 state machine. All transactions are
/// serialized: a second entry while one runs is rejected, never queued.
public actor ClaudeAccountService {
    public typealias AccessTokenValidator = @Sendable (_ accessToken: String) async throws -> Void
    public typealias TokenRefresher = @Sendable (_ refreshToken: String) async throws -> ClaudeRefreshedTokens

    /// Refresh slightly before the recorded expiry so a token that dies mid-validation
    /// does not force the 401 retry path.
    private static let tokenExpiryMargin: TimeInterval = 60

    private let store: any ClaudeManagedAccountStoring
    private let backups: any ClaudeCredentialBackupStoring
    private let systemCredentials: any ClaudeSystemCredentialAccessing
    private let importSource: any CCSwitcherImportReading
    private let makeClashClient: @Sendable (_ socketPath: String) -> any ClashProxyControlling
    private let validateAccessToken: AccessTokenValidator
    private let refreshTokens: TokenRefresher
    private let invalidateOAuthCache: @Sendable () -> Void
    private let now: @Sendable () -> Date
    private var transactionInProgress = false

    private static let log = CodexBarLog.logger(LogCategories.claudeAccounts)

    public init(
        store: any ClaudeManagedAccountStoring = FileClaudeManagedAccountStore(),
        backups: any ClaudeCredentialBackupStoring = KeychainClaudeCredentialBackupStore(),
        systemCredentials: any ClaudeSystemCredentialAccessing = ClaudeSystemCredentialStore(),
        importSource: any CCSwitcherImportReading = SystemCCSwitcherImportSource(),
        makeClashClient: @Sendable @escaping (_ socketPath: String) -> any ClashProxyControlling = {
            ClashVergeClient(socketPath: $0)
        },
        validateAccessToken: AccessTokenValidator? = nil,
        refreshTokens: TokenRefresher? = nil,
        invalidateOAuthCache: @Sendable @escaping () -> Void = {
            ClaudeOAuthCredentialsStore.invalidateCache()
        },
        now: @Sendable @escaping () -> Date = { Date() })
    {
        self.store = store
        self.backups = backups
        self.systemCredentials = systemCredentials
        self.importSource = importSource
        self.makeClashClient = makeClashClient
        self.validateAccessToken = validateAccessToken ?? { accessToken in
            _ = try await ClaudeOAuthUsageFetcher.fetchUsage(accessToken: accessToken)
        }
        self.refreshTokens = refreshTokens ?? { refreshToken in
            try await ClaudeAccountTokenRefresher.refresh(refreshToken: refreshToken)
        }
        self.invalidateOAuthCache = invalidateOAuthCache
        self.now = now
    }

    // MARK: - Reads

    public func currentSet() throws -> ClaudeManagedAccountSet {
        try self.store.load()
    }

    public func hasBackup(accountID: UUID) -> Bool {
        self.backups.load(accountID: accountID) != nil
    }

    // MARK: - Mutations (metadata only)

    public func updateClashSettings(_ settings: ClashConnectionSettings) throws {
        var set = try self.store.load()
        set.clash = settings
        try self.persist(set)
    }

    public func setCustomLabel(accountID: UUID, label: String?) throws {
        try self.mutateAccount(accountID: accountID) { account in
            let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
            account.customLabel = (trimmed?.isEmpty ?? true) ? nil : trimmed
        }
    }

    public func setClashBinding(accountID: UUID, group: String?, node: String?) throws {
        try self.mutateAccount(accountID: accountID) { account in
            if let node, !node.isEmpty {
                account.clashNode = node
                account.clashGroup = group
            } else {
                account.clashNode = nil
                account.clashGroup = nil
            }
        }
    }

    public func removeAccount(accountID: UUID) throws {
        var set = try self.store.load()
        guard set.account(id: accountID) != nil else { throw ClaudeAccountServiceError.accountNotFound }
        set.accounts.removeAll { $0.id == accountID }
        try self.persist(set)
        self.backups.clear(accountID: accountID)
        Self.log.info("Removed account \(accountID.uuidString)")
    }

    // MARK: - Capture (REQ-001)

    @discardableResult
    public func captureCurrentAccount() async throws -> ClaudeManagedAccount {
        try self.beginTransaction()
        defer { self.endTransaction() }
        let txID = Self.newTransactionID()

        let current = try await self.readCurrentForCapture(txID: txID)
        guard Self.blobHasClaudeAiOauth(current.credentialsBlob) else {
            Self.log.error("[\(txID)] capture rejected: keychain item has no claudeAiOauth")
            throw ClaudeAccountServiceError.captureInvalid
        }
        guard let email = current.emailAddress, !email.isEmpty else {
            throw ClaudeAccountServiceError.captureFailed(detail: "oauthAccount has no emailAddress")
        }

        var set = try self.store.load()
        let backup = ClaudeCredentialBackup(
            credentialsBlob: current.credentialsBlob,
            oauthAccountJSON: current.oauthAccountJSON,
            capturedAt: self.now())

        if var existing = set.account(email: email) {
            self.backups.store(backup, accountID: existing.id)
            existing.lastUsed = self.now()
            set.accounts = set.accounts.map { $0.id == existing.id ? existing : $0 }
            set.setActiveAccount(id: existing.id)
            try self.persist(set)
            Self.log.info("[\(txID)] capture refreshed backup for account \(existing.id.uuidString)")
            return existing
        }

        let account = ClaudeManagedAccount(email: email, isActive: true, lastUsed: self.now())
        self.backups.store(backup, accountID: account.id)
        set.accounts.append(account)
        set.setActiveAccount(id: account.id)
        try self.persist(set)
        Self.log.info("[\(txID)] captured new account \(account.id.uuidString)")
        return account
    }

    // MARK: - Switch (REQ-002 / REQ-004)

    public func switchTo(accountID: UUID) async throws {
        try self.beginTransaction()
        defer { self.endTransaction() }
        let txID = Self.newTransactionID()

        var set = try self.store.load()
        guard let target = set.account(id: accountID) else {
            throw ClaudeAccountServiceError.accountNotFound
        }
        guard let targetBackup = self.backups.load(accountID: target.id) else {
            throw ClaudeAccountServiceError.backupMissing
        }
        Self.log.info("[\(txID)] switch started → \(target.id.uuidString)")

        // Proxy first: a Clash failure must abort before credentials are touched.
        let proxyRollback = try await self.switchProxyIfBound(target: target, in: set, txID: txID)

        // Capture-before-write keeps the outgoing account's backup fresh.
        let current: ClaudeSystemCredentials
        do {
            current = try await self.systemCredentials.readCurrent()
        } catch {
            await self.restoreProxy(proxyRollback, txID: txID)
            Self.log.error("[\(txID)] switch failed capturing current credentials")
            throw ClaudeAccountServiceError.captureFailed(detail: error.localizedDescription)
        }
        if let email = current.emailAddress, let outgoing = set.account(email: email),
           Self.blobHasClaudeAiOauth(current.credentialsBlob)
        {
            self.backups.store(
                ClaudeCredentialBackup(
                    credentialsBlob: current.credentialsBlob,
                    oauthAccountJSON: current.oauthAccountJSON,
                    capturedAt: self.now()),
                accountID: outgoing.id)
            Self.log.info("[\(txID)] refreshed outgoing backup \(outgoing.id.uuidString)")
        }

        // Backups age while an account is inactive: access tokens expire within hours
        // (imported CCSwitcher backups virtually always need this) while the refresh
        // token stays valid. Refresh a stale token before it reaches the credential
        // position (API-004); credentials are still untouched if the refresh fails.
        var activeBackup = targetBackup
        if let fields = Self.credentialFields(fromCredentialsBlob: activeBackup.credentialsBlob),
           let expiresAt = fields.expiresAt,
           expiresAt <= self.now().addingTimeInterval(Self.tokenExpiryMargin),
           let refreshToken = fields.refreshToken
        {
            do {
                activeBackup = try await self.refreshedBackup(
                    activeBackup,
                    refreshToken: refreshToken,
                    accountID: target.id,
                    txID: txID)
            } catch {
                await self.restoreProxy(proxyRollback, txID: txID)
                Self.log.error("[\(txID)] pre-write token refresh failed")
                throw ClaudeAccountServiceError.switchValidateFailed(
                    detail: error.localizedDescription,
                    rolledBack: true)
            }
        }

        // Write the target credential position.
        do {
            try await self.systemCredentials.write(
                credentialsBlob: activeBackup.credentialsBlob,
                oauthAccountJSON: activeBackup.oauthAccountJSON)
        } catch {
            let rolledBack = await self.rollbackCredentials(to: current, txID: txID)
            await self.restoreProxy(proxyRollback, txID: txID)
            Self.log.error("[\(txID)] switch write failed (rolledBack=\(rolledBack))")
            throw ClaudeAccountServiceError.switchWriteFailed(
                detail: error.localizedDescription,
                rolledBack: rolledBack)
        }

        // Validate via the OAuth usage endpoint (ADR-003); a first-try 401 gets one
        // refresh-and-retry before the transaction is declared failed (API-004).
        do {
            guard let fields = Self.credentialFields(fromCredentialsBlob: activeBackup.credentialsBlob) else {
                throw ClaudeAccountServiceError.captureInvalid
            }
            do {
                try await self.validateAccessToken(fields.accessToken)
            } catch let error as ClaudeOAuthFetchError {
                guard case .unauthorized = error, let refreshToken = fields.refreshToken else { throw error }
                Self.log.info("[\(txID)] usage returned 401; refreshing token and retrying once")
                activeBackup = try await self.refreshedBackup(
                    activeBackup,
                    refreshToken: refreshToken,
                    accountID: target.id,
                    txID: txID)
                try await self.systemCredentials.write(
                    credentialsBlob: activeBackup.credentialsBlob,
                    oauthAccountJSON: activeBackup.oauthAccountJSON)
                guard let retryToken = Self.accessToken(fromCredentialsBlob: activeBackup.credentialsBlob)
                else {
                    throw ClaudeAccountServiceError.captureInvalid
                }
                try await self.validateAccessToken(retryToken)
            }
        } catch {
            let rolledBack = await self.rollbackCredentials(to: current, txID: txID)
            await self.restoreProxy(proxyRollback, txID: txID)
            self.invalidateOAuthCache()
            Self.log.error("[\(txID)] switch validation failed (rolledBack=\(rolledBack))")
            throw ClaudeAccountServiceError.switchValidateFailed(
                detail: error.localizedDescription,
                rolledBack: rolledBack)
        }

        var updatedTarget = target
        updatedTarget.lastUsed = self.now()
        set.accounts = set.accounts.map { $0.id == updatedTarget.id ? updatedTarget : $0 }
        set.setActiveAccount(id: updatedTarget.id)
        try self.persist(set)
        self.invalidateOAuthCache()
        Self.log.info("[\(txID)] switch completed → \(updatedTarget.id.uuidString)")
    }

    // MARK: - Import (REQ-005)

    public func importFromCCSwitcher() async throws -> CCSwitcherImportSummary {
        try self.beginTransaction()
        defer { self.endTransaction() }
        let txID = Self.newTransactionID()

        let records: [CCSwitcherAccountRecord]
        do {
            records = try self.importSource.readAccounts()
                .filter { $0.provider == SystemCCSwitcherImportSource.claudeProviderName }
        } catch is CCSwitcherImportError {
            throw ClaudeAccountServiceError.importSourceMissing
        }
        guard !records.isEmpty else {
            throw ClaudeAccountServiceError.importSourceMissing
        }

        var keychainDenied = false
        var backupRecords: [String: CCSwitcherBackupRecord] = [:]
        do {
            backupRecords = try self.importSource.readBackups()
        } catch {
            // Metadata-only import stays possible; accounts surface as "needs capture".
            keychainDenied = true
            Self.log.error("[\(txID)] CCSwitcher backup read denied or failed")
        }

        var set = try self.store.load()
        var imported = 0
        var skipped = 0
        var missingBackup = 0

        for record in records {
            let email = ClaudeManagedAccount.normalizeEmail(record.email)
            guard set.account(email: email) == nil else {
                skipped += 1
                continue
            }
            let account = ClaudeManagedAccount(
                id: record.id,
                email: email,
                displayName: record.displayName,
                subscriptionType: record.subscriptionType,
                customLabel: record.customLabel,
                clashGroup: record.clashProxyName != nil
                    ? (record.clashProxyGroupName ?? set.clash.defaultGroup)
                    : nil,
                clashNode: record.clashProxyName,
                isActive: false,
                lastUsed: record.lastUsed)
            if let backup = backupRecords[record.id.uuidString.uppercased()] {
                self.backups.store(
                    ClaudeCredentialBackup(
                        credentialsBlob: backup.token,
                        oauthAccountJSON: backup.oauthAccountJSON,
                        capturedAt: self.now()),
                    accountID: account.id)
            } else {
                missingBackup += 1
            }
            set.accounts.append(account)
            imported += 1
        }

        // Active flag is re-derived from the live identity, never copied from CCSwitcher.
        if let liveEmail = try? self.systemCredentials.readIdentityEmail(),
           let liveAccount = set.account(email: liveEmail)
        {
            set.setActiveAccount(id: liveAccount.id)
        }
        try self.persist(set)
        Self.log.info(
            "[\(txID)] import finished: imported=\(imported) skipped=\(skipped) "
                + "missingBackup=\(missingBackup) denied=\(keychainDenied)")
        return CCSwitcherImportSummary(
            imported: imported,
            skipped: skipped,
            missingBackup: missingBackup,
            keychainDenied: keychainDenied)
    }

    public nonisolated static func ccSwitcherDataLooksPresent(
        plistURL: URL = SystemCCSwitcherImportSource.defaultPlistURL()) -> Bool
    {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    // MARK: - Blob parsing

    struct BlobCredentialFields {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
    }

    static func credentialFields(fromCredentialsBlob blob: String) -> BlobCredentialFields? {
        guard let data = blob.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else {
            return nil
        }
        let refreshToken = (oauth["refreshToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        // Claude Code stores expiresAt as milliseconds since the Unix epoch.
        let expiresAt = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return BlobCredentialFields(accessToken: token, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    static func accessToken(fromCredentialsBlob blob: String) -> String? {
        self.credentialFields(fromCredentialsBlob: blob)?.accessToken
    }

    /// Rewrites the token triple inside the blob's `claudeAiOauth` object, preserving
    /// every other key (scopes, subscriptionType, mcpOAuth, …) verbatim.
    static func blobReplacingTokens(_ blob: String, with tokens: ClaudeRefreshedTokens) -> String? {
        guard let data = blob.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var oauth = object["claudeAiOauth"] as? [String: Any]
        else {
            return nil
        }
        oauth["accessToken"] = tokens.accessToken
        oauth["refreshToken"] = tokens.refreshToken
        oauth["expiresAt"] = tokens.expiresAt.timeIntervalSince1970 * 1000
        object["claudeAiOauth"] = oauth
        guard let output = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(bytes: output, encoding: .utf8)
    }

    static func blobHasClaudeAiOauth(_ blob: String) -> Bool {
        guard let data = blob.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        return object["claudeAiOauth"] is [String: Any]
    }

    // MARK: - Transaction plumbing

    private struct ProxyRollback {
        let group: String
        let previousNode: String?
    }

    private func switchProxyIfBound(
        target: ClaudeManagedAccount,
        in set: ClaudeManagedAccountSet,
        txID: String) async throws -> ProxyRollback?
    {
        guard let node = target.clashNode, !node.isEmpty else { return nil }
        let group = target.clashGroup ?? set.clash.defaultGroup
        let clash = self.makeClashClient(set.clash.socketPath)
        let status: ClashProxyGroupStatus
        do {
            status = try await clash.groupStatus(group: group)
        } catch let error as ClashVergeClientError {
            throw Self.mapClashError(error, group: group, node: node)
        }
        guard status.all.contains(node) else {
            throw ClaudeAccountServiceError.clashNodeMissing(group: group, node: node)
        }
        do {
            try await clash.switchNode(group: group, node: node)
        } catch let error as ClashVergeClientError {
            throw Self.mapClashError(error, group: group, node: node)
        }
        Self.log.info("[\(txID)] clash switched group to bound node (was \(status.now ?? "unknown"))")
        return ProxyRollback(group: group, previousNode: status.now)
    }

    private func restoreProxy(_ rollback: ProxyRollback?, txID: String) async {
        guard let rollback, let previousNode = rollback.previousNode else { return }
        do {
            let set = try self.store.load()
            let clash = self.makeClashClient(set.clash.socketPath)
            try await clash.switchNode(group: rollback.group, node: previousNode)
            Self.log.info("[\(txID)] clash restored previous node")
        } catch {
            Self.log.error("[\(txID)] clash restore failed: \(error.localizedDescription)")
        }
    }

    /// Refreshes a backup's tokens via API-004 and persists the refreshed backup
    /// immediately: refresh tokens rotate on use, so the old pair is dead either way.
    private func refreshedBackup(
        _ backup: ClaudeCredentialBackup,
        refreshToken: String,
        accountID: UUID,
        txID: String) async throws -> ClaudeCredentialBackup
    {
        let tokens = try await self.refreshTokens(refreshToken)
        guard let newBlob = Self.blobReplacingTokens(backup.credentialsBlob, with: tokens) else {
            throw ClaudeAccountServiceError.captureInvalid
        }
        let refreshed = ClaudeCredentialBackup(
            credentialsBlob: newBlob,
            oauthAccountJSON: backup.oauthAccountJSON,
            capturedAt: self.now())
        self.backups.store(refreshed, accountID: accountID)
        Self.log.info("[\(txID)] refreshed backup tokens for \(accountID.uuidString)")
        return refreshed
    }

    private func rollbackCredentials(to previous: ClaudeSystemCredentials, txID: String) async -> Bool {
        do {
            try await self.systemCredentials.write(
                credentialsBlob: previous.credentialsBlob,
                oauthAccountJSON: previous.oauthAccountJSON)
            Self.log.info("[\(txID)] credentials rolled back")
            return true
        } catch {
            Self.log.error("[\(txID)] credential rollback failed: \(error.localizedDescription)")
            return false
        }
    }

    private func readCurrentForCapture(txID: String) async throws -> ClaudeSystemCredentials {
        do {
            return try await self.systemCredentials.readCurrent()
        } catch {
            Self.log.error("[\(txID)] capture read failed")
            throw ClaudeAccountServiceError.captureFailed(detail: error.localizedDescription)
        }
    }

    private static func mapClashError(
        _ error: ClashVergeClientError,
        group: String,
        node: String) -> ClaudeAccountServiceError
    {
        switch error {
        case let .unreachable(detail):
            .clashUnreachable(detail: detail)
        case let .groupMissing(missingGroup):
            .clashGroupMissing(group: missingGroup)
        case .nodeMissing:
            .clashNodeMissing(group: group, node: node)
        case let .invalidResponse(detail):
            .clashUnreachable(detail: detail)
        }
    }

    private func beginTransaction() throws {
        guard !self.transactionInProgress else { throw ClaudeAccountServiceError.switchInProgress }
        self.transactionInProgress = true
    }

    private func endTransaction() {
        self.transactionInProgress = false
    }

    private func persist(_ set: ClaudeManagedAccountSet) throws {
        do {
            try self.store.store(set)
        } catch {
            throw ClaudeAccountServiceError.storeFailed(detail: error.localizedDescription)
        }
    }

    private func mutateAccount(accountID: UUID, _ mutate: (inout ClaudeManagedAccount) -> Void) throws {
        var set = try self.store.load()
        guard var account = set.account(id: accountID) else {
            throw ClaudeAccountServiceError.accountNotFound
        }
        mutate(&account)
        set.accounts = set.accounts.map { $0.id == accountID ? account : $0 }
        try self.persist(set)
    }

    private static func newTransactionID() -> String {
        String(UUID().uuidString.prefix(8))
    }
}
