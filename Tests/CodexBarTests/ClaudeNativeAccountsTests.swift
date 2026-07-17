import Foundation
import Testing
@testable import CodexBarCore

// MARK: - Shared fakes

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [String] = []

    var events: [String] {
        self.lock.withLock { self.recordedEvents }
    }

    func record(_ event: String) {
        self.lock.withLock { self.recordedEvents.append(event) }
    }
}

private final class InMemoryAccountStore: ClaudeManagedAccountStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var set: ClaudeManagedAccountSet

    init(_ set: ClaudeManagedAccountSet) {
        self.set = set
    }

    func load() throws -> ClaudeManagedAccountSet {
        self.lock.withLock { self.set }
    }

    func store(_ set: ClaudeManagedAccountSet) throws {
        self.lock.withLock { self.set = set }
    }
}

private final class InMemoryBackupStore: ClaudeCredentialBackupStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var backups: [UUID: ClaudeCredentialBackup] = [:]

    init(_ backups: [UUID: ClaudeCredentialBackup] = [:]) {
        self.backups = backups
    }

    func load(accountID: UUID) -> ClaudeCredentialBackup? {
        self.lock.withLock { self.backups[accountID] }
    }

    @discardableResult
    func store(_ backup: ClaudeCredentialBackup, accountID: UUID) -> Bool {
        self.lock.withLock { self.backups[accountID] = backup }
        return true
    }

    func clear(accountID: UUID) {
        _ = self.lock.withLock { self.backups.removeValue(forKey: accountID) }
    }
}

private final class FakeSystemCredentials: ClaudeSystemCredentialAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private let log: EventLog
    var current: ClaudeSystemCredentials?
    var readErrorDetail: String?
    var failNextWrites = 0
    var identityEmail: String?

    init(current: ClaudeSystemCredentials?, log: EventLog = EventLog()) {
        self.current = current
        self.identityEmail = current?.emailAddress
        self.log = log
    }

    func readCurrent() async throws -> ClaudeSystemCredentials {
        self.log.record("read-current")
        let (credentials, errorDetail) = self.lock.withLock { (self.current, self.readErrorDetail) }
        if let errorDetail {
            throw ClaudeSystemCredentialError.keychainReadFailed(detail: errorDetail)
        }
        guard let credentials else {
            throw ClaudeSystemCredentialError.keychainReadFailed(detail: "no scripted credentials")
        }
        return credentials
    }

    func readIdentityEmail() throws -> String? {
        self.lock.withLock { self.identityEmail }
    }

    func write(credentialsBlob: String, oauthAccountJSON: Data) async throws {
        let shouldFail: Bool = self.lock.withLock {
            if self.failNextWrites > 0 {
                self.failNextWrites -= 1
                return true
            }
            return false
        }
        if shouldFail {
            self.log.record("write-failed")
            throw ClaudeSystemCredentialError.keychainWriteFailed(detail: "scripted failure")
        }
        let email = (try? JSONSerialization.jsonObject(with: oauthAccountJSON) as? [String: Any])?["emailAddress"]
            as? String
        self.log.record("write:\(email ?? "?")")
        self.lock.withLock {
            self.current = ClaudeSystemCredentials(
                credentialsBlob: credentialsBlob,
                oauthAccountJSON: oauthAccountJSON,
                emailAddress: email)
            self.identityEmail = email
        }
    }
}

private final class FakeClash: ClashProxyControlling, @unchecked Sendable {
    private let log: EventLog
    private let lock = NSLock()
    var groupStatusResult: Result<ClashProxyGroupStatus, ClashVergeClientError>
    var switchNodeError: ClashVergeClientError?

    init(
        groupStatusResult: Result<ClashProxyGroupStatus, ClashVergeClientError> =
            .success(ClashProxyGroupStatus(now: "OldNode", all: ["OldNode", "NodeA", "NodeB"])),
        log: EventLog = EventLog())
    {
        self.groupStatusResult = groupStatusResult
        self.log = log
    }

    func groupStatus(group: String) async throws -> ClashProxyGroupStatus {
        self.log.record("clash-status:\(group)")
        return try self.lock.withLock { self.groupStatusResult }.get()
    }

    func switchNode(group: String, node: String) async throws {
        self.log.record("clash-switch:\(group):\(node)")
        if let error = self.lock.withLock({ self.switchNodeError }) {
            throw error
        }
    }
}

private struct FakeImportSource: CCSwitcherImportReading {
    var accounts: [CCSwitcherAccountRecord]
    var backups: [String: CCSwitcherBackupRecord]
    var backupsDenied = false

    func readAccounts() throws -> [CCSwitcherAccountRecord] {
        if self.accounts.isEmpty {
            throw CCSwitcherImportError.sourceMissing
        }
        return self.accounts
    }

    func readBackups() throws -> [String: CCSwitcherBackupRecord] {
        if self.backupsDenied {
            throw CCSwitcherImportError.keychainDenied(status: -128)
        }
        return self.backups
    }
}

