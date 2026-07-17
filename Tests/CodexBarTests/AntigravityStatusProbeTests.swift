import Foundation
import Testing
@testable import CodexBarCore

private final class AntigravityAttemptRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var endpoints: [AntigravityStatusProbe.AntigravityConnectionEndpoint] = []

    func append(_ endpoint: AntigravityStatusProbe.AntigravityConnectionEndpoint) {
        self.lock.lock()
        self.endpoints.append(endpoint)
        self.lock.unlock()
    }

    func snapshot() -> [AntigravityStatusProbe.AntigravityConnectionEndpoint] {
        self.lock.lock()
        let snapshot = self.endpoints
        self.lock.unlock()
        return snapshot
    }
}

struct AntigravityStatusProbeTests {
    @Test
    func process_detection_accepts_antigravity_2_unsuffixed_language_server() {
        let command = """
        /Applications/Antigravity.app/Contents/Resources/bin/language_server --standalone \
        --override_ide_name antigravity --override_ide_version 2.0.0 \
        --csrf_token token --app_data_dir antigravity
        """

        #expect(AntigravityStatusProbe.isAntigravityLanguageServerCommandLine(command))
    }

    @Test
    func process_detection_accepts_antigravity_language_server_paths_with_spaces() {
        let command = """
        /Applications/Google Antigravity.app/Contents/Resources/bin/language_server --standalone \
        --override_ide_name antigravity --csrf_token token --app_data_dir antigravity
        """

        #expect(AntigravityStatusProbe.isAntigravityLanguageServerCommandLine(command))
    }

    @Test
    func process_detection_accepts_hyphenated_language_server_from_app_bundle() throws {
        let command = """
        /Applications/Google Antigravity.app/Contents/Resources/bin/language-server --standalone \
        --csrf_token token --extension_server_port 64123
        """

        #expect(AntigravityStatusProbe.isAntigravityLanguageServerCommandLine(command))

        let result = try AntigravityStatusProbe.processInfo(fromProcessListOutput: "  321 \(command)")
        #expect(result.pid == 321)
        #expect(result.csrfToken == "token")
        #expect(result.extensionPort == 64123)
    }

    @Test
    func process_detection_keeps_ignoring_non_language_server_antigravity_helpers() {
        let helper = """
        /Applications/Antigravity.app/Contents/Frameworks/Antigravity Helper.app/Contents/MacOS/Antigravity Helper \
        --type=renderer --user-data-dir=/Users/test/Library/Application Support/Antigravity
        """

        #expect(!AntigravityStatusProbe.isAntigravityLanguageServerCommandLine(helper))
    }

    @Test
    func process_detection_still_accepts_legacy_antigravity_language_server() {
        let command = """
        /Applications/Antigravity.app/Contents/Resources/bin/language_server_macos \
        --csrf_token token --app_data_dir antigravity
        """

        #expect(AntigravityStatusProbe.isAntigravityLanguageServerCommandLine(command))
    }

    @Test
    func process_detection_accepts_platform_suffixed_antigravity_language_server() throws {
        let output = """
          101 /Applications/Antigravity.app/Contents/Resources/bin/language_server_macos_arm \
          --csrf_token ide-token --app_data_dir antigravity --extension_server_port 54977
        """

        let result = try AntigravityStatusProbe.processInfo(fromProcessListOutput: output, scope: .appOnly)

        #expect(result.pid == 101)
        #expect(result.csrfToken == "ide-token")
        #expect(result.extensionPort == 54977)
    }

    @Test
    func process_detection_accepts_antigravity_cli_without_csrf_token() {
        // The CLI launches its language server without a `--csrf_token` flag.
        let node = """
        node /Users/test/.gemini/antigravity-cli/build/mcp-server.cjs \
        --app_data_dir /Users/test/.gemini/antigravity
        """
        #expect(AntigravityStatusProbe.isAntigravityLanguageServerCommandLine(node))

        let agy = "/Users/test/.local/bin/agy -p hello"
        #expect(AntigravityStatusProbe.isAntigravityLanguageServerCommandLine(agy))

        let agyUnderscore = "/usr/local/bin/agy --app_data_dir /Users/test/.gemini/antigravity_cli"
        #expect(AntigravityStatusProbe.isAntigravityLanguageServerCommandLine(agyUnderscore))
    }

    @Test
    func process_detection_ignores_unrelated_binaries_containing_agy_substring() {
        // "agy" must be path-anchored so unrelated commands do not match.
        #expect(!AntigravityStatusProbe.isAntigravityLanguageServerCommandLine("/usr/bin/legacy --run"))
        #expect(!AntigravityStatusProbe.isAntigravityLanguageServerCommandLine("/opt/imagymagic/bin/tool"))
    }

