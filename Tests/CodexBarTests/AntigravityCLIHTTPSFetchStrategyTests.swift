import Foundation
import Testing
@testable import CodexBarCore

private func antigravityBlockingSleep(_ interval: TimeInterval) {
    Thread.sleep(forTimeInterval: interval)
}

private final class AntigravityCLICounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    @discardableResult
    func increment() -> Int {
        self.lock.lock()
        self.count += 1
        let value = self.count
        self.lock.unlock()
        return value
    }

    var value: Int {
        self.lock.lock()
        let value = self.count
        self.lock.unlock()
        return value
    }
}

private final class AntigravityCLIPortRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var ports: [[Int]] = []

    func append(_ value: [Int]) {
        self.lock.lock()
        self.ports.append(value)
        self.lock.unlock()
    }

    func snapshot() -> [[Int]] {
        self.lock.lock()
        let value = self.ports
        self.lock.unlock()
        return value
    }
}

private final class AntigravityCLITimeoutRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var timeouts: [TimeInterval] = []

    func append(_ value: TimeInterval) {
        self.lock.lock()
        self.timeouts.append(value)
        self.lock.unlock()
    }

    func snapshot() -> [TimeInterval] {
        self.lock.lock()
        let value = self.timeouts
        self.lock.unlock()
        return value
    }
}

private final class AntigravityCLITestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(date: Date) {
        self.date = date
    }

    func now() -> Date {
        self.lock.lock()
        let value = self.date
        self.date = self.date.addingTimeInterval(1)
        self.lock.unlock()
        return value
    }
}

private final class AntigravityCLIOutputSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Data]

    init(_ values: [Data]) {
        self.values = values
    }

    func next() -> Data {
        self.lock.lock()
        let value = self.values.isEmpty ? Data() : self.values.removeFirst()
        self.lock.unlock()
        return value
    }
}

struct AntigravityCLIHTTPSFetchStrategyTests {
    @Test
    func local_strategy_falls_back_to_cli_HTTPS_in_cli_source_mode() {
        let strategy = AntigravityStatusFetchStrategy()
        let context = self.makeFetchContext(sourceMode: .cli)

        #expect(strategy.shouldFallback(on: AntigravityStatusProbeError.notRunning, context: context))
    }

    @Test
    func local_strategy_falls_back_to_cli_HTTPS_in_auto_source_mode() {
        let strategy = AntigravityStatusFetchStrategy()
        let context = self.makeFetchContext(sourceMode: .auto)

        #expect(strategy.shouldFallback(on: AntigravityStatusProbeError.notRunning, context: context))
    }