// MARK: - Fixtures

private enum Fixtures {
    /// Year-2100 in milliseconds: a "not expired" default so switch tests exercise
    /// the plain validation path unless a test opts into expiry.
    static let farFutureExpiryMs: Double = 4_102_444_800_000

    static func blob(
        token: String,
        refreshToken: String = "r",
        expiresAtMs: Double = Fixtures.farFutureExpiryMs) -> String
    {
        #"{"claudeAiOauth":{"accessToken":"\#(token)","refreshToken":"\#(refreshToken)","expiresAt":\#(expiresAtMs)}}"#
    }

    static let mcpOnlyBlob = #"{"mcpOAuth":{"someServer":{"accessToken":"x"}}}"#

    static func oauthAccountJSON(email: String) -> Data {
        Data(#"{"accountUuid":"uuid-\#(email)","emailAddress":"\#(email)"}"#.utf8)
    }

    static func credentials(email: String, token: String) -> ClaudeSystemCredentials {
        ClaudeSystemCredentials(
            credentialsBlob: self.blob(token: token),
            oauthAccountJSON: self.oauthAccountJSON(email: email),
            emailAddress: email)
    }

    static func backup(
        email: String,
        token: String,
        expiresAtMs: Double = Fixtures.farFutureExpiryMs) -> ClaudeCredentialBackup
    {
        ClaudeCredentialBackup(
            credentialsBlob: self.blob(token: token, expiresAtMs: expiresAtMs),
            oauthAccountJSON: self.oauthAccountJSON(email: email),
            capturedAt: Date(timeIntervalSince1970: 0))
    }

    static func accountSet(_ accounts: [ClaudeManagedAccount]) -> ClaudeManagedAccountSet {
        ClaudeManagedAccountSet(
            version: FileClaudeManagedAccountStore.currentVersion,
            clash: ClashConnectionSettings(),
            accounts: accounts)
    }
}

/// First-call-fails validator scripting: outcomes are consumed per call; when the
/// list runs out, calls succeed.
private final class ValidationScript: @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [ClaudeOAuthFetchError?]

    init(_ outcomes: [ClaudeOAuthFetchError?]) {
        self.outcomes = outcomes
    }

    func next() -> ClaudeOAuthFetchError? {
        self.lock.withLock {
            self.outcomes.isEmpty ? nil : self.outcomes.removeFirst()
        }
    }
}

private struct ServiceHarness {
    let service: ClaudeAccountService
    let store: InMemoryAccountStore
    let backups: InMemoryBackupStore
    let credentials: FakeSystemCredentials
    let clash: FakeClash
    let log: EventLog
    let validatedTokens: EventLog
    let refreshedTokens: EventLog
    let seededBlobs: EventLog

    init(
        accounts: [ClaudeManagedAccount],
        backupsByID: [UUID: ClaudeCredentialBackup],
        current: ClaudeSystemCredentials?,
        clashStatus: Result<ClashProxyGroupStatus, ClashVergeClientError> =
            .success(ClashProxyGroupStatus(now: "OldNode", all: ["OldNode", "NodeA", "NodeB"])),
        importSource: FakeImportSource = FakeImportSource(accounts: [], backups: [:]),
        validationError: ClaudeOAuthFetchError? = nil,
        validationOutcomes: [ClaudeOAuthFetchError?]? = nil,
        refreshResult: Result<ClaudeRefreshedTokens, ClaudeAccountTokenRefreshError>? = nil,
        loginAction: (@Sendable (FakeSystemCredentials) async throws -> Void)? = nil)
    {
        let log = EventLog()
        let validatedTokens = EventLog()
        let refreshedTokens = EventLog()
        let seededBlobs = EventLog()
        let store = InMemoryAccountStore(Fixtures.accountSet(accounts))
        let backupStore = InMemoryBackupStore(backupsByID)
        let credentials = FakeSystemCredentials(current: current, log: log)
        let clash = FakeClash(groupStatusResult: clashStatus, log: log)
        let script = validationOutcomes.map(ValidationScript.init)
        self.service = ClaudeAccountService(
            store: store,
            backups: backupStore,
            systemCredentials: credentials,
            importSource: importSource,
            makeClashClient: { _ in clash },
            validateAccessToken: { token in
                validatedTokens.record(token)
                if let scripted = script?.next() {
                    throw scripted
                }
                if script == nil, let validationError {
                    throw validationError
                }
            },
            refreshTokens: { refreshToken in
                refreshedTokens.record(refreshToken)
                guard let refreshResult else {
                    throw ClaudeAccountTokenRefreshError.requestFailed(detail: "no scripted refresh result")
                }
                return try refreshResult.get()
            },
            runClaudeLogin: {
                guard let loginAction else {
                    throw ClaudeAccountLoginRunnerError.cliNotFound
                }
                try await loginAction(credentials)
            },
            seedOAuthCache: { blob in seededBlobs.record(blob) },
            now: { Date(timeIntervalSince1970: 1000) })
        self.store = store
        self.backups = backupStore
        self.credentials = credentials
        self.clash = clash
        self.log = log
        self.validatedTokens = validatedTokens
        self.refreshedTokens = refreshedTokens
        self.seededBlobs = seededBlobs
    }
}