    @Test
    func process_detection_ignores_cli_names_outside_explicit_cli_path_segments() {
        #expect(
            !AntigravityStatusProbe.isAntigravityLanguageServerCommandLine(
                "/usr/bin/node /tmp/not-antigravity-cli/build/server.js"))
        #expect(
            !AntigravityStatusProbe.isAntigravityLanguageServerCommandLine(
                "/usr/bin/helper --workspace antigravity-cli"))
    }

    @Test
    func process_kind_distinguishes_app_ide_language_server_and_cli() {
        let app = """
        /Applications/Antigravity.app/Contents/Resources/bin/language_server \
        --csrf_token token --app_data_dir antigravity
        """
        let ide = """
        /Applications/Antigravity IDE.app/Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm \
        --csrf_token token --app_data_dir antigravity-ide
        """
        #expect(AntigravityStatusProbe.antigravityProcessKind(app) == .app)
        #expect(AntigravityStatusProbe.antigravityProcessKind(ide) == .ide)
        #expect(AntigravityStatusProbe.antigravityProcessKind("/Users/test/.local/bin/agy -p hi") == .cli)
        #expect(
            AntigravityStatusProbe.antigravityProcessKind(
                "node /x/.gemini/antigravity-cli/build/mcp-server.cjs --app_data_dir /x/.gemini/antigravity") == .cli)
        #expect(AntigravityStatusProbe.antigravityProcessKind("/usr/bin/legacy --run") == nil)
    }

    @Test
    func csrf_token_stays_required_for_ide_but_optional_for_cli() {
        // Desktop app/IDE with a token returns it.
        let appWithToken = """
        /Applications/Antigravity.app/Contents/Resources/bin/language_server \
        --csrf_token ide-token --app_data_dir antigravity
        """
        #expect(AntigravityStatusProbe.resolvedCSRFToken(forKind: .app, command: appWithToken) == "ide-token")

        // Tokenless desktop app is skipped (nil) so detection keeps scanning for a valid
        // server and preserves the missing-token diagnostic - no empty-token probe.
        let appNoToken = """
        /Applications/Antigravity.app/Contents/Resources/bin/language_server \
        --app_data_dir antigravity
        """
        #expect(AntigravityStatusProbe.resolvedCSRFToken(forKind: .app, command: appNoToken) == nil)

        // CLI without a token resolves to an empty token (its server needs none).
        #expect(
            AntigravityStatusProbe.resolvedCSRFToken(
                forKind: .cli, command: "/Users/test/.local/bin/agy -p hi")?.isEmpty == true)

        // A CLI that does carry a token still uses it.
        #expect(
            AntigravityStatusProbe.resolvedCSRFToken(
                forKind: .cli, command: "/Users/test/.local/bin/agy --csrf_token cli-token") == "cli-token")
    }

    @Test
    func process_scan_skips_tokenless_ide_before_later_valid_ide() throws {
        let tokenlessIDE =
            "  100 /Applications/Antigravity.app/Contents/Resources/bin/language_server --app_data_dir antigravity"
        let validIDE = "  101 /Applications/Antigravity.app/Contents/Resources/bin/language_server " +
            "--csrf_token ide-token --app_data_dir antigravity " +
            "--extension_server_port 64432 --extension_server_csrf_token extension-token"
        let output = [tokenlessIDE, validIDE].joined(separator: "\n")

        let result = try AntigravityStatusProbe.processInfo(fromProcessListOutput: output)

        #expect(result.pid == 101)
        #expect(result.csrfToken == "ide-token")
        #expect(result.extensionPort == 64432)
        #expect(result.extensionServerCSRFToken == "extension-token")
    }

    @Test
    func process_scan_returns_all_valid_app_candidates() throws {
        let firstApp = "  101 /Applications/Antigravity.app/Contents/Resources/bin/language_server " +
            "--csrf_token first-token --app_data_dir antigravity"
        let secondApp = "  102 /Applications/Antigravity.app/Contents/Resources/bin/language_server " +
            "--csrf_token second-token --app_data_dir antigravity " +
            "--extension_server_port 64432 --extension_server_csrf_token extension-token"
        let output = [firstApp, secondApp].joined(separator: "\n")

        let results = try AntigravityStatusProbe.processInfos(fromProcessListOutput: output, scope: .appOnly)

        #expect(results.map(\.pid) == [101, 102])
        #expect(results.map(\.csrfToken) == ["first-token", "second-token"])
        #expect(results.last?.extensionPort == 64432)
        #expect(results.last?.extensionServerCSRFToken == "extension-token")
    }

    @Test
    func local_snapshot_score_prefers_quota_summary_over_legacy_model_quotas() {
        let legacy = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Gemini 3 Pro Low",
                    modelId: "gemini-3-pro-low",
                    remainingFraction: 0.9,
                    resetTime: Date(timeIntervalSince1970: 1_700_000_000),
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Claude Sonnet",
                    modelId: "claude-sonnet",
                    remainingFraction: 0.5,
                    resetTime: Date(timeIntervalSince1970: 1_700_000_000),
                    resetDescription: nil),
            ],
            accountEmail: "user@example.com",
            accountPlan: "Pro",
            source: .local)
        let summary = AntigravityStatusSnapshot(
            quotaSummary: AntigravityQuotaSummary(
                description: nil,
                groups: [
                    AntigravityQuotaSummaryGroup(
                        displayName: "Gemini Models",
                        description: nil,
                        buckets: [
                            AntigravityQuotaSummaryBucket(
                                bucketId: "gemini-5h",
                                displayName: "Five Hour Limit",
                                remainingFraction: 0.9,
                                resetDescription: nil,
                                disabled: false),
                            AntigravityQuotaSummaryBucket(
                                bucketId: "gemini-weekly",
                                displayName: "Weekly Limit",
                                remainingFraction: 0.8,
                                resetDescription: nil,
                                disabled: false),
                        ]),
                    AntigravityQuotaSummaryGroup(
                        displayName: "Claude and GPT models",
                        description: nil,
                        buckets: [
                            AntigravityQuotaSummaryBucket(
                                bucketId: "3p-5h",
                                displayName: "Five Hour Limit",
                                remainingFraction: 0.7,
                                resetDescription: nil,
                                disabled: false),
                            AntigravityQuotaSummaryBucket(
                                bucketId: "3p-weekly",
                                displayName: "Weekly Limit",
                                remainingFraction: 0.6,
                                resetDescription: nil,
                                disabled: false),
                        ]),
                ]),
            accountEmail: "user@example.com",
            accountPlan: "Pro",
            source: .local)

        #expect(AntigravityStatusProbe.localSnapshotScore(summary) > AntigravityStatusProbe.localSnapshotScore(legacy))
    }

    @Test
    func process_scan_reports_missing_csrf_when_only_tokenless_ide_matches() {
        let output = """
          100 /Applications/Antigravity.app/Contents/Resources/bin/language_server --app_data_dir antigravity
        """

        #expect(throws: AntigravityStatusProbeError.missingCSRFToken) {
            try AntigravityStatusProbe.processInfo(fromProcessListOutput: output)
        }
    }

    @Test
    func process_scan_allows_empty_csrf_only_for_explicit_cli_match() throws {
        let output = """
          200 /Users/test/.local/bin/agy -p hello
        """

        let result = try AntigravityStatusProbe.processInfo(fromProcessListOutput: output)

        #expect(result.pid == 200)
        #expect(result.csrfToken.isEmpty)
        #expect(result.commandLine == "/Users/test/.local/bin/agy -p hello")
    }

    @Test
    func ideOnly_scope_skips_app_and_cli_processes_and_reports_not_running() {
        let output = "  200 /Users/test/.local/bin/agy -p hello"

        #expect(throws: AntigravityStatusProbeError.notRunning) {
            try AntigravityStatusProbe.processInfo(fromProcessListOutput: output, scope: .ideOnly)
        }

        let app = "  101 /Applications/Antigravity.app/Contents/Resources/bin/language_server " +
            "--csrf_token app-token --app_data_dir antigravity"
        #expect(throws: AntigravityStatusProbeError.notRunning) {
            try AntigravityStatusProbe.processInfo(fromProcessListOutput: app, scope: .ideOnly)
        }
    }

    @Test
    func ideOnly_scope_still_matches_ide_server_listed_after_cli_and_app_processes() throws {
        let cli = "  200 /Users/test/.local/bin/agy -p hello"
        let app = "  101 /Applications/Antigravity.app/Contents/Resources/bin/language_server " +
            "--csrf_token app-token --app_data_dir antigravity"
        let ide = "  102 /Applications/Antigravity IDE.app/Contents/Resources/app/extensions/antigravity/bin/" +
            "language_server_macos_arm " +
            "--csrf_token ide-token --app_data_dir antigravity"
        let output = cli + "\n" + app + "\n" + ide

        let result = try AntigravityStatusProbe.processInfo(fromProcessListOutput: output, scope: .ideOnly)

        #expect(result.pid == 102)
        #expect(result.csrfToken == "ide-token")
    }

    @Test
    func appOnly_scope_skips_ide_and_cli_processes() throws {
        let cli = "  200 /Users/test/.local/bin/agy -p hello"
        let ide = "  102 /Applications/Antigravity IDE.app/Contents/Resources/app/extensions/antigravity/bin/" +
            "language_server_macos_arm --csrf_token ide-token --app_data_dir antigravity-ide"
        let app = "  101 /Applications/Antigravity.app/Contents/Resources/bin/language_server " +
            "--csrf_token app-token --app_data_dir antigravity"
        let output = cli + "\n" + ide + "\n" + app

        let result = try AntigravityStatusProbe.processInfo(fromProcessListOutput: output, scope: .appOnly)

        #expect(result.pid == 101)
        #expect(result.csrfToken == "app-token")
    }
}