    @Test
    func local_strategy_does_not_fallback_for_unrelated_source_modes() {
        let strategy = AntigravityStatusFetchStrategy()

        #expect(!strategy.shouldFallback(
            on: AntigravityStatusProbeError.notRunning,
            context: self.makeFetchContext(sourceMode: .oauth)))
        #expect(!strategy.shouldFallback(
            on: AntigravityStatusProbeError.notRunning,
            context: self.makeFetchContext(sourceMode: .web)))
        #expect(!strategy.shouldFallback(
            on: AntigravityStatusProbeError.notRunning,
            context: self.makeFetchContext(sourceMode: .api)))
    }

    @Test
    func strategy_pipeline_includes_cli_HTTPS_fallback_in_cli_and_auto_modes() async {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .antigravity)

        let cliStrategies = await descriptor.fetchPlan.pipeline.resolveStrategies(
            self.makeFetchContext(sourceMode: .cli))
        #expect(cliStrategies.map(\.id) == [
            "antigravity.app-local",
            "antigravity.cli-https",
            "antigravity.ide-local",
        ])

        let autoStrategies = await descriptor.fetchPlan.pipeline.resolveStrategies(
            self.makeFetchContext(sourceMode: .auto))
        #expect(autoStrategies.map(\.id) == [
            "antigravity.app-local",
            "antigravity.cli-https",
            "antigravity.ide-local",
        ])
    }

    @Test
    func strategy_pipeline_keeps_source_mode_authoritative_with_selected_token_account() async {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .antigravity)

        let accountID = UUID()
        let autoStrategies = await descriptor.fetchPlan.pipeline.resolveStrategies(
            self.makeFetchContext(sourceMode: .auto, selectedTokenAccountID: accountID))
        let cliStrategies = await descriptor.fetchPlan.pipeline.resolveStrategies(
            self.makeFetchContext(sourceMode: .cli, selectedTokenAccountID: accountID))
        let oauthStrategies = await descriptor.fetchPlan.pipeline.resolveStrategies(
            self.makeFetchContext(sourceMode: .oauth, selectedTokenAccountID: accountID))

        #expect(autoStrategies.map(\.id) == [
            "antigravity.app-local",
            "antigravity.cli-https",
            "antigravity.ide-local",
            "antigravity.oauth",
        ])
        #expect(cliStrategies.map(\.id) == [
            "antigravity.app-local",
            "antigravity.cli-https",
            "antigravity.ide-local",
        ])
        #expect(oauthStrategies.map(\.id) == ["antigravity.oauth"])
    }

    @Test
    func auto_strategy_pipeline_includes_oauth_when_credentials_are_injected() async {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .antigravity)

        let autoStrategies = await descriptor.fetchPlan.pipeline.resolveStrategies(
            self.makeFetchContext(
                sourceMode: .auto,
                env: self.accountEnv(email: "selected@example.com")))

        #expect(autoStrategies.map(\.id) == [
            "antigravity.app-local",
            "antigravity.cli-https",
            "antigravity.ide-local",
            "antigravity.oauth",
        ])
    }

    @Test
    func auto_strategy_pipeline_preserves_oauth_fallback_for_shared_credentials_file() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("antigravity-shared-auto-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AntigravityOAuthCredentialsStore(
            fileURL: AntigravityOAuthCredentialsStore.defaultURL(home: root))
        try store.save(AntigravityOAuthCredentials(
            accessToken: "access",
            refreshToken: "refresh",
            expiryDate: Date().addingTimeInterval(3600),
            email: "legacy@example.com"))

        let descriptor = ProviderDescriptorRegistry.descriptor(for: .antigravity)
        let autoStrategies = await descriptor.fetchPlan.pipeline.resolveStrategies(
            self.makeFetchContext(sourceMode: .auto, env: ["HOME": root.path]))

        #expect(autoStrategies.map(\.id) == [
            "antigravity.app-local",
            "antigravity.cli-https",
            "antigravity.ide-local",
            "antigravity.oauth",
        ])
    }

    // MARK: - Selected-account guard

    @Test
    func account_guard_ignores_fetches_without_a_selected_account() throws {
        let usage = self.makeUsage(accountEmail: "ambient@example.com")
        let context = self.makeFetchContext(
            sourceMode: .auto,
            env: self.accountEnv(email: "selected@example.com"))

        try AntigravitySelectedAccountGuard.validate(usage, context: context)
    }

    @Test
    func account_guard_accepts_matching_ambient_snapshot_in_auto_mode() throws {
        let usage = self.makeUsage(accountEmail: "Selected@Example.com")
        let context = self.makeFetchContext(
            sourceMode: .auto,
            selectedTokenAccountID: UUID(),
            env: self.accountEnv(email: "selected@example.com"))

        try AntigravitySelectedAccountGuard.validate(usage, context: context)
    }

    @Test
    func account_guard_rejects_mismatched_ambient_snapshot_in_auto_mode() {
        let usage = self.makeUsage(accountEmail: "ambient@example.com")
        let context = self.makeFetchContext(
            sourceMode: .auto,
            selectedTokenAccountID: UUID(),
            env: self.accountEnv(email: "selected@example.com"))

        #expect(throws: AntigravityStatusProbeError.accountMismatch(
            expected: "selected@example.com",
            found: "ambient@example.com"))
        {
            try AntigravitySelectedAccountGuard.validate(usage, context: context)
        }
    }

    @Test
    func account_guard_rejects_snapshot_without_an_identity_email() {
        let usage = self.makeUsage(accountEmail: nil)
        let context = self.makeFetchContext(
            sourceMode: .auto,
            selectedTokenAccountID: UUID(),
            env: self.accountEnv(email: "selected@example.com"))

        #expect(throws: AntigravityStatusProbeError.accountMismatch(
            expected: "selected@example.com",
            found: nil))
        {
            try AntigravitySelectedAccountGuard.validate(usage, context: context)
        }
    }

    @Test
    func account_guard_rejects_when_selected_account_email_cannot_be_resolved() {
        let usage = self.makeUsage(accountEmail: "ambient@example.com")
        let context = self.makeFetchContext(
            sourceMode: .auto,
            selectedTokenAccountID: UUID())

        #expect(throws: AntigravityStatusProbeError.accountMismatch(
            expected: nil,
            found: "ambient@example.com"))
        {
            try AntigravitySelectedAccountGuard.validate(usage, context: context)
        }
    }

    @Test
    func account_guard_leaves_explicit_cli_source_mode_authoritative() throws {
        let usage = self.makeUsage(accountEmail: "ambient@example.com")
        let context = self.makeFetchContext(
            sourceMode: .cli,
            selectedTokenAccountID: UUID(),
            env: self.accountEnv(email: "selected@example.com"))

        try AntigravitySelectedAccountGuard.validate(usage, context: context)
    }

    @Test
    func selected_account_email_resolves_from_id_token_when_email_field_missing() {
        let idToken = Self.makeIDToken(email: "jwt@example.com")
        let context = self.makeFetchContext(
            sourceMode: .auto,
            selectedTokenAccountID: UUID(),
            env: self.accountEnv(email: nil, idToken: idToken))

        #expect(AntigravitySelectedAccountGuard.selectedAccountEmail(context: context) == "jwt@example.com")
    }

    @Test
    func selected_account_email_prefers_id_token_over_stored_email_field() {
        let idToken = Self.makeIDToken(email: "jwt@example.com")
        let context = self.makeFetchContext(
            sourceMode: .auto,
            selectedTokenAccountID: UUID(),
            env: self.accountEnv(email: "stored@example.com", idToken: idToken))

        #expect(AntigravitySelectedAccountGuard.selectedAccountEmail(context: context) == "jwt@example.com")
    }

    @Test
    func cli_HTTPS_resets_session_only_for_one_shot_CLI_runtime() {
        // One-shot CLI invocation: reset after fetch.
        #expect(AntigravityCLIHTTPSFetchStrategy.shouldResetSessionAfterFetch(self.makeFetchContext(runtime: .cli)))
        // App runtime keeps the warm session.
        #expect(!AntigravityCLIHTTPSFetchStrategy.shouldResetSessionAfterFetch(self.makeFetchContext(runtime: .app)))
        // Long-lived CLI host (codexbar serve) keeps the warm session even at .cli runtime.
        #expect(!AntigravityCLIHTTPSFetchStrategy.shouldResetSessionAfterFetch(
            self.makeFetchContext(runtime: .cli, persistsCLISessions: true)))
    }

    @Test
    func cli_HTTPS_reports_public_source_as_cli() {
        #expect(AntigravityCLIHTTPSFetchStrategy.sourceLabel == "cli")
    }

    @Test
    func cli_local_strategy_availability_requires_binary() async throws {
        let binaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-antigravity-\(UUID().uuidString)")
        try Data("#!/bin/sh\n".utf8).write(to: binaryURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: binaryURL.path)
        defer { try? FileManager.default.removeItem(at: binaryURL) }

        let strategy = AntigravityCLIHTTPSFetchStrategy()
        let context = self.makeFetchContext(env: ["ANTIGRAVITY_CLI_PATH": binaryURL.path])
        let isAvailable = await strategy.isAvailable(context)

        #expect(isAvailable)
    }

    @Test
    func cli_local_endpoints_remain_HTTPS_only_on_macOS() {
        #expect(
            AntigravityStatusProbe.cliEndpoints(ports: [55624]) == [
                AntigravityStatusProbe.AntigravityConnectionEndpoint(
                    scheme: "https",
                    port: 55624,
                    csrfToken: "",
                    source: .cliHTTPS),
            ])
    }

    @Test
    func cli_HTTPS_falls_back_to_command_model_configs_when_quota_summary_and_user_status_fail() async throws {
        let endpoints = [
            AntigravityStatusProbe.AntigravityConnectionEndpoint(
                scheme: "https",
                port: 50080,
                csrfToken: "",
                source: .cliHTTPS),
        ]
        let attempts = AntigravityCLICounter()

        let snapshot = try await AntigravityStatusProbe.fetchSnapshot(
            context: AntigravityStatusProbe.RequestContext(
                endpoints: endpoints,
                timeout: 1,
                deadline: Date().addingTimeInterval(2)),
            send: { payload, _, _ in
                let attempt = attempts.increment()
                if attempt == 1 {
                    #expect(payload.path == "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary")
                    throw AntigravityStatusProbeError.apiError("quota summary unavailable")
                }
                if attempt == 2 {
                    #expect(payload.path == "/exa.language_server_pb.LanguageServerService/GetUserStatus")
                    throw AntigravityStatusProbeError.apiError("user status unavailable")
                }
                #expect(payload.path == "/exa.language_server_pb.LanguageServerService/GetCommandModelConfigs")
                return Data("""
                {
                  "clientModelConfigs": [
                    {
                      "label": "Claude Sonnet",
                      "modelOrAlias": { "model": "claude-sonnet" },
                      "quotaInfo": { "remainingFraction": 0.5 }
                    }
                  ]
                }
                """.utf8)
            })

        #expect(snapshot.modelQuotas.first?.label == "Claude Sonnet")
        #expect(attempts.value == 3)
    }

    @Test
    func cli_HTTPS_waits_for_user_status_after_ports_appear() async throws {
        let fetchAttempts = AntigravityCLICounter()
        let drainAttempts = AntigravityCLICounter()
        let fetchedPorts = AntigravityCLIPortRecorder()
        let snapshot = try await AntigravityCLIHTTPSFetchStrategy.waitForSnapshot(
            pid: 123,
            deadline: Date().addingTimeInterval(5),
            dependencies: AntigravityCLIHTTPSFetchStrategy.SnapshotWaitDependencies(
                pollIntervalNanoseconds: 0,
                listeningPorts: { _, _ in [50080, 50081] },
                drainOutput: {
                    drainAttempts.increment()
                    return Data()
                },
                fetchSnapshot: { ports in
                    fetchedPorts.append(ports)
                    if fetchAttempts.increment() == 1 {
                        throw AntigravityStatusProbeError.apiError("HTTP 500: GetCascadeModelConfigData() is nil")
                    }
                    return AntigravityStatusSnapshot(
                        modelQuotas: [
                            AntigravityModelQuota(
                                label: "Claude Opus 4.6 (Thinking)",
                                modelId: "claude-opus-4.6-thinking",
                                remainingFraction: 1,
                                resetTime: nil,
                                resetDescription: nil),
                        ],
                        accountEmail: "user@example.com",
                        accountPlan: "Pro",
                        source: .local)
                }))

        #expect(snapshot.accountEmail == "user@example.com")
        #expect(fetchAttempts.value == 2)
        #expect(fetchedPorts.snapshot() == [[50080, 50081], [50080, 50081]])
        #expect(drainAttempts.value == 4)
    }

    @Test
    func cli_HTTPS_retries_empty_quota_snapshots_until_usage_is_parseable() async throws {
        let fetchAttempts = AntigravityCLICounter()

        let snapshot = try await AntigravityCLIHTTPSFetchStrategy.waitForSnapshot(
            pid: 123,
            deadline: Date().addingTimeInterval(5),
            dependencies: AntigravityCLIHTTPSFetchStrategy.SnapshotWaitDependencies(
                pollIntervalNanoseconds: 0,
                listeningPorts: { _, _ in [50080] },
                drainOutput: { Data() },
                fetchSnapshot: { _ in
                    if fetchAttempts.increment() == 1 {
                        return AntigravityStatusSnapshot(
                            modelQuotas: [],
                            accountEmail: nil,
                            accountPlan: nil,
                            source: .local)
                    }
                    return AntigravityStatusSnapshot(
                        modelQuotas: [
                            AntigravityModelQuota(
                                label: "Claude Sonnet",
                                modelId: "claude-sonnet",
                                remainingFraction: 0.5,
                                resetTime: nil,
                                resetDescription: nil),
                        ],
                        accountEmail: "user@example.com",
                        accountPlan: "Pro",
                        source: .local)
                }))

        #expect(fetchAttempts.value == 2)
        #expect(snapshot.modelQuotas.first?.modelId == "claude-sonnet")
    }

    @Test
    func cli_HTTPS_drains_output_before_ports_appear() async throws {
        let portPolls = AntigravityCLICounter()
        let drainAttempts = AntigravityCLICounter()
        let snapshot = try await AntigravityCLIHTTPSFetchStrategy.waitForSnapshot(
            pid: 123,
            deadline: Date().addingTimeInterval(5),
            dependencies: AntigravityCLIHTTPSFetchStrategy.SnapshotWaitDependencies(
                pollIntervalNanoseconds: 0,
                listeningPorts: { _, _ in
                    portPolls.increment() == 1 ? [] : [50080]
                },
                drainOutput: {
                    drainAttempts.increment()
                    return Data()
                },
                fetchSnapshot: { _ in
                    AntigravityStatusSnapshot(
                        modelQuotas: [
                            AntigravityModelQuota(
                                label: "Claude Sonnet",
                                modelId: "claude-sonnet",
                                remainingFraction: 1,
                                resetTime: nil,
                                resetDescription: nil),
                        ],
                        accountEmail: "user@example.com",
                        accountPlan: "Pro",
                        source: .local)
                }))

        #expect(snapshot.accountEmail == "user@example.com")
        #expect(portPolls.value == 2)
        #expect(drainAttempts.value == 3)
    }

    @Test
    func cli_HTTPS_stops_before_probing_when_signed_out_prompt_spans_output_chunks() async {
        let output = AntigravityCLIOutputSequence([
            Data("Welcome. You are currently ".utf8),
            Data("Welcome. You are currently not signed in.\nSelect login method:".utf8),
        ])
        let portPolls = AntigravityCLICounter()

        do {
            _ = try await AntigravityCLIHTTPSFetchStrategy.waitForSnapshot(
                pid: 123,
                deadline: Date().addingTimeInterval(2),
                dependencies: AntigravityCLIHTTPSFetchStrategy.SnapshotWaitDependencies(
                    pollIntervalNanoseconds: 0,
                    listeningPorts: { _, _ in
                        portPolls.increment()
                        return []
                    },
                    drainOutput: {
                        output.next()
                    },
                    fetchSnapshot: { _ in
                        Issue.record("Signed-out helper should not fetch a snapshot")
                        return AntigravityStatusSnapshot(
                            modelQuotas: [],
                            accountEmail: nil,
                            accountPlan: nil,
                            source: .local)
                    }))
            Issue.record("Expected authentication failure")
        } catch AntigravityStatusProbeError.authenticationRequired {
            #expect(portPolls.value == 1)
        } catch {
            Issue.record("Expected authenticationRequired, got \(error)")
        }
    }

    @Test
    func cli_HTTPS_allows_transient_automatic_sign_in_banner() async throws {
        let output = AntigravityCLIOutputSequence([
            Data("Welcome. You are currently not signed in.\nSigning in...".utf8),
            Data("user@example.com\nGemini 3.1 Pro (High)".utf8),
        ])

        let snapshot = try await AntigravityCLIHTTPSFetchStrategy.waitForSnapshot(
            pid: 123,
            deadline: Date().addingTimeInterval(2),
            dependencies: AntigravityCLIHTTPSFetchStrategy.SnapshotWaitDependencies(
                pollIntervalNanoseconds: 0,
                listeningPorts: { _, _ in [50080] },
                drainOutput: {
                    output.next()
                },
                fetchSnapshot: { _ in
                    AntigravityStatusSnapshot(
                        modelQuotas: [
                            AntigravityModelQuota(
                                label: "Claude Sonnet",
                                modelId: "claude-sonnet",
                                remainingFraction: 1,
                                resetTime: nil,
                                resetDescription: nil),
                        ],
                        accountEmail: "user@example.com",
                        accountPlan: "Pro",
                        source: .local)
                }))

        #expect(snapshot.accountEmail == "user@example.com")
    }

    @Test
    func cli_HTTPS_rechecks_signed_out_prompt_after_snapshot_readiness() async {
        let output = AntigravityCLIOutputSequence([
            Data(),
            Data("You are currently not signed in.\nSelect login method:".utf8),
        ])

        do {
            _ = try await AntigravityCLIHTTPSFetchStrategy.waitForSnapshot(
                pid: 123,
                deadline: Date().addingTimeInterval(2),
                dependencies: AntigravityCLIHTTPSFetchStrategy.SnapshotWaitDependencies(
                    pollIntervalNanoseconds: 0,
                    listeningPorts: { _, _ in [50080] },
                    drainOutput: {
                        output.next()
                    },
                    fetchSnapshot: { _ in
                        AntigravityStatusSnapshot(
                            modelQuotas: [
                                AntigravityModelQuota(
                                    label: "Claude Sonnet",
                                    modelId: "claude-sonnet",
                                    remainingFraction: 1,
                                    resetTime: nil,
                                    resetDescription: nil),
                            ],
                            accountEmail: "user@example.com",
                            accountPlan: "Pro",
                            source: .local)
                    }))
            Issue.record("Expected authentication failure")
        } catch AntigravityStatusProbeError.authenticationRequired {
            // Expected: the late prompt wins over the apparently ready API.
        } catch {
            Issue.record("Expected authenticationRequired, got \(error)")
        }
    }

    @Test
    func cli_HTTPS_treats_empty_lsof_exit_as_ports_not_ready() async throws {
        let portPolls = AntigravityCLICounter()
        let snapshot = try await AntigravityCLIHTTPSFetchStrategy.waitForSnapshot(
            pid: 123,
            deadline: Date().addingTimeInterval(5),
            dependencies: AntigravityCLIHTTPSFetchStrategy.SnapshotWaitDependencies(
                pollIntervalNanoseconds: 0,
                listeningPorts: { _, _ in
                    if portPolls.increment() == 1 {
                        throw SubprocessRunnerError.nonZeroExit(code: 1, stderr: "")
                    }
                    return [50080]
                },
                drainOutput: { Data() },
                fetchSnapshot: { _ in
                    AntigravityStatusSnapshot(
                        modelQuotas: [
                            AntigravityModelQuota(
                                label: "Claude Sonnet",
                                modelId: "claude-sonnet",
                                remainingFraction: 0.5,
                                resetTime: nil,
                                resetDescription: nil),
                        ],
                        accountEmail: "user@example.com",
                        accountPlan: "Pro",
                        source: .local)
                }))

        #expect(snapshot.accountEmail == "user@example.com")
        #expect(portPolls.value == 2)
    }

    @Test
    func parsed_requests_recompute_timeout_from_shared_deadline_between_endpoints() async throws {
        let timeoutRecorder = AntigravityCLITimeoutRecorder()
        let attempts = AntigravityCLICounter()
        let endpoints = [
            AntigravityStatusProbe.AntigravityConnectionEndpoint(
                scheme: "https",
                port: 50080,
                csrfToken: "",
                source: .cliHTTPS),
            AntigravityStatusProbe.AntigravityConnectionEndpoint(
                scheme: "https",
                port: 50081,
                csrfToken: "",
                source: .cliHTTPS),
        ]

        let result = try await AntigravityStatusProbe.makeParsedRequest(
            payload: AntigravityStatusProbe.RequestPayload(path: "/status", body: [:]),
            context: AntigravityStatusProbe.RequestContext(
                endpoints: endpoints,
                timeout: 10,
                deadline: Date().addingTimeInterval(10)),
            send: { _, _, timeout in
                timeoutRecorder.append(timeout)
                if attempts.increment() == 1 {
                    antigravityBlockingSleep(0.1)
                    throw AntigravityStatusProbeError.apiError("first endpoint failed")
                }
                return Data("ok".utf8)
            },
            parse: { data in
                guard let value = String(bytes: data, encoding: .utf8) else {
                    throw AntigravityStatusProbeError.apiError("invalid test data")
                }
                return value
            })

        let timeouts = timeoutRecorder.snapshot()
        #expect(result == "ok")
        #expect(timeouts.count == 2)
        #expect(timeouts.allSatisfy { $0 <= 10 })
        #expect((timeouts.last ?? 10) < (timeouts.first ?? 0))
    }

    @Test
    func parsed_request_reports_timeout_when_shared_deadline_is_already_expired() async {
        do {
            _ = try await AntigravityStatusProbe.makeParsedRequest(
                payload: AntigravityStatusProbe.RequestPayload(path: "/status", body: [:]),
                context: AntigravityStatusProbe.RequestContext(
                    endpoints: [
                        AntigravityStatusProbe.AntigravityConnectionEndpoint(
                            scheme: "https",
                            port: 50080,
                            csrfToken: "",
                            source: .cliHTTPS),
                    ],
                    timeout: 10,
                    deadline: Date().addingTimeInterval(-1)),
                send: { _, _, _ in
                    Issue.record("Expired deadline should not send a request")
                    return Data()
                },
                parse: { _ in "ok" })
            Issue.record("Expected timeout")
        } catch AntigravityStatusProbeError.timedOut {
        } catch {
            Issue.record("Expected timedOut, got \(error)")
        }
    }

    @Test
    func cli_HTTPS_reports_last_readiness_error_when_ports_never_become_usable() async {
        let fetchAttempts = AntigravityCLICounter()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let clock = AntigravityCLITestClock(date: start)

        do {
            _ = try await AntigravityCLIHTTPSFetchStrategy.waitForSnapshot(
                pid: 123,
                deadline: start.addingTimeInterval(5),
                dependencies: AntigravityCLIHTTPSFetchStrategy.SnapshotWaitDependencies(
                    pollIntervalNanoseconds: 0,
                    listeningPorts: { _, _ in [50080] },
                    drainOutput: { Data() },
                    fetchSnapshot: { _ in
                        let attempt = fetchAttempts.increment()
                        throw AntigravityStatusProbeError.apiError("HTTP 500: warming attempt \(attempt)")
                    },
                    now: { clock.now() }))
            Issue.record("Expected readiness polling to throw")
        } catch let AntigravityStatusProbeError.apiError(message) {
            #expect(fetchAttempts.value == 2)
            #expect(message == "HTTP 500: warming attempt 2")
        } catch {
            Issue.record("Expected apiError, got \(error)")
        }
    }

    @Test
    func cli_HTTPS_preserves_non_transient_port_detection_errors() async {
        do {
            _ = try await AntigravityCLIHTTPSFetchStrategy.waitForSnapshot(
                pid: 123,
                deadline: Date().addingTimeInterval(2),
                dependencies: AntigravityCLIHTTPSFetchStrategy.SnapshotWaitDependencies(
                    pollIntervalNanoseconds: 0,
                    listeningPorts: { _, _ in
                        throw AntigravityStatusProbeError.portDetectionFailed("lsof not available")
                    },
                    drainOutput: { Data() },
                    fetchSnapshot: { _ in
                        Issue.record("Port detection failure should not fetch a snapshot")
                        return AntigravityStatusSnapshot(
                            modelQuotas: [],
                            accountEmail: nil,
                            accountPlan: nil,
                            source: .local)
                    }))
            Issue.record("Expected port detection failure")
        } catch let AntigravityStatusProbeError.portDetectionFailed(message) {
            #expect(message == "lsof not available")
        } catch {
            Issue.record("Expected portDetectionFailed, got \(error)")
        }
    }

    @Test
    func cli_HTTPS_endpoint_does_not_require_CSRF_token() {
        let endpoint = AntigravityStatusProbe.AntigravityConnectionEndpoint(
            scheme: "https",
            port: 55624,
            csrfToken: "ignored-by-cli",
            source: .cliHTTPS)
        #expect(!endpoint.requiresCSRFToken)
    }

    @Test
    func languageServer_endpoint_requires_CSRF_token() {
        let endpoint = AntigravityStatusProbe.AntigravityConnectionEndpoint(
            scheme: "https",
            port: 64440,
            csrfToken: "",
            source: .languageServer)
        #expect(endpoint.requiresCSRFToken)
    }

    @Test
    func extensionServer_endpoint_requires_CSRF_token() {
        let endpoint = AntigravityStatusProbe.AntigravityConnectionEndpoint(
            scheme: "http",
            port: 64432,
            csrfToken: "",
            source: .extensionServer)
        #expect(endpoint.requiresCSRFToken)
    }

    private func makeFetchContext(
        runtime: ProviderRuntime = .app,
        sourceMode: ProviderSourceMode = .auto,
        selectedTokenAccountID: UUID? = nil,
        persistsCLISessions: Bool = false,
        env: [String: String] = [:]) -> ProviderFetchContext
    {
        var effectiveEnv = env
        effectiveEnv["HOME"] = effectiveEnv["HOME"] ??
            FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-antigravity-empty-home-\(UUID().uuidString)", isDirectory: true)
            .path
        return ProviderFetchContext(
            runtime: runtime,
            sourceMode: sourceMode,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: effectiveEnv,
            settings: nil,
            fetcher: UsageFetcher(environment: effectiveEnv),
            claudeFetcher: StubClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            selectedTokenAccountID: selectedTokenAccountID,
            persistsCLISessions: persistsCLISessions)
    }

    private func makeUsage(accountEmail: String?) -> UsageSnapshot {
        UsageSnapshot(
            primary: nil,
            secondary: nil,
            updatedAt: Date(),
            identity: ProviderIdentitySnapshot(
                providerID: .antigravity,
                accountEmail: accountEmail,
                accountOrganization: nil,
                loginMethod: nil))
    }

    private func accountEnv(email: String?, idToken: String? = nil) -> [String: String] {
        let credentials = AntigravityOAuthCredentials(
            accessToken: "access",
            refreshToken: "refresh",
            expiryDate: Date().addingTimeInterval(3600),
            idToken: idToken,
            email: email)
        guard let value = try? AntigravityOAuthCredentialsStore.tokenAccountValue(for: credentials) else {
            return [:]
        }
        return [AntigravityOAuthCredentialsStore.environmentCredentialsKey: value]
    }

    private static func makeIDToken(email: String) -> String {
        let payload = Data("{\"email\":\"\(email)\"}".utf8)
        let encodedPayload = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encodedPayload).signature"
    }

    private struct StubClaudeFetcher: ClaudeUsageFetching {
        func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot {
            throw ClaudeUsageError.parseFailed("stub")
        }

        func debugRawProbe(model _: String) async -> String {
            "stub"
        }

        func detectVersion() -> String? {
            nil
        }
    }
}