// MARK: - ClashVergeClient parsing

struct ClashVergeClientParsingTests {
    @Test
    func status_marker_splits_body_from_http_code() throws {
        let parsed = try ClashVergeClient.splitStatusLine(output: "{\"all\":[]}\n200")
        #expect(parsed.status == 200)
        #expect(parsed.body == "{\"all\":[]}")
    }

    @Test
    func missing_status_marker_is_an_invalid_response() {
        #expect(throws: ClashVergeClientError.self) {
            try ClashVergeClient.splitStatusLine(output: "no-marker")
        }
    }

    @Test
    func group_status_parses_now_and_all() throws {
        let status = try ClashVergeClient.parseGroupStatus(
            body: #"{"all":["A","B"],"now":"A","type":"Selector"}"#)
        #expect(status.now == "A")
        #expect(status.all == ["A", "B"])
    }

    @Test
    func group_404_maps_to_groupMissing() async {
        let client = ClashVergeClient(socketPath: "/tmp/x.sock", runCurl: { _ in "{}\n404" })
        await #expect(throws: ClashVergeClientError.groupMissing(group: "GLOBAL")) {
            try await client.groupStatus(group: "GLOBAL")
        }
    }

    @Test
    func curl_failure_maps_to_unreachable() async {
        struct CurlFailed: Error {}
        let client = ClashVergeClient(socketPath: "/tmp/x.sock", runCurl: { _ in throw CurlFailed() })
        do {
            _ = try await client.groupStatus(group: "GLOBAL")
            Issue.record("expected unreachable")
        } catch let error as ClashVergeClientError {
            guard case .unreachable = error else {
                Issue.record("expected unreachable, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test
    func switch_node_accepts_204_and_rejects_404() async throws {
        let ok = ClashVergeClient(socketPath: "/tmp/x.sock", runCurl: { _ in "\n204" })
        try await ok.switchNode(group: "GLOBAL", node: "A")

        let missing = ClashVergeClient(socketPath: "/tmp/x.sock", runCurl: { _ in "{}\n404" })
        await #expect(throws: ClashVergeClientError.nodeMissing(group: "GLOBAL", node: "A")) {
            try await missing.switchNode(group: "GLOBAL", node: "A")
        }
    }

    @Test
    func path_components_escape_spaces_but_keep_plain_names() {
        #expect(ClashVergeClient.encodePathComponent("GLOBAL") == "GLOBAL")
        #expect(ClashVergeClient.encodePathComponent("My Group") == "My%20Group")
        #expect(ClashVergeClient.encodePathComponent("a/b") == "a%2Fb")
    }
}

// MARK: - File store

struct ClaudeManagedAccountStoreTests {
    @Test
    func round_trip_preserves_accounts_clash_settings_and_dates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-accounts-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileClaudeManagedAccountStore(
            fileURL: directory.appendingPathComponent("managed-claude-accounts.json"))

        let account = ClaudeManagedAccount(
            email: "User@Example.com",
            subscriptionType: "max",
            customLabel: "Main",
            clashGroup: "GLOBAL",
            clashNode: "NodeA",
            isActive: true,
            lastUsed: Date(timeIntervalSince1970: 12345))
        var set = Fixtures.accountSet([account])
        set.clash = ClashConnectionSettings(socketPath: "/tmp/custom.sock", defaultGroup: "Proxies")
        try store.store(set)

        let loaded = try store.load()
        #expect(loaded.accounts.count == 1)
        #expect(loaded.accounts[0].email == "user@example.com")
        #expect(loaded.accounts[0].clashNode == "NodeA")
        #expect(loaded.accounts[0].lastUsed == Date(timeIntervalSince1970: 12345))
        #expect(loaded.clash.socketPath == "/tmp/custom.sock")
        #expect(loaded.clash.defaultGroup == "Proxies")
    }

    @Test
    func future_version_is_rejected_instead_of_silently_rewritten() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-accounts-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("managed-claude-accounts.json")
        try Data(#"{"version":99,"accounts":[]}"#.utf8).write(to: fileURL)

        let store = FileClaudeManagedAccountStore(fileURL: fileURL)
        #expect(throws: FileClaudeManagedAccountStoreError.unsupportedVersion(99)) {
            try store.load()
        }
    }

    @Test
    func duplicate_emails_and_ids_are_sanitized() {
        let id = UUID()
        let set = Fixtures.accountSet([
            ClaudeManagedAccount(id: id, email: "a@example.com"),
            ClaudeManagedAccount(id: id, email: "other@example.com"),
            ClaudeManagedAccount(email: "A@Example.com"),
            ClaudeManagedAccount(email: "b@example.com"),
        ])
        #expect(set.accounts.map(\.email) == ["a@example.com", "b@example.com"])
    }
}