extension AntigravityStatusProbeTests {
    @Test
    func localhost_trust_policy_only_accepts_local_server_trust_challenges() {
        #expect(
            LocalhostTrustPolicy.shouldAcceptServerTrust(
                host: "127.0.0.1",
                authenticationMethod: NSURLAuthenticationMethodServerTrust,
                hasServerTrust: true))
        #expect(
            LocalhostTrustPolicy.shouldAcceptServerTrust(
                host: "LOCALHOST",
                authenticationMethod: NSURLAuthenticationMethodServerTrust,
                hasServerTrust: true))

        #expect(
            !LocalhostTrustPolicy.shouldAcceptServerTrust(
                host: "cursor.com",
                authenticationMethod: NSURLAuthenticationMethodServerTrust,
                hasServerTrust: true))
        #expect(
            !LocalhostTrustPolicy.shouldAcceptServerTrust(
                host: "127.0.0.1",
                authenticationMethod: NSURLAuthenticationMethodHTTPBasic,
                hasServerTrust: true))
        #expect(
            !LocalhostTrustPolicy.shouldAcceptServerTrust(
                host: "127.0.0.1",
                authenticationMethod: NSURLAuthenticationMethodServerTrust,
                hasServerTrust: false))
    }

    @Test
    func localhost_trust_policy_rejects_non_loopback_hostnames_that_contain_localhost() {
        #expect(
            !LocalhostTrustPolicy.shouldAcceptServerTrust(
                host: "localhost.example.com",
                authenticationMethod: NSURLAuthenticationMethodServerTrust,
                hasServerTrust: true))
    }

    @Test
    func connection_candidates_preserve_scheme_order_and_endpoint_tokens() {
        let candidates = AntigravityStatusProbe.connectionCandidates(
            listeningPorts: [64440],
            languageServerCSRFToken: "language-token",
            extensionServerPort: 64432,
            extensionServerCSRFToken: "extension-token")

        #expect(
            candidates == [
                AntigravityStatusProbe.AntigravityConnectionEndpoint(
                    scheme: "https",
                    port: 64440,
                    csrfToken: "language-token",
                    source: .languageServer),
                AntigravityStatusProbe.AntigravityConnectionEndpoint(
                    scheme: "http",
                    port: 64432,
                    csrfToken: "extension-token",
                    source: .extensionServer),
                AntigravityStatusProbe.AntigravityConnectionEndpoint(
                    scheme: "http",
                    port: 64432,
                    csrfToken: "language-token",
                    source: .extensionServer),
            ])
    }

    @Test
    func connection_candidates_restrict_plain_http_probing_to_the_declared_extension_port() {
        let candidates = AntigravityStatusProbe.connectionCandidates(
            listeningPorts: [64440, 64441],
            languageServerCSRFToken: "language-token",
            extensionServerPort: 64432,
            extensionServerCSRFToken: nil)

        #expect(
            candidates == [
                AntigravityStatusProbe.AntigravityConnectionEndpoint(
                    scheme: "https",
                    port: 64440,
                    csrfToken: "language-token",
                    source: .languageServer),
                AntigravityStatusProbe.AntigravityConnectionEndpoint(
                    scheme: "https",
                    port: 64441,
                    csrfToken: "language-token",
                    source: .languageServer),
                AntigravityStatusProbe.AntigravityConnectionEndpoint(
                    scheme: "http",
                    port: 64432,
                    csrfToken: "language-token",
                    source: .extensionServer),
            ])
    }

    @Test
    func connection_candidates_preserve_extension_fallback_when_extension_token_is_unavailable() {
        let candidates = AntigravityStatusProbe.connectionCandidates(
            listeningPorts: [64440],
            languageServerCSRFToken: "language-token",
            extensionServerPort: 64432,
            extensionServerCSRFToken: nil)

        #expect(
            candidates == [
                AntigravityStatusProbe.AntigravityConnectionEndpoint(
                    scheme: "https",
                    port: 64440,
                    csrfToken: "language-token",
                    source: .languageServer),
                AntigravityStatusProbe.AntigravityConnectionEndpoint(
                    scheme: "http",
                    port: 64432,
                    csrfToken: "language-token",
                    source: .extensionServer),
            ])
    }

    @Test
    func connection_candidates_do_not_duplicate_the_same_http_target_when_ports_overlap() {
        let candidates = AntigravityStatusProbe.connectionCandidates(
            listeningPorts: [64432],
            languageServerCSRFToken: "language-token",
            extensionServerPort: 64432,
            extensionServerCSRFToken: nil)

        #expect(
            candidates == [
                AntigravityStatusProbe.AntigravityConnectionEndpoint(
                    scheme: "https",
                    port: 64432,
                    csrfToken: "language-token",
                    source: .languageServer),
                AntigravityStatusProbe.AntigravityConnectionEndpoint(
                    scheme: "http",
                    port: 64432,
                    csrfToken: "language-token",
                    source: .extensionServer),
            ])
    }

    @Test
    func request_endpoints_retry_extension_server_after_language_server_success() {
        let resolvedEndpoint = AntigravityStatusProbe.AntigravityConnectionEndpoint(
            scheme: "https",
            port: 64440,
            csrfToken: "language-token",
            source: .languageServer)

        let endpoints = AntigravityStatusProbe.requestEndpoints(
            resolvedEndpoint: resolvedEndpoint,
            listeningPorts: [64440],
            languageServerCSRFToken: "language-token",
            extensionServerPort: 64432,
            extensionServerCSRFToken: "extension-token")

        #expect(
            endpoints == [
                resolvedEndpoint,
                AntigravityStatusProbe.AntigravityConnectionEndpoint(
                    scheme: "http",
                    port: 64432,
                    csrfToken: "extension-token",
                    source: .extensionServer),
                AntigravityStatusProbe.AntigravityConnectionEndpoint(
                    scheme: "http",
                    port: 64432,
                    csrfToken: "language-token",
                    source: .extensionServer),
            ])
    }

    @Test
    func request_endpoints_preserve_extension_fallback_when_extension_token_is_unavailable() {
        let resolvedEndpoint = AntigravityStatusProbe.AntigravityConnectionEndpoint(
            scheme: "https",
            port: 64440,
            csrfToken: "language-token",
            source: .languageServer)

        let endpoints = AntigravityStatusProbe.requestEndpoints(
            resolvedEndpoint: resolvedEndpoint,
            listeningPorts: [64440],
            languageServerCSRFToken: "language-token",
            extensionServerPort: 64432,
            extensionServerCSRFToken: nil)

        #expect(
            endpoints == [
                resolvedEndpoint,
                AntigravityStatusProbe.AntigravityConnectionEndpoint(
                    scheme: "http",
                    port: 64432,
                    csrfToken: "language-token",
                    source: .extensionServer),
            ])
    }

    @Test
    func request_endpoints_retry_alternate_token_after_extension_server_wins_discovery() {
        let resolvedEndpoint = AntigravityStatusProbe.AntigravityConnectionEndpoint(
            scheme: "http",
            port: 64432,
            csrfToken: "extension-token",
            source: .extensionServer)

        let endpoints = AntigravityStatusProbe.requestEndpoints(
            resolvedEndpoint: resolvedEndpoint,
            listeningPorts: [64440],
            languageServerCSRFToken: "language-token",
            extensionServerPort: 64432,
            extensionServerCSRFToken: "extension-token")

        #expect(
            endpoints == [
                resolvedEndpoint,
                AntigravityStatusProbe.AntigravityConnectionEndpoint(
                    scheme: "http",
                    port: 64432,
                    csrfToken: "language-token",
                    source: .extensionServer),
                AntigravityStatusProbe.AntigravityConnectionEndpoint(
                    scheme: "https",
                    port: 64440,
                    csrfToken: "language-token",
                    source: .languageServer),
            ])
    }

    @Test
    func request_endpoints_keep_https_language_server_fallback_after_extension_probe_wins() {
        let resolvedEndpoint = AntigravityStatusProbe.AntigravityConnectionEndpoint(
            scheme: "http",
            port: 64432,
            csrfToken: "language-token",
            source: .extensionServer)

        let endpoints = AntigravityStatusProbe.requestEndpoints(
            resolvedEndpoint: resolvedEndpoint,
            listeningPorts: [64432, 64440],
            languageServerCSRFToken: "language-token",
            extensionServerPort: 64432,
            extensionServerCSRFToken: nil)

        #expect(
            endpoints == [
                resolvedEndpoint,
                AntigravityStatusProbe.AntigravityConnectionEndpoint(
                    scheme: "https",
                    port: 64432,
                    csrfToken: "language-token",
                    source: .languageServer),
                AntigravityStatusProbe.AntigravityConnectionEndpoint(
                    scheme: "https",
                    port: 64440,
                    csrfToken: "language-token",
                    source: .languageServer),
            ])
    }

    @Test
    func parsed_request_retries_later_endpoints_after_api_level_error_payload() async throws {
        let endpoints = [
            AntigravityStatusProbe.AntigravityConnectionEndpoint(
                scheme: "https",
                port: 64440,
                csrfToken: "bad-token",
                source: .languageServer),
            AntigravityStatusProbe.AntigravityConnectionEndpoint(
                scheme: "http",
                port: 64432,
                csrfToken: "good-token",
                source: .extensionServer),
        ]
        let attempted = AntigravityAttemptRecorder()

        let snapshot = try await AntigravityStatusProbe.makeParsedRequest(
            payload: AntigravityStatusProbe.RequestPayload(
                path: "/exa.language_server_pb.LanguageServerService/GetUserStatus",
                body: ["metadata": [:]]),
            context: AntigravityStatusProbe.RequestContext(
                endpoints: endpoints,
                timeout: 1),
            send: { _, endpoint, _ in
                attempted.append(endpoint)
                if endpoint.csrfToken == "bad-token" {
                    return Data(#"{"code":16}"#.utf8)
                }
                return Data(
                    #"""
                    {
                      "code": 0,
                      "userStatus": {
                        "email": "test@example.com",
                        "cascadeModelConfigData": {
                          "clientModelConfigs": []
                        }
                      }
                    }
                    """#.utf8)
            },
            parse: AntigravityStatusProbe.parseUserStatusResponse)

        #expect(snapshot.accountEmail == "test@example.com")
        #expect(attempted.snapshot() == endpoints)
    }

    @Test
    func endpoint_resolver_prefers_successful_https_language_server_candidate() async throws {
        let candidates = AntigravityStatusProbe.connectionCandidates(
            listeningPorts: [64440],
            languageServerCSRFToken: "language-token",
            extensionServerPort: 64432,
            extensionServerCSRFToken: "extension-token")
        let attempted = AntigravityAttemptRecorder()

        let endpoint = try await AntigravityStatusProbe.resolveWorkingEndpoint(
            candidateEndpoints: candidates,
            timeout: 1)
        { endpoint, _ in
            attempted.append(endpoint)
            return endpoint.scheme == "https" && endpoint.port == 64440
        }

        #expect(endpoint == candidates[0])
        #expect(attempted.snapshot() == [candidates[0]])
    }

    @Test
    func endpoint_resolver_falls_back_to_extension_server_after_https_language_server_candidates() async throws {
        let candidates = AntigravityStatusProbe.connectionCandidates(
            listeningPorts: [64440, 64441],
            languageServerCSRFToken: "language-token",
            extensionServerPort: 64432,
            extensionServerCSRFToken: "extension-token")
        let attempted = AntigravityAttemptRecorder()

        let endpoint = try await AntigravityStatusProbe.resolveWorkingEndpoint(
            candidateEndpoints: candidates,
            timeout: 1)
        { endpoint, _ in
            attempted.append(endpoint)
            return endpoint.scheme == "http" && endpoint.port == 64432 && endpoint.source == .extensionServer
        }

        #expect(endpoint == candidates[2])
        #expect(attempted.snapshot() == Array(candidates.prefix(3)))
    }

    @Test
    func endpoint_resolver_falls_back_to_alternate_extension_token_after_primary_token_fails() async throws {
        let candidates = AntigravityStatusProbe.connectionCandidates(
            listeningPorts: [64440],
            languageServerCSRFToken: "language-token",
            extensionServerPort: 64432,
            extensionServerCSRFToken: "extension-token")
        let attempted = AntigravityAttemptRecorder()

        let endpoint = try await AntigravityStatusProbe.resolveWorkingEndpoint(
            candidateEndpoints: candidates,
            timeout: 1)
        { endpoint, _ in
            attempted.append(endpoint)
            return endpoint.source == .extensionServer && endpoint.csrfToken == "language-token"
        }

        #expect(endpoint == candidates[2])
        #expect(attempted.snapshot() == candidates)
        #expect(endpoint.csrfToken == "language-token")
    }

    @Test
    func parses_user_status_response() throws {
        let json = """
        {
          "code": 0,
          "userStatus": {
            "email": "test@example.com",
            "planStatus": {
              "planInfo": {
                "planName": "Pro"
              }
            },
            "cascadeModelConfigData": {
              "clientModelConfigs": [
                {
                  "label": "Claude 3.5 Sonnet",
                  "modelOrAlias": { "model": "claude-3-5-sonnet" },
                  "quotaInfo": { "remainingFraction": 0.5, "resetTime": "2025-12-24T10:00:00Z" }
                },
                {
                  "label": "Gemini Pro Low",
                  "modelOrAlias": { "model": "gemini-pro-low" },
                  "quotaInfo": { "remainingFraction": 0.8, "resetTime": "2025-12-24T11:00:00Z" }
                },
                {
                  "label": "Gemini Flash",
                  "modelOrAlias": { "model": "gemini-flash" },
                  "quotaInfo": { "remainingFraction": 0.2, "resetTime": "2025-12-24T12:00:00Z" }
                }
              ]
            }
          }
        }
        """

        let data = Data(json.utf8)
        let snapshot = try AntigravityStatusProbe.parseUserStatusResponse(data)
        #expect(snapshot.accountEmail == "test@example.com")
        #expect(snapshot.accountPlan == "Pro")
        #expect(snapshot.modelQuotas.count == 3)

        let usage = try snapshot.toUsageSnapshot()
        guard let primary = usage.primary else {
            return
        }
        #expect(primary.remainingPercent.rounded() == 20)
        #expect(usage.secondary?.remainingPercent.rounded() == 50)
        #expect(usage.tertiary == nil)
    }

    @Test
    func prefers_user_tier_name_over_generic_plan_info() throws {
        let json = """
        {
          "code": 0,
          "userStatus": {
            "email": "ultra@example.com",
            "userTier": {
              "id": "google_ai_ultra",
              "name": "Google AI Ultra",
              "description": "Ultra tier"
            },
            "planStatus": {
              "planInfo": {
                "planName": "Pro"
              }
            },
            "cascadeModelConfigData": {
              "clientModelConfigs": []
            }
          }
        }
        """

        let data = Data(json.utf8)
        let snapshot = try AntigravityStatusProbe.parseUserStatusResponse(data)

        #expect(snapshot.accountEmail == "ultra@example.com")
        #expect(snapshot.accountPlan == "Google AI Ultra")
        #expect(snapshot.modelQuotas.isEmpty)
    }

    @Test
    func falls_back_to_plan_info_when_user_tier_name_is_blank() throws {
        let json = """
        {
          "code": 0,
          "userStatus": {
            "email": "fallback@example.com",
            "userTier": {
              "id": "google_ai_ultra",
              "name": "   ",
              "description": "Ultra tier"
            },
            "planStatus": {
              "planInfo": {
                "planName": "Pro"
              }
            },
            "cascadeModelConfigData": {
              "clientModelConfigs": []
            }
          }
        }
        """

        let data = Data(json.utf8)
        let snapshot = try AntigravityStatusProbe.parseUserStatusResponse(data)

        #expect(snapshot.accountEmail == "fallback@example.com")
        #expect(snapshot.accountPlan == "Pro")
        #expect(snapshot.modelQuotas.isEmpty)
    }

    @Test
    func claude_gpt_pool_can_use_thinking_variants() throws {
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Claude Thinking",
                    modelId: "claude-thinking",
                    remainingFraction: 0.7,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Claude Sonnet 4",
                    modelId: "claude-sonnet-4",
                    remainingFraction: 0.3,
                    resetTime: nil,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil)

        let usage = try snapshot.toUsageSnapshot()
        #expect(usage.primary == nil)
        #expect(usage.secondary?.remainingPercent.rounded() == 30)
    }

    @Test
    func claude_gpt_pool_uses_thinking_model_when_it_is_the_only_claude_option() throws {
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Claude Thinking",
                    modelId: "claude-thinking",
                    remainingFraction: 0.7,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3 Pro Low",
                    modelId: "gemini-3-pro-low",
                    remainingFraction: 0.4,
                    resetTime: nil,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil)

        let usage = try snapshot.toUsageSnapshot()
        #expect(usage.primary?.remainingPercent.rounded() == 40)
        #expect(usage.secondary?.remainingPercent.rounded() == 70)
    }

    @Test
    func gemini_pool_unavailable_when_only_excluded_variants_exist() throws {
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Gemini Pro Lite",
                    modelId: "gemini-3-pro-lite",
                    remainingFraction: 0.6,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Claude Sonnet 4",
                    modelId: "claude-sonnet-4",
                    remainingFraction: 0.3,
                    resetTime: nil,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil)

        let usage = try snapshot.toUsageSnapshot()
        #expect(usage.primary == nil)
        #expect(usage.secondary?.remainingPercent.rounded() == 30)
    }

    @Test
    func gemini_pool_chooses_most_constrained_pro_variant() throws {
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Gemini 3 Pro",
                    modelId: "gemini-3-pro",
                    remainingFraction: 0.9,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3 Pro Low",
                    modelId: "gemini-3-pro-low",
                    remainingFraction: 0.4,
                    resetTime: nil,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil)

        let usage = try snapshot.toUsageSnapshot()
        #expect(usage.primary?.remainingPercent.rounded() == 40)
        #expect(usage.secondary == nil)
    }

    @Test
    func gemini_pool_chooses_standard_pro_when_it_is_more_constrained_than_low_variant() throws {
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Gemini 3 Pro",
                    modelId: "gemini-3-pro",
                    remainingFraction: 0.1,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3 Pro Low",
                    modelId: "gemini-3-pro-low",
                    remainingFraction: 0.9,
                    resetTime: nil,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil)

        let usage = try snapshot.toUsageSnapshot()
        #expect(usage.primary?.remainingPercent.rounded() == 10)
        #expect(usage.secondary == nil)
    }

    @Test
    func gemini_pool_ignores_reset_only_placeholder_when_remaining_data_exists() throws {
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Gemini 3 Pro (Low)",
                    modelId: "MODEL_PLACEHOLDER_M36",
                    remainingFraction: nil,
                    resetTime: Date(timeIntervalSince1970: 1_735_000_000),
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3 Pro (High)",
                    modelId: "MODEL_PLACEHOLDER_M37",
                    remainingFraction: 1,
                    resetTime: Date(timeIntervalSince1970: 1_735_100_000),
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil)

        let usage = try snapshot.toUsageSnapshot()
        #expect(usage.primary?.remainingPercent.rounded() == 100)
        #expect(usage.secondary == nil)
    }

    @Test
    func gemini_pool_does_not_fallback_to_lite_flash_variant() throws {
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Gemini 2 Flash Lite",
                    modelId: "gemini-2-flash-lite",
                    remainingFraction: 0.2,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Claude Sonnet 4",
                    modelId: "claude-sonnet-4",
                    remainingFraction: 0.3,
                    resetTime: nil,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil)

        let usage = try snapshot.toUsageSnapshot()
        #expect(usage.tertiary == nil)
        #expect(usage.primary == nil)
        #expect(usage.secondary?.remainingPercent.rounded() == 30)
    }

    @Test
    func falls_back_to_labels_when_model_ids_are_placeholders() throws {
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Claude Sonnet 4.6",
                    modelId: "MODEL_PLACEHOLDER_M35",
                    remainingFraction: 0.3,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3.1 Pro (Low)",
                    modelId: "MODEL_PLACEHOLDER_M36",
                    remainingFraction: 0.4,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3 Flash",
                    modelId: "MODEL_PLACEHOLDER_M47",
                    remainingFraction: 1,
                    resetTime: nil,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil)

        let usage = try snapshot.toUsageSnapshot()
        #expect(usage.primary?.remainingPercent.rounded() == 40)
        #expect(usage.secondary?.remainingPercent.rounded() == 30)
        #expect(usage.tertiary == nil)
    }

    @Test
    func matches_remote_antigravity_model_names_with_parentheses() throws {
        let resetTime = Date(timeIntervalSince1970: 1_775_000_000)
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Claude Opus 4.6 (Thinking)",
                    modelId: "MODEL_PLACEHOLDER_M50",
                    remainingFraction: 1,
                    resetTime: resetTime,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Claude Sonnet 4.6 (Thinking)",
                    modelId: "MODEL_PLACEHOLDER_M51",
                    remainingFraction: 1,
                    resetTime: resetTime,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3 Pro (High)",
                    modelId: "MODEL_PLACEHOLDER_M52",
                    remainingFraction: 1,
                    resetTime: resetTime,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3 Pro (Low)",
                    modelId: "MODEL_PLACEHOLDER_M53",
                    remainingFraction: 1,
                    resetTime: resetTime,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3 Flash",
                    modelId: "MODEL_PLACEHOLDER_M54",
                    remainingFraction: 1,
                    resetTime: resetTime,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "GPT-OSS 120B (Medium)",
                    modelId: "MODEL_PLACEHOLDER_M55",
                    remainingFraction: 1,
                    resetTime: resetTime,
                    resetDescription: nil),
            ],
            accountEmail: "user@example.com",
            accountPlan: "Pro")

        let usage = try snapshot.toUsageSnapshot()
        #expect(usage.primary?.remainingPercent.rounded() == 100)
        #expect(usage.secondary?.remainingPercent.rounded() == 100)
        #expect(usage.tertiary == nil)
        #expect(usage.identity?.accountEmail == "user@example.com")
    }
}

extension AntigravityStatusProbeTests {
    @Test
    func known_model_quota_rows_collapse_into_two_usage_pools() throws {
        let resetTime = Date(timeIntervalSince1970: 1_775_000_000)
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "GPT-OSS 120B (Medium)",
                    modelId: "MODEL_PLACEHOLDER_M55",
                    remainingFraction: 0.25,
                    resetTime: resetTime,
                    resetDescription: "tomorrow"),
                AntigravityModelQuota(
                    label: "Gemini 3 Pro (Low)",
                    modelId: "MODEL_PLACEHOLDER_M53",
                    remainingFraction: 0.5,
                    resetTime: resetTime,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Claude Opus 4.6 (Thinking)",
                    modelId: "MODEL_PLACEHOLDER_M50",
                    remainingFraction: 0.75,
                    resetTime: resetTime,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3 Pro (High)",
                    modelId: "MODEL_PLACEHOLDER_M52",
                    remainingFraction: 1,
                    resetTime: resetTime,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil,
            source: .local)

        let usage = try snapshot.toUsageSnapshot()
        #expect(usage.primary?.remainingPercent.rounded() == 50)
        #expect(usage.secondary?.remainingPercent.rounded() == 25)
        #expect(usage.extraRateWindows == nil)
    }

    @Test
    func model_without_remaining_fraction_stays_out_of_family_summary_and_preserves_reset_metadata() throws {
        let resetTime = Date(timeIntervalSince1970: 1_735_000_000)
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Gemini 3.1 Pro (Low)",
                    modelId: "MODEL_PLACEHOLDER_M36",
                    remainingFraction: nil,
                    resetTime: resetTime,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3 Flash",
                    modelId: "MODEL_PLACEHOLDER_M47",
                    remainingFraction: 1,
                    resetTime: nil,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil)

        let usage = try snapshot.toUsageSnapshot()
        #expect(usage.primary?.remainingPercent.rounded() == 100)
        #expect(usage.secondary == nil)
        #expect(usage.tertiary == nil)
        #expect(usage.extraRateWindows == nil)
    }

    @Test
    func group_without_remaining_fraction_preserves_reset_metadata_as_unavailable_grouped_window() throws {
        let resetTime = Date(timeIntervalSince1970: 1_735_000_000)
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Gemini 3.1 Pro (Low)",
                    modelId: "MODEL_PLACEHOLDER_M36",
                    remainingFraction: nil,
                    resetTime: resetTime,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil)

        let usage = try snapshot.toUsageSnapshot()
        #expect(usage.primary == nil)
        let modelWindow = try #require(usage.extraRateWindows?.first)
        #expect(modelWindow.id == "antigravity-gemini")
        #expect(modelWindow.title == "Gemini Models")
        #expect(modelWindow.window.resetsAt == resetTime)
        #expect(modelWindow.usageKnown == false)
    }

    @Test
    func named_rate_windows_default_legacy_payloads_to_known_usage() throws {
        let json = """
        {
          "id": "legacy-window",
          "title": "Legacy Window",
          "window": {
            "usedPercent": 42,
            "windowMinutes": null,
            "resetsAt": null,
            "resetDescription": null,
            "nextRegenPercent": null
          }
        }
        """

        let decoded = try JSONDecoder().decode(NamedRateWindow.self, from: Data(json.utf8))

        #expect(decoded.usageKnown)
    }

    @Test
    func filtered_variants_stay_out_of_summary_but_remain_distinct_extras() throws {
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Gemini 3 Pro Lite",
                    modelId: "gemini-3-pro-lite",
                    remainingFraction: 0.6,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3 Flash Lite",
                    modelId: "gemini-3-flash-lite",
                    remainingFraction: 0.2,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Tab Autocomplete",
                    modelId: "tab_autocomplete_model",
                    remainingFraction: 0.9,
                    resetTime: nil,
                    resetDescription: nil),
            ],
            accountEmail: "test@example.com",
            accountPlan: "Pro",
            source: .local)

        let usage = try snapshot.toUsageSnapshot()
        #expect(usage.primary == nil)
        #expect(usage.secondary == nil)
        #expect(usage.tertiary == nil)
        #expect(usage.extraRateWindows?.map(\.id) == [
            "gemini-3-pro-lite",
            "gemini-3-flash-lite",
            "tab_autocomplete_model",
        ])
        #expect(usage.accountEmail(for: .antigravity) == "test@example.com")
        #expect(usage.loginMethod(for: .antigravity) == "Pro")
    }

    // MARK: - Source-aware filter + sort tests

    @Test
    func local_source_collapses_opaque_model_ids_into_two_usage_pools() throws {
        // Fixture A: 8 opaque-ID models, source .local -> two grouped quota pools
        let resetTime = Date(timeIntervalSince1970: 1_775_000_000)
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Claude Sonnet 4.6 (Thinking)",
                    modelId: "MODEL_PLACEHOLDER_M60",
                    remainingFraction: 0.8,
                    resetTime: resetTime,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Claude Opus 4.6 (Thinking)",
                    modelId: "MODEL_PLACEHOLDER_M61",
                    remainingFraction: 0.7,
                    resetTime: resetTime,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3.1 Pro (High)",
                    modelId: "MODEL_PLACEHOLDER_M62",
                    remainingFraction: 0.9,
                    resetTime: resetTime,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3.1 Pro (Low)",
                    modelId: "MODEL_PLACEHOLDER_M63",
                    remainingFraction: 0.4,
                    resetTime: resetTime,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3.5 Flash (High)",
                    modelId: "MODEL_PLACEHOLDER_M64",
                    remainingFraction: 0.6,
                    resetTime: resetTime,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3.5 Flash (Low)",
                    modelId: "MODEL_PLACEHOLDER_M65",
                    remainingFraction: 0.3,
                    resetTime: resetTime,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3.5 Flash (Medium)",
                    modelId: "MODEL_PLACEHOLDER_M66",
                    remainingFraction: 0.5,
                    resetTime: resetTime,
                    resetDescription: nil),
                // GPT-OSS pinned at remainingFraction == 1.0 - shown by local show-all
                AntigravityModelQuota(
                    label: "GPT-OSS 120B (Medium)",
                    modelId: "MODEL_PLACEHOLDER_M55",
                    remainingFraction: 1.0,
                    resetTime: resetTime,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil,
            source: .local)

        let usage = try snapshot.toUsageSnapshot()
        #expect(usage.primary?.remainingPercent.rounded() == 30)
        #expect(usage.secondary?.remainingPercent.rounded() == 70)
        #expect(usage.extraRateWindows == nil)
    }

    @Test
    func remote_source_collapses_recognized_family_models_and_hides_unconsumed_junk() throws {
        // Fixture B: verified 13 remote models; recognized text models collapse into Gemini,
        // and unconsumed junk stays hidden.
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                // junk: image
                AntigravityModelQuota(
                    label: "Gemini 2.5 Flash Image",
                    modelId: "gemini-2-5-flash-image",
                    remainingFraction: 1.0,
                    resetTime: nil,
                    resetDescription: nil),
                // junk: tab autocomplete
                AntigravityModelQuota(
                    label: "Tab Flash Lite Vertex",
                    modelId: "tab_flash_lite_vertex",
                    remainingFraction: 1.0,
                    resetTime: nil,
                    resetDescription: nil),
                // survivor
                AntigravityModelQuota(
                    label: "Gemini 2.5 Pro",
                    modelId: "gemini-2-5-pro",
                    remainingFraction: 1.0,
                    resetTime: nil,
                    resetDescription: nil),
                // survivor
                AntigravityModelQuota(
                    label: "Gemini 3 Pro (High)",
                    modelId: "gemini-3-pro-high",
                    remainingFraction: 1.0,
                    resetTime: nil,
                    resetDescription: nil),
                // junk: lite
                AntigravityModelQuota(
                    label: "Gemini 2.5 Flash Lite",
                    modelId: "gemini-2-5-flash-lite",
                    remainingFraction: 1.0,
                    resetTime: nil,
                    resetDescription: nil),
                // junk: image
                AntigravityModelQuota(
                    label: "Gemini 3 Pro Image",
                    modelId: "gemini-3-pro-image",
                    remainingFraction: 1.0,
                    resetTime: nil,
                    resetDescription: nil),
                // survivor
                AntigravityModelQuota(
                    label: "Gemini 3 Flash",
                    modelId: "gemini-3-flash",
                    remainingFraction: 1.0,
                    resetTime: nil,
                    resetDescription: nil),
                // junk: lite
                AntigravityModelQuota(
                    label: "Gemini 3.1 Flash Lite",
                    modelId: "gemini-3-1-flash-lite",
                    remainingFraction: 1.0,
                    resetTime: nil,
                    resetDescription: nil),
                // survivor
                AntigravityModelQuota(
                    label: "Gemini 3.1 Pro (Low)",
                    modelId: "gemini-3-1-pro-low",
                    remainingFraction: 1.0,
                    resetTime: nil,
                    resetDescription: nil),
                // survivor
                AntigravityModelQuota(
                    label: "Gemini 3.1 Pro (High)",
                    modelId: "gemini-3-1-pro-high",
                    remainingFraction: 1.0,
                    resetTime: nil,
                    resetDescription: nil),
                // junk: tab autocomplete
                AntigravityModelQuota(
                    label: "Tab Jump Flash Lite Vertex",
                    modelId: "tab_jump_flash_lite_vertex",
                    remainingFraction: 1.0,
                    resetTime: nil,
                    resetDescription: nil),
                // survivor
                AntigravityModelQuota(
                    label: "Gemini 3 Pro (Low)",
                    modelId: "gemini-3-pro-low",
                    remainingFraction: 1.0,
                    resetTime: nil,
                    resetDescription: nil),
                // survivor
                AntigravityModelQuota(
                    label: "Gemini 2.5 Flash",
                    modelId: "gemini-2-5-flash",
                    remainingFraction: 1.0,
                    resetTime: nil,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil,
            source: .remote)

        let usage = try snapshot.toUsageSnapshot()
        #expect(usage.primary?.remainingPercent.rounded() == 100)
        #expect(usage.secondary == nil)
        #expect(usage.extraRateWindows == nil)
    }

    @Test
    func remote_source_shows_consumed_junk_models_despite_filter() throws {
        // Fixture C: junk models with remainingFraction < 0.999 must be shown
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                // consumed tab - should be shown
                AntigravityModelQuota(
                    label: "Tab Flash Lite Vertex",
                    modelId: "tab_flash_lite_vertex",
                    remainingFraction: 0.4,
                    resetTime: nil,
                    resetDescription: nil),
                // consumed image - should be shown
                AntigravityModelQuota(
                    label: "Gemini 3 Pro Image",
                    modelId: "gemini-3-pro-image",
                    remainingFraction: 0.4,
                    resetTime: nil,
                    resetDescription: nil),
                // unconsumed sibling tab (0.9995 >= 0.999) - should be hidden
                AntigravityModelQuota(
                    label: "Tab Jump Flash Lite Vertex",
                    modelId: "tab_jump_flash_lite_vertex",
                    remainingFraction: 0.9995,
                    resetTime: nil,
                    resetDescription: nil),
                // a clean survivor for non-empty guard
                AntigravityModelQuota(
                    label: "Gemini 3 Flash",
                    modelId: "gemini-3-flash",
                    remainingFraction: 1.0,
                    resetTime: nil,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil,
            source: .remote)

        let usage = try snapshot.toUsageSnapshot()
        let extraWindows = try #require(usage.extraRateWindows)
        let ids = extraWindows.map(\.id)

        // Consumed junk models shown despite being junk type
        #expect(ids.contains("tab_flash_lite_vertex"))
        #expect(ids.contains("gemini-3-pro-image"))

        // Unconsumed sibling stays hidden
        #expect(!ids.contains("tab_jump_flash_lite_vertex"))
    }

    @Test
    func remote_source_image_models_do_not_drive_family_summary_bars() throws {
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Gemini 3 Pro Image",
                    modelId: "gemini-3-pro-image",
                    remainingFraction: 0.2,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3 Pro (High)",
                    modelId: "gemini-3-pro-high",
                    remainingFraction: 0.9,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3 Flash Image",
                    modelId: "gemini-3-flash-image",
                    remainingFraction: 0.1,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3 Flash",
                    modelId: "gemini-3-flash",
                    remainingFraction: 0.8,
                    resetTime: nil,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil,
            source: .remote)

        let usage = try snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 20)
        #expect(usage.secondary == nil)
        #expect(usage.extraRateWindows?.map(\.id).contains("gemini-3-pro-image") == true)
        #expect(usage.extraRateWindows?.map(\.id).contains("gemini-3-flash-image") == true)
    }

    @Test
    func remote_source_yields_nil_extra_windows_when_all_models_are_unconsumed_junk() throws {
        // Fixture D: all-junk-unconsumed -> extraRateWindows nil
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Tab Flash Lite Vertex",
                    modelId: "tab_flash_lite_vertex",
                    remainingFraction: 1.0,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 2.5 Flash Lite",
                    modelId: "gemini-2-5-flash-lite",
                    remainingFraction: 1.0,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3 Pro Image",
                    modelId: "gemini-3-pro-image",
                    remainingFraction: 1.0,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Unknown Model X",
                    modelId: "unknown-model-x",
                    remainingFraction: 1.0,
                    resetTime: nil,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil,
            source: .remote)

        let usage = try snapshot.toUsageSnapshot()
        #expect(usage.primary == nil)
        #expect(usage.secondary == nil)
        #expect(usage.tertiary == nil)
        #expect(usage.extraRateWindows == nil)
    }

    @Test
    func ordering_edge_cases_collapse_to_most_constrained_usage_pool() throws {
        // Fixture F: local source; known Gemini Pro rows collapse into the Gemini pool
        // using the most constrained remaining fraction.
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Gemini 3 Pro (Low)",
                    modelId: "MODEL_PLACEHOLDER_M70",
                    remainingFraction: 0.5,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini 3 Pro (High)",
                    modelId: "MODEL_PLACEHOLDER_M71",
                    remainingFraction: 0.8,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Gemini Pro Experimental",
                    modelId: "MODEL_PLACEHOLDER_M72",
                    remainingFraction: 0.3,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Claude Sonnet 4",
                    modelId: "MODEL_PLACEHOLDER_M73",
                    remainingFraction: 0.9,
                    resetTime: nil,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil,
            source: .local)

        let usage = try snapshot.toUsageSnapshot()
        #expect(usage.primary?.remainingPercent.rounded() == 30)
        #expect(usage.secondary?.remainingPercent.rounded() == 90)
        #expect(usage.extraRateWindows == nil)
    }

    @Test
    func nil_version_unknown_family_models_sort_deterministically_by_label() throws {
        // Strict-weak-ordering guard: two .unknown models with unparseable versions
        // should sort by label without trapping
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "Zebra Unknown Model",
                    modelId: "MODEL_PLACEHOLDER_MA",
                    remainingFraction: 0.5,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "Alpha Unknown Model",
                    modelId: "MODEL_PLACEHOLDER_MB",
                    remainingFraction: 0.5,
                    resetTime: nil,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil,
            source: .local)

        let usage = try snapshot.toUsageSnapshot()
        let extraWindows = try #require(usage.extraRateWindows)
        let titles = extraWindows.map(\.title)

        // Deterministic: label tiebreaker -> Alpha before Zebra
        #expect(titles == ["Alpha Unknown Model", "Zebra Unknown Model"])
    }

    @Test
    func hyphenated_raw_model_ids_without_display_name_still_map_to_gemini_group() throws {
        // When the remote catalog omits displayName/label, the raw hyphenated model id
        // becomes the label and still participates in the Gemini group.
        let snapshot = AntigravityStatusSnapshot(
            modelQuotas: [
                AntigravityModelQuota(
                    label: "gemini-3-pro-preview",
                    modelId: "gemini-3-pro-preview",
                    remainingFraction: 1,
                    resetTime: nil,
                    resetDescription: nil),
                AntigravityModelQuota(
                    label: "gemini-2.5-pro",
                    modelId: "gemini-2.5-pro",
                    remainingFraction: 1,
                    resetTime: nil,
                    resetDescription: nil),
            ],
            accountEmail: nil,
            accountPlan: nil,
            source: .remote)

        let usage = try snapshot.toUsageSnapshot()
        #expect(usage.primary?.remainingPercent.rounded() == 100)
        #expect(usage.extraRateWindows == nil)
    }

    @Test
    func http_probe_errors_still_count_as_reachable() {
        #expect(
            AntigravityStatusProbe.isReachableProbeError(
                AntigravityStatusProbeError.apiError("HTTP 403: Forbidden")))
        #expect(
            AntigravityStatusProbe.isReachableProbeError(
                AntigravityStatusProbeError.apiError("HTTP 404: Not Found")))
        #expect(
            !AntigravityStatusProbe.isReachableProbeError(
                AntigravityStatusProbeError.apiError("Invalid response")))
        #expect(!AntigravityStatusProbe.isReachableProbeError(AntigravityStatusProbeError.notRunning))
    }

    @Test
    func fallback_probe_port_prefers_non_extension_candidate() {
        #expect(
            AntigravityStatusProbe.fallbackProbePort(
                ports: [51170, 61775],
                extensionPort: 61775) == 51170)
        #expect(
            AntigravityStatusProbe.fallbackProbePort(
                ports: [61775],
                extensionPort: 61775) == 61775)
        #expect(
            AntigravityStatusProbe.fallbackProbePort(
                ports: [51170, 61775],
                extensionPort: nil) == 51170)
    }
}