// MARK: - CCSwitcher decoding

struct CCSwitcherDecodingTests {
    @Test
    func accounts_decode_with_reference_epoch_dates_and_bindings() throws {
        let json = """
        [{"id":"5CC6C707-6F8B-4C35-B21D-D344120F2228","email":"a@example.com",
          "displayName":"a display","provider":"Claude Code","subscriptionType":"max",
          "customLabel":"Main","clashProxyName":"NodeA","clashProxyGroupName":"GLOBAL",
          "isActive":true,"lastUsed":805960070.5}]
        """
        let accounts = try SystemCCSwitcherImportSource.decodeAccounts(Data(json.utf8))
        #expect(accounts.count == 1)
        let account = accounts[0]
        #expect(account.id == UUID(uuidString: "5CC6C707-6F8B-4C35-B21D-D344120F2228"))
        #expect(account.clashProxyName == "NodeA")
        #expect(account.clashProxyGroupName == "GLOBAL")
        #expect(account.lastUsed == Date(timeIntervalSinceReferenceDate: 805_960_070.5))
    }

    @Test
    func backups_decode_tokens_and_oauth_account_with_uppercased_keys() throws {
        let json = """
        {"5cc6c707-6f8b-4c35-b21d-d344120f2228":
            {"token":"blob-a","oauthAccount":{"emailAddress":"a@example.com"}},
         "broken": {"token": 42}}
        """
        let backups = try SystemCCSwitcherImportSource.decodeBackups(Data(json.utf8))
        #expect(backups.count == 1)
        let record = try #require(backups["5CC6C707-6F8B-4C35-B21D-D344120F2228"])
        #expect(record.token == "blob-a")
        let oauth = try JSONSerialization.jsonObject(with: record.oauthAccountJSON) as? [String: Any]
        #expect(oauth?["emailAddress"] as? String == "a@example.com")
    }
}

// MARK: - Capture (REQ-001)

struct ClaudeAccountServiceCaptureTests {
    @Test
    func capture_creates_a_new_active_account_with_a_backup() async throws {
        let harness = ServiceHarness(
            accounts: [],
            backupsByID: [:],
            current: Fixtures.credentials(email: "a@example.com", token: "tok-a"))

        let account = try await harness.service.captureCurrentAccount()
        #expect(account.email == "a@example.com")
        #expect(account.isActive)
        let set = try harness.store.load()
        #expect(set.accounts.count == 1)
        #expect(harness.backups.load(accountID: account.id)?.credentialsBlob == Fixtures.blob(token: "tok-a"))
    }

    @Test
    func capture_with_an_existing_email_refreshes_the_backup_instead_of_duplicating() async throws {
        let existing = ClaudeManagedAccount(email: "a@example.com", customLabel: "Main")
        let harness = ServiceHarness(
            accounts: [existing, ClaudeManagedAccount(email: "b@example.com", isActive: true)],
            backupsByID: [existing.id: Fixtures.backup(email: "a@example.com", token: "stale")],
            current: Fixtures.credentials(email: "A@Example.com", token: "fresh"))

        let captured = try await harness.service.captureCurrentAccount()
        #expect(captured.id == existing.id)
        let set = try harness.store.load()
        #expect(set.accounts.count == 2)
        #expect(set.activeAccount?.id == existing.id)
        #expect(harness.backups.load(accountID: existing.id)?.credentialsBlob == Fixtures.blob(token: "fresh"))
    }

    @Test
    func capture_rejects_a_keychain_item_without_claudeAiOauth() async {
        let harness = ServiceHarness(
            accounts: [],
            backupsByID: [:],
            current: ClaudeSystemCredentials(
                credentialsBlob: Fixtures.mcpOnlyBlob,
                oauthAccountJSON: Fixtures.oauthAccountJSON(email: "a@example.com"),
                emailAddress: "a@example.com"))

        await #expect(throws: ClaudeAccountServiceError.captureInvalid) {
            try await harness.service.captureCurrentAccount()
        }
    }
}

// MARK: - Login new account (REQ-009)

struct ClaudeAccountServiceLoginTests {
    @Test
    func login_backs_up_the_current_account_then_captures_the_new_identity() async throws {
        let existing = ClaudeManagedAccount(email: "a@example.com", isActive: true)
        let harness = ServiceHarness(
            accounts: [existing],
            backupsByID: [existing.id: Fixtures.backup(email: "a@example.com", token: "stale")],
            current: Fixtures.credentials(email: "a@example.com", token: "fresh-a"),
            loginAction: { credentials in
                credentials.current = Fixtures.credentials(email: "new@example.com", token: "tok-new")
                credentials.identityEmail = "new@example.com"
            })

        let account = try await harness.service.loginNewAccount()

        #expect(account.email == "new@example.com")
        #expect(account.isActive)
        let set = try harness.store.load()
        #expect(set.accounts.count == 2)
        #expect(set.activeAccount?.id == account.id)
        // The signed-in account's backup was refreshed before the login overwrote it.
        #expect(harness.backups.load(accountID: existing.id)?.credentialsBlob.contains("fresh-a") == true)
        #expect(harness.backups.load(accountID: account.id)?.credentialsBlob.contains("tok-new") == true)
    }

    @Test
    func missing_claude_cli_is_reported_without_touching_accounts() async throws {
        let existing = ClaudeManagedAccount(email: "a@example.com", isActive: true)
        let harness = ServiceHarness(
            accounts: [existing],
            backupsByID: [:],
            current: Fixtures.credentials(email: "a@example.com", token: "tok-a"))

        await #expect(throws: ClaudeAccountServiceError.claudeCLIMissing) {
            try await harness.service.loginNewAccount()
        }
        let set = try harness.store.load()
        #expect(set.accounts.count == 1)
    }
}

// MARK: - Switch (REQ-002 / REQ-004)

struct ClaudeAccountServiceSwitchTests {
    private static func twoAccounts(bindTarget: Bool) -> (active: ClaudeManagedAccount, target: ClaudeManagedAccount) {
        let active = ClaudeManagedAccount(email: "a@example.com", isActive: true)
        let target = ClaudeManagedAccount(
            email: "b@example.com",
            clashGroup: bindTarget ? "GLOBAL" : nil,
            clashNode: bindTarget ? "NodeA" : nil)
        return (active, target)
    }

    @Test
    func unbound_switch_swaps_credentials_without_touching_clash() async throws {
        let (active, target) = Self.twoAccounts(bindTarget: false)
        let harness = ServiceHarness(
            accounts: [active, target],
            backupsByID: [target.id: Fixtures.backup(email: "b@example.com", token: "tok-b")],
            current: Fixtures.credentials(email: "a@example.com", token: "tok-a"))

        try await harness.service.switchTo(accountID: target.id)

        #expect(!harness.log.events.contains { $0.hasPrefix("clash-") })
        #expect(harness.log.events.contains("write:b@example.com"))
        #expect(harness.validatedTokens.events == ["tok-b"])
        #expect(harness.seededBlobs.events.count == 1)
        #expect(harness.seededBlobs.events.first?.contains("tok-b") == true)
        let set = try harness.store.load()
        #expect(set.activeAccount?.id == target.id)
        #expect(set.account(id: target.id)?.lastUsed != nil)
    }

    @Test
    func bound_switch_drives_clash_before_any_credential_write() async throws {
        let (active, target) = Self.twoAccounts(bindTarget: true)
        let harness = ServiceHarness(
            accounts: [active, target],
            backupsByID: [target.id: Fixtures.backup(email: "b@example.com", token: "tok-b")],
            current: Fixtures.credentials(email: "a@example.com", token: "tok-a"))

        try await harness.service.switchTo(accountID: target.id)

        let events = harness.log.events
        let switchIndex = try #require(events.firstIndex(of: "clash-switch:GLOBAL:NodeA"))
        let writeIndex = try #require(events.firstIndex(of: "write:b@example.com"))
        #expect(switchIndex < writeIndex)
    }

    @Test
    func clash_unreachable_aborts_before_credentials_are_touched() async {
        let (active, target) = Self.twoAccounts(bindTarget: true)
        let harness = ServiceHarness(
            accounts: [active, target],
            backupsByID: [target.id: Fixtures.backup(email: "b@example.com", token: "tok-b")],
            current: Fixtures.credentials(email: "a@example.com", token: "tok-a"),
            clashStatus: .failure(.unreachable(detail: "no socket")))

        await #expect(throws: ClaudeAccountServiceError.self) {
            try await harness.service.switchTo(accountID: target.id)
        }
        #expect(!harness.log.events.contains { $0.hasPrefix("write") })
        #expect(!harness.log.events.contains("read-current"))
    }

    @Test
    func bound_node_missing_from_the_group_aborts_the_switch() async {
        let (active, target) = Self.twoAccounts(bindTarget: true)
        let harness = ServiceHarness(
            accounts: [active, target],
            backupsByID: [target.id: Fixtures.backup(email: "b@example.com", token: "tok-b")],
            current: Fixtures.credentials(email: "a@example.com", token: "tok-a"),
            clashStatus: .success(ClashProxyGroupStatus(now: "OldNode", all: ["OldNode", "Other"])))

        await #expect(throws: ClaudeAccountServiceError.clashNodeMissing(group: "GLOBAL", node: "NodeA")) {
            try await harness.service.switchTo(accountID: target.id)
        }
        #expect(!harness.log.events.contains { $0.hasPrefix("write") })
    }

    @Test
    func definitive_credential_death_rolls_back_credentials_and_proxy() async throws {
        let (active, target) = Self.twoAccounts(bindTarget: true)
        let harness = ServiceHarness(
            accounts: [active, target],
            backupsByID: [
                active.id: Fixtures.backup(email: "a@example.com", token: "tok-a"),
                target.id: Fixtures.backup(email: "b@example.com", token: "tok-b"),
            ],
            current: Fixtures.credentials(email: "a@example.com", token: "tok-a"),
            validationError: .unauthorized,
            refreshResult: .failure(.rejected(status: 400, detail: "invalid_grant")))

        do {
            try await harness.service.switchTo(accountID: target.id)
            Issue.record("expected switchValidateFailed")
        } catch let error as ClaudeAccountServiceError {
            guard case let .switchValidateFailed(_, rolledBack) = error else {
                Issue.record("expected switchValidateFailed, got \(error)")
                return
            }
            #expect(rolledBack)
        }

        let events = harness.log.events
        #expect(events.count(where: { $0 == "write:b@example.com" }) == 1)
        #expect(events.last == "clash-switch:GLOBAL:OldNode")
        #expect(events.contains("write:a@example.com"))
        #expect(harness.credentials.current?.emailAddress == "a@example.com")
        let set = try harness.store.load()
        #expect(set.activeAccount?.id == active.id)
    }

    @Test
    func write_failure_rolls_back_and_reports_it() async throws {
        let (active, target) = Self.twoAccounts(bindTarget: false)
        let harness = ServiceHarness(
            accounts: [active, target],
            backupsByID: [target.id: Fixtures.backup(email: "b@example.com", token: "tok-b")],
            current: Fixtures.credentials(email: "a@example.com", token: "tok-a"))
        harness.credentials.failNextWrites = 1

        do {
            try await harness.service.switchTo(accountID: target.id)
            Issue.record("expected switchWriteFailed")
        } catch let error as ClaudeAccountServiceError {
            guard case let .switchWriteFailed(_, rolledBack) = error else {
                Issue.record("expected switchWriteFailed, got \(error)")
                return
            }
            #expect(rolledBack)
        }
        #expect(harness.credentials.current?.emailAddress == "a@example.com")
        #expect(harness.validatedTokens.events.isEmpty)
    }

    @Test
    func switching_without_a_backup_is_rejected() async {
        let (active, target) = Self.twoAccounts(bindTarget: false)
        let harness = ServiceHarness(
            accounts: [active, target],
            backupsByID: [:],
            current: Fixtures.credentials(email: "a@example.com", token: "tok-a"))

        await #expect(throws: ClaudeAccountServiceError.backupMissing) {
            try await harness.service.switchTo(accountID: target.id)
        }
    }

    @Test
    func switch_refreshes_the_outgoing_account_backup_before_writing() async throws {
        let (active, target) = Self.twoAccounts(bindTarget: false)
        let harness = ServiceHarness(
            accounts: [active, target],
            backupsByID: [
                active.id: Fixtures.backup(email: "a@example.com", token: "stale"),
                target.id: Fixtures.backup(email: "b@example.com", token: "tok-b"),
            ],
            current: Fixtures.credentials(email: "a@example.com", token: "freshest"))

        try await harness.service.switchTo(accountID: target.id)
        #expect(harness.backups.load(accountID: active.id)?.credentialsBlob == Fixtures.blob(token: "freshest"))
    }

    @Test
    func a_second_transaction_is_rejected_while_one_is_running() async throws {
        let (active, target) = Self.twoAccounts(bindTarget: false)
        let gate = EventLog()
        let store = InMemoryAccountStore(Fixtures.accountSet([active, target]))
        let backups = InMemoryBackupStore([
            target.id: Fixtures.backup(email: "b@example.com", token: "tok-b"),
        ])
        let credentials = FakeSystemCredentials(
            current: Fixtures.credentials(email: "a@example.com", token: "tok-a"))
        let service = ClaudeAccountService(
            store: store,
            backups: backups,
            systemCredentials: credentials,
            importSource: FakeImportSource(accounts: [], backups: [:]),
            makeClashClient: { _ in FakeClash() },
            validateAccessToken: { _ in
                gate.record("validating")
                try await Task.sleep(nanoseconds: 300_000_000)
            },
            seedOAuthCache: { _ in },
            now: { Date(timeIntervalSince1970: 1000) })

        async let first: Void = service.switchTo(accountID: target.id)
        while gate.events.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        await #expect(throws: ClaudeAccountServiceError.switchInProgress) {
            try await service.captureCurrentAccount()
        }
        try await first
    }
}

// MARK: - Token refresh during switch (REQ-002 / API-004)

struct ClaudeAccountServiceTokenRefreshTests {
    private static let freshTokens = ClaudeRefreshedTokens(
        accessToken: "fresh-token",
        refreshToken: "fresh-refresh",
        expiresAt: Date(timeIntervalSince1970: 2_000_000_000))

    private static func accounts() -> (active: ClaudeManagedAccount, target: ClaudeManagedAccount) {
        (
            ClaudeManagedAccount(email: "a@example.com", isActive: true),
            ClaudeManagedAccount(email: "b@example.com"))
    }

    @Test
    func expired_backup_is_refreshed_before_the_credential_write() async throws {
        let (active, target) = Self.accounts()
        let harness = ServiceHarness(
            accounts: [active, target],
            backupsByID: [target.id: Fixtures.backup(email: "b@example.com", token: "stale-tok", expiresAtMs: 1)],
            current: Fixtures.credentials(email: "a@example.com", token: "tok-a"),
            refreshResult: .success(Self.freshTokens))

        try await harness.service.switchTo(accountID: target.id)

        #expect(harness.refreshedTokens.events == ["r"])
        #expect(harness.validatedTokens.events == ["fresh-token"])
        #expect(harness.credentials.current?.credentialsBlob.contains("fresh-token") == true)
        let storedBackup = try #require(harness.backups.load(accountID: target.id))
        #expect(storedBackup.credentialsBlob.contains("fresh-token"))
        #expect(storedBackup.credentialsBlob.contains("fresh-refresh"))
        let set = try harness.store.load()
        #expect(set.activeAccount?.id == target.id)
    }

    @Test
    func first_try_401_refreshes_once_and_retries() async throws {
        let (active, target) = Self.accounts()
        let harness = ServiceHarness(
            accounts: [active, target],
            backupsByID: [target.id: Fixtures.backup(email: "b@example.com", token: "tok-b")],
            current: Fixtures.credentials(email: "a@example.com", token: "tok-a"),
            validationOutcomes: [.unauthorized, nil],
            refreshResult: .success(Self.freshTokens))

        try await harness.service.switchTo(accountID: target.id)

        #expect(harness.validatedTokens.events == ["tok-b", "fresh-token"])
        #expect(harness.refreshedTokens.events == ["r"])
        #expect(harness.log.events.count(where: { $0 == "write:b@example.com" }) == 2)
        let set = try harness.store.load()
        #expect(set.activeAccount?.id == target.id)
    }

    @Test
    func rejected_refresh_of_an_expired_backup_aborts_before_credentials_are_touched() async throws {
        let (active, target) = Self.accounts()
        let harness = ServiceHarness(
            accounts: [active, target],
            backupsByID: [target.id: Fixtures.backup(email: "b@example.com", token: "stale-tok", expiresAtMs: 1)],
            current: Fixtures.credentials(email: "a@example.com", token: "tok-a"),
            refreshResult: .failure(.rejected(status: 400, detail: "invalid_grant")))

        do {
            try await harness.service.switchTo(accountID: target.id)
            Issue.record("expected switchValidateFailed")
        } catch let error as ClaudeAccountServiceError {
            guard case .switchValidateFailed = error else {
                Issue.record("expected switchValidateFailed, got \(error)")
                return
            }
        }
        #expect(!harness.log.events.contains { $0.hasPrefix("write") })
        let set = try harness.store.load()
        #expect(set.activeAccount?.id == active.id)
    }

    @Test
    func unreachable_refresh_of_an_expired_backup_still_switches_with_the_stale_token() async throws {
        let (active, target) = Self.accounts()
        let harness = ServiceHarness(
            accounts: [active, target],
            backupsByID: [target.id: Fixtures.backup(email: "b@example.com", token: "stale-tok", expiresAtMs: 1)],
            current: Fixtures.credentials(email: "a@example.com", token: "tok-a"))

        try await harness.service.switchTo(accountID: target.id)

        #expect(harness.log.events.contains("write:b@example.com"))
        let set = try harness.store.load()
        #expect(set.activeAccount?.id == target.id)
    }
}

// MARK: - Advisory validation (REQ-002 / design v1.6)

struct ClaudeAccountServiceAdvisoryValidationTests {
    private static func accounts() -> (active: ClaudeManagedAccount, target: ClaudeManagedAccount) {
        (
            ClaudeManagedAccount(email: "a@example.com", isActive: true),
            ClaudeManagedAccount(email: "b@example.com"))
    }

    @Test
    func rate_limited_usage_does_not_block_the_switch() async throws {
        let (active, target) = Self.accounts()
        let harness = ServiceHarness(
            accounts: [active, target],
            backupsByID: [target.id: Fixtures.backup(email: "b@example.com", token: "tok-b")],
            current: Fixtures.credentials(email: "a@example.com", token: "tok-a"),
            validationError: .rateLimited(retryAfter: nil))

        try await harness.service.switchTo(accountID: target.id)

        #expect(harness.refreshedTokens.events.isEmpty)
        #expect(harness.credentials.current?.emailAddress == "b@example.com")
        #expect(harness.seededBlobs.events.count == 1)
        let set = try harness.store.load()
        #expect(set.activeAccount?.id == target.id)
    }

    @Test
    func network_failure_during_validation_does_not_block_the_switch() async throws {
        let (active, target) = Self.accounts()
        let harness = ServiceHarness(
            accounts: [active, target],
            backupsByID: [target.id: Fixtures.backup(email: "b@example.com", token: "tok-b")],
            current: Fixtures.credentials(email: "a@example.com", token: "tok-a"),
            validationError: .networkError(URLError(.notConnectedToInternet)))

        try await harness.service.switchTo(accountID: target.id)

        let set = try harness.store.load()
        #expect(set.activeAccount?.id == target.id)
    }

    @Test
    func server_error_during_validation_does_not_block_the_switch() async throws {
        let (active, target) = Self.accounts()
        let harness = ServiceHarness(
            accounts: [active, target],
            backupsByID: [target.id: Fixtures.backup(email: "b@example.com", token: "tok-b")],
            current: Fixtures.credentials(email: "a@example.com", token: "tok-a"),
            validationError: .serverError(403, nil))

        try await harness.service.switchTo(accountID: target.id)

        let set = try harness.store.load()
        #expect(set.activeAccount?.id == target.id)
    }
}

// MARK: - Import (REQ-005)

struct ClaudeAccountServiceImportTests {
    private static func record(
        id: UUID,
        email: String,
        node: String?,
        provider: String = "Claude Code") -> CCSwitcherAccountRecord
    {
        CCSwitcherAccountRecord(
            id: id,
            email: email,
            displayName: "\(email) display",
            provider: provider,
            subscriptionType: "max",
            customLabel: "Label-\(email)",
            clashProxyName: node,
            clashProxyGroupName: node != nil ? "GLOBAL" : nil,
            isActive: false,
            lastUsed: Date(timeIntervalSinceReferenceDate: 805_960_070))
    }

    @Test
    func import_maps_fields_reuses_ids_and_re_derives_the_active_flag() async throws {
        let idA = UUID()
        let idB = UUID()
        let source = FakeImportSource(
            accounts: [
                Self.record(id: idA, email: "a@example.com", node: "NodeA"),
                Self.record(id: idB, email: "b@example.com", node: nil),
                Self.record(id: UUID(), email: "g@example.com", node: nil, provider: "Gemini"),
            ],
            backups: [
                idA.uuidString.uppercased(): CCSwitcherBackupRecord(
                    token: Fixtures.blob(token: "tok-a"),
                    oauthAccountJSON: Fixtures.oauthAccountJSON(email: "a@example.com")),
            ])
        let harness = ServiceHarness(
            accounts: [],
            backupsByID: [:],
            current: Fixtures.credentials(email: "b@example.com", token: "live"),
            importSource: source)

        let summary = try await harness.service.importFromCCSwitcher()
        #expect(summary == CCSwitcherImportSummary(
            imported: 2, skipped: 0, missingBackup: 1, keychainDenied: false))

        let set = try harness.store.load()
        #expect(set.accounts.count == 2)
        let accountA = try #require(set.account(id: idA))
        #expect(accountA.email == "a@example.com")
        #expect(accountA.customLabel == "Label-a@example.com")
        #expect(accountA.clashGroup == "GLOBAL")
        #expect(accountA.clashNode == "NodeA")
        #expect(accountA.lastUsed == Date(timeIntervalSinceReferenceDate: 805_960_070))
        #expect(!accountA.isActive)
        #expect(set.activeAccount?.id == idB)
        #expect(harness.backups.load(accountID: idA) != nil)
        #expect(harness.backups.load(accountID: idB) == nil)
    }

    @Test
    func re_import_is_idempotent_by_email() async throws {
        let idA = UUID()
        let source = FakeImportSource(
            accounts: [Self.record(id: idA, email: "a@example.com", node: "NodeA")],
            backups: [:])
        let harness = ServiceHarness(
            accounts: [],
            backupsByID: [:],
            current: Fixtures.credentials(email: "a@example.com", token: "live"),
            importSource: source)

        _ = try await harness.service.importFromCCSwitcher()
        let second = try await harness.service.importFromCCSwitcher()
        #expect(second.imported == 0)
        #expect(second.skipped == 1)
        let set = try harness.store.load()
        #expect(set.accounts.count == 1)
    }

    @Test
    func import_with_only_non_claude_records_reports_a_missing_source() async {
        let source = FakeImportSource(
            accounts: [Self.record(id: UUID(), email: "g@example.com", node: nil, provider: "Gemini")],
            backups: [:])
        let harness = ServiceHarness(
            accounts: [],
            backupsByID: [:],
            current: nil,
            importSource: source)

        await #expect(throws: ClaudeAccountServiceError.importSourceMissing) {
            _ = try await harness.service.importFromCCSwitcher()
        }
    }

    @Test
    func denied_keychain_still_imports_metadata_and_flags_the_denial() async throws {
        let idA = UUID()
        var source = FakeImportSource(
            accounts: [Self.record(id: idA, email: "a@example.com", node: "NodeA")],
            backups: [:])
        source.backupsDenied = true
        let harness = ServiceHarness(
            accounts: [],
            backupsByID: [:],
            current: nil,
            importSource: source)

        let summary = try await harness.service.importFromCCSwitcher()
        #expect(summary.keychainDenied)
        #expect(summary.imported == 1)
        #expect(summary.missingBackup == 1)
        #expect(harness.backups.load(accountID: idA) == nil)
    }
}
