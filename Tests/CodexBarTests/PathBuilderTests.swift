import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct PathBuilderTests {
    @Test
    func merges_login_shell_path_when_available() {
        let seeded = PathBuilder.effectivePATH(
            purposes: [.rpc],
            env: ["PATH": "/custom/bin:/usr/bin"],
            loginPATH: ["/login/bin", "/login/alt"])
        #expect(seeded == "/login/bin:/login/alt:/custom/bin:/usr/bin")
    }

    @Test
    func falls_back_to_existing_path_when_no_login_path() {
        let seeded = PathBuilder.effectivePATH(
            purposes: [.tty],
            env: ["PATH": "/custom/bin:/usr/bin"],
            loginPATH: nil)
        #expect(seeded == "/custom/bin:/usr/bin")
    }

    @Test
    func uses_fallback_when_no_path_available() {
        let seeded = PathBuilder.effectivePATH(
            purposes: [.tty],
            env: [:],
            loginPATH: nil)
        #expect(seeded == "/usr/bin:/bin:/usr/sbin:/sbin")
    }

    @Test
    func debug_snapshot_async_matches_sync() async {
        let env = [
            "CODEX_CLI_PATH": "/usr/bin/true",
            "CLAUDE_CLI_PATH": "/usr/bin/true",
            "GEMINI_CLI_PATH": "/usr/bin/true",
            "PATH": "/usr/bin:/bin",
        ]
        let sync = PathBuilder.debugSnapshot(purposes: [.rpc], env: env, home: "/tmp")
        let async = await PathBuilder.debugSnapshotAsync(purposes: [.rpc], env: env, home: "/tmp")
        #expect(async == sync)
    }

    @Test
    func login_shell_cache_retries_after_timed_out_nil_capture() async {
        let capture = LoginShellPathCaptureStub([
            nil,
            ["/login/bin", "/usr/bin"],
        ])

        let cache = LoginShellPathCache { _, _ in capture.next() }
        let firstResult: [String]? = await withCheckedContinuation { continuation in
            cache.captureOnce(shell: "/unused", timeout: 0.01) { result in
                continuation.resume(returning: result)
            }
        }

        #expect(firstResult == nil)
        #expect(cache.current == nil)

        let recovered = cache.currentOrCapture(shell: "/unused", timeout: 2.0)
        #expect(recovered == ["/login/bin", "/usr/bin"])
        #expect(cache.current == ["/login/bin", "/usr/bin"])
        #expect(capture.callCount == 2)
    }

    @Test
    func shell_runner_drains_noisy_stdout_and_stderr() throws {
        let script = """
        i=0
        while [ "$i" -lt 4000 ]; do
          printf 'out-%04d\\n' "$i"
          printf 'err-%04d\\n' "$i" >&2
          i=$((i + 1))
        done
        printf '__CODEXBAR_DONE__\\n'
        """
        let data = try #require(ShellCommandLocator.test_runShellCommand(
            shell: "/bin/sh",
            arguments: ["-c", script],
            timeout: 4.0))
        let output = try #require(String(data: data, encoding: .utf8))

        #expect(output.contains("out-3999"))
        #expect(output.contains("__CODEXBAR_DONE__"))
    }

    @Test
    func shell_runner_terminates_background_children_after_normal_exit() throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-shell-runner-\(UUID().uuidString)")
            .path
        let escapedMarker = Self.shellSingleQuoted(marker)
        let script = """
        (
          trap '' HUP TERM
          touch \(escapedMarker)
          while :; do sleep 1; done
        ) &
        printf '%s\\n' "$!"
        """
        let data = try #require(ShellCommandLocator.test_runShellCommand(
            shell: "/bin/sh",
            arguments: ["-c", script],
            timeout: 2.0))
        let pidText = try #require(String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines))
        let pid = try #require(pid_t(pidText))

        defer {
            kill(pid, SIGKILL)
            try? FileManager.default.removeItem(atPath: marker)
        }

        let deadline = Date().addingTimeInterval(2.0)
        while kill(pid, 0) == 0, Date() < deadline {
            usleep(50000 as useconds_t)
        }

        #expect(kill(pid, 0) != 0)
    }

    @Test
    func resolves_codex_from_env_override() {
        let overridePath = "/custom/bin/codex"
        let fm = MockFileManager(executables: [overridePath])

        let resolved = BinaryLocator.resolveCodexBinary(
            env: ["CODEX_CLI_PATH": overridePath],
            loginPATH: nil,
            fileManager: fm,
            home: "/home/test")
        #expect(resolved == overridePath)
    }

    @Test
    func resolves_codex_from_login_path() {
        let fm = MockFileManager(executables: ["/login/bin/codex"])
        let resolved = BinaryLocator.resolveCodexBinary(
            env: ["PATH": "/env/bin"],
            loginPATH: ["/login/bin"],
            fileManager: fm,
            home: "/home/test")
        #expect(resolved == "/login/bin/codex")
    }

    @Test
    func resolves_codex_from_env_path() {
        let fm = MockFileManager(executables: ["/env/bin/codex"])
        let resolved = BinaryLocator.resolveCodexBinary(
            env: ["PATH": "/env/bin:/usr/bin"],
            loginPATH: nil,
            fileManager: fm,
            home: "/home/test")
        #expect(resolved == "/env/bin/codex")
    }

    @Test
    func resolves_codex_from_bundled_ChatGPT_app() {
        let appPath = "/Applications/ChatGPT.app/Contents/Resources/codex"
        let fm = MockFileManager(executables: [appPath])

        let resolved = BinaryLocator.resolveCodexBinary(
            env: ["PATH": "/missing/bin"],
            loginPATH: nil,
            commandV: { _, _, _, _ in nil },
            aliasResolver: { _, _, _, _, _ in nil },
            launchCandidateFilter: { _, _ in true },
            fileManager: fm,
            home: "/Users/test")

        #expect(resolved == appPath)
    }

    @Test
    func resolves_codex_from_user_bundled_ChatGPT_app() {
        let appPath = "/Users/test/Applications/ChatGPT.app/Contents/Resources/codex"
        let fm = MockFileManager(executables: [appPath])

        let resolved = BinaryLocator.resolveCodexBinary(
            env: ["PATH": "/missing/bin"],
            loginPATH: nil,
            commandV: { _, _, _, _ in nil },
            aliasResolver: { _, _, _, _, _ in nil },
            launchCandidateFilter: { _, _ in true },
            fileManager: fm,
            home: "/Users/test")

        #expect(resolved == appPath)
    }

    @Test
    func prefers_bundled_ChatGPT_app_over_legacy_Codex_app_within_one_scope() {
        let chatGPTPath = "/Applications/ChatGPT.app/Contents/Resources/codex"
        let codexPath = "/Applications/Codex.app/Contents/Resources/codex"
        let fm = MockFileManager(executables: [chatGPTPath, codexPath])

        let resolved = BinaryLocator.resolveCodexBinary(
            env: ["PATH": "/missing/bin"],
            loginPATH: nil,
            commandV: { _, _, _, _ in nil },
            aliasResolver: { _, _, _, _, _ in nil },
            launchCandidateFilter: { _, _ in true },
            fileManager: fm,
            home: "/Users/test")

        #expect(resolved == chatGPTPath)
    }

    @Test
    func preserves_user_app_precedence_over_system_ChatGPT_app() {
        let userCodexPath = "/Users/test/Applications/Codex.app/Contents/Resources/codex"
        let systemChatGPTPath = "/Applications/ChatGPT.app/Contents/Resources/codex"
        let fm = MockFileManager(executables: [userCodexPath, systemChatGPTPath])

        let resolved = BinaryLocator.resolveCodexBinary(
            env: ["PATH": "/missing/bin"],
            loginPATH: nil,
            commandV: { _, _, _, _ in nil },
            aliasResolver: { _, _, _, _, _ in nil },
            launchCandidateFilter: { _, _ in true },
            fileManager: fm,
            home: "/Users/test")

        #expect(resolved == userCodexPath)
    }

    @Test
    func skips_blocked_ChatGPT_app_and_falls_back_to_legacy_Codex_app() {
        let chatGPTPath = "/Users/test/Applications/ChatGPT.app/Contents/Resources/codex"
        let codexPath = "/Users/test/Applications/Codex.app/Contents/Resources/codex"
        let fm = MockFileManager(executables: [chatGPTPath, codexPath])
        var checked: [String] = []

        let resolved = BinaryLocator.resolveCodexBinary(
            env: ["PATH": "/missing/bin"],
            loginPATH: nil,
            commandV: { _, _, _, _ in nil },
            aliasResolver: { _, _, _, _, _ in nil },
            launchCandidateFilter: { path, _ in
                checked.append(path)
                return path != chatGPTPath
            },
            fileManager: fm,
            home: "/Users/test")

        #expect(resolved == codexPath)
        #expect(checked == [chatGPTPath, codexPath])
    }

    @Test
    func skips_blocked_codex_path_and_falls_back_to_signed_app_binary() {
        let blockedPath = "/usr/local/bin/codex"
        let appPath = "/Applications/Codex.app/Contents/Resources/codex"
        let fm = MockFileManager(executables: [blockedPath, appPath])
        var checked: [String] = []

        let resolved = BinaryLocator.resolveCodexBinary(
            env: ["PATH": "/usr/local/bin"],
            loginPATH: nil,
            commandV: { _, _, _, _ in nil },
            aliasResolver: { _, _, _, _, _ in nil },
            launchCandidateFilter: { path, _ in
                checked.append(path)
                return path != blockedPath
            },
            fileManager: fm,
            home: "/Users/test")

        #expect(resolved == appPath)
        #expect(checked == [blockedPath, appPath])
    }

    @Test
    func explicit_codex_override_bypasses_launch_candidate_fallback() {
        let overridePath = "/custom/bin/codex"
        let appPath = "/Applications/Codex.app/Contents/Resources/codex"
        let fm = MockFileManager(executables: [overridePath, appPath])
        var checked: [String] = []

        let resolved = BinaryLocator.resolveCodexBinary(
            env: ["CODEX_CLI_PATH": overridePath],
            loginPATH: nil,
            launchCandidateFilter: { path, _ in
                checked.append(path)
                return false
            },
            fileManager: fm,
            home: "/Users/test")

        #expect(resolved == overridePath)
        #expect(checked.isEmpty)
    }

    @Test
    func Codex_CLI_strategy_availability_uses_filtered_binary_resolution() {
        let commandV: (String, String?, TimeInterval, FileManager) -> String? = { _, _, _, _ in nil }
        let aliasResolver: (String, String?, TimeInterval, FileManager, String) -> String? = { _, _, _, _, _ in nil }

        let unavailable = CodexCLIUsageStrategy.resolvedBinary(
            env: ["PATH": "/missing/bin", "SHELL": "/bin/sh"],
            loginPATH: nil,
            commandV: commandV,
            aliasResolver: aliasResolver,
            fileManager: MockFileManager(executables: []),
            home: "/home/test")
        #expect(unavailable == nil)

        let available = CodexCLIUsageStrategy.resolvedBinary(
            env: ["PATH": "/tools/bin", "SHELL": "/bin/sh"],
            loginPATH: nil,
            commandV: commandV,
            aliasResolver: aliasResolver,
            fileManager: MockFileManager(executables: ["/tools/bin/codex"]),
            home: "/home/test")
        #expect(available == "/tools/bin/codex")
    }

    #if os(macOS)
    @Test
    func Codex_launch_preflight_allows_quarantined_notarized_native_binary() {
        let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: "/Applications/Codex.app/Contents/Resources/codex",
            fileManager: MockFileManager(executables: []),
            hasExtendedAttribute: { _, name in name == "com.apple.quarantine" },
            spctlAssessment: { _ in .init(output: "accepted\nsource=Notarized Developer ID", exitStatus: 0) },
            appSignatureIsTrusted: { _ in true },
            isMachOExecutable: { _ in true })

        #expect(allowed)
    }

    @Test
    func Codex_launch_preflight_blocks_malware_attribute_before_assessment() {
        var assessed = false
        let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: "/Applications/Codex.app/Contents/Resources/codex",
            fileManager: MockFileManager(executables: []),
            hasExtendedAttribute: { _, name in name == "com.apple.malware" },
            spctlAssessment: { _ in
                assessed = true
                return .init(output: "accepted\nsource=Notarized Developer ID", exitStatus: 0)
            },
            appSignatureIsTrusted: { _ in true },
            isMachOExecutable: { _ in true })

        #expect(!allowed)
        #expect(!assessed)
    }

    @Test
    func Codex_launch_preflight_validates_containing_app_bundle() {
        let executable = "/Applications/ChatGPT.app/Contents/Resources/codex"
        let bundle = "/Applications/ChatGPT.app"
        var assessedPaths: [String] = []

        let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: executable,
            fileManager: MockFileManager(executables: []),
            hasExtendedAttribute: { path, name in
                path == bundle && name == "com.apple.quarantine"
            },
            spctlAssessment: { path in
                assessedPaths.append(path)
                return .init(output: "\(path): accepted\nsource=Notarized Developer ID", exitStatus: 0)
            },
            appSignatureIsTrusted: { path in path == bundle },
            isMachOExecutable: { path in path == executable })

        #expect(allowed)
        #expect(assessedPaths == [bundle])
    }

    @Test
    func Codex_launch_preflight_blocks_unexpected_app_signing_identity() {
        let executable = "/Users/test/Applications/ChatGPT.app/Contents/Resources/codex"
        let bundle = "/Users/test/Applications/ChatGPT.app"
        var assessed = false

        let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: executable,
            fileManager: MockFileManager(executables: []),
            hasExtendedAttribute: { _, _ in false },
            spctlAssessment: { _ in
                assessed = true
                return .init(output: "accepted", exitStatus: 0)
            },
            appSignatureIsTrusted: { path in
                #expect(path == bundle)
                return false
            },
            isMachOExecutable: { path in path == executable })

        #expect(!allowed)
        #expect(!assessed)
    }

    @Test
    func Codex_launch_preflight_blocks_rejected_containing_app_bundle() {
        let executable = "/Users/test/Applications/ChatGPT.app/Contents/Resources/codex"
        let bundle = "/Users/test/Applications/ChatGPT.app"

        let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: executable,
            fileManager: MockFileManager(executables: []),
            hasExtendedAttribute: { _, _ in false },
            spctlAssessment: { path in
                #expect(path == bundle)
                return .init(output: "\(path): rejected\nsource=no usable signature", exitStatus: 3)
            },
            appSignatureIsTrusted: { _ in true },
            isMachOExecutable: { path in path == executable })

        #expect(!allowed)
    }

    @Test
    func Codex_launch_preflight_requires_successful_app_bundle_assessment() {
        let executable = "/Users/test/Applications/ChatGPT.app/Contents/Resources/codex"
        let bundle = "/Users/test/Applications/ChatGPT.app"

        let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: executable,
            fileManager: MockFileManager(executables: []),
            hasExtendedAttribute: { _, _ in false },
            spctlAssessment: { path in
                #expect(path == bundle)
                return .init(output: "\(path): accepted", exitStatus: 1)
            },
            appSignatureIsTrusted: { _ in true },
            isMachOExecutable: { path in path == executable })

        #expect(!allowed)
    }

    @Test
    func Codex_launch_preflight_rejects_indeterminate_app_assessment() {
        let executable = "/Users/test/Applications/ChatGPT.app/Contents/Resources/codex"
        let bundle = "/Users/test/Applications/ChatGPT.app"

        let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: executable,
            fileManager: MockFileManager(executables: []),
            hasExtendedAttribute: { _, _ in false },
            spctlAssessment: { path in
                #expect(path == bundle)
                return .init(output: "internal code signing error", exitStatus: 0)
            },
            appSignatureIsTrusted: { _ in true },
            isMachOExecutable: { path in path == executable })

        #expect(!allowed)
    }

    @Test
    func Codex_launch_preflight_fails_closed_when_app_bundle_cannot_be_assessed() {
        let executable = "/Users/test/Applications/ChatGPT.app/Contents/Resources/codex"
        let bundle = "/Users/test/Applications/ChatGPT.app"

        let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: executable,
            fileManager: MockFileManager(executables: []),
            hasExtendedAttribute: { path, name in
                path == bundle && name == "com.apple.quarantine"
            },
            spctlAssessment: { path in
                #expect(path == bundle)
                return nil
            },
            appSignatureIsTrusted: { _ in true },
            isMachOExecutable: { _ in false })

        #expect(!allowed)
    }

    @Test
    func Codex_launch_preflight_blocks_app_bundled_executable_symlink_escaping_the_bundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundle = root.appendingPathComponent("ChatGPT.app")
        let resources = bundle.appendingPathComponent("Contents/Resources")
        let executable = resources.appendingPathComponent("codex")
        let escapedTarget = root.appendingPathComponent("outside-codex")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data().write(to: escapedTarget)
        try FileManager.default.createSymbolicLink(at: executable, withDestinationURL: escapedTarget)
        defer { try? FileManager.default.removeItem(at: root) }
        var assessed = false

        let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: executable.path,
            fileManager: FileManager.default,
            hasExtendedAttribute: { _, _ in false },
            spctlAssessment: { _ in
                assessed = true
                return .init(output: "accepted", exitStatus: 0)
            },
            appSignatureIsTrusted: { _ in true },
            isMachOExecutable: { _ in true })

        #expect(!allowed)
        #expect(!assessed)
    }

    @Test
    func Codex_launch_preflight_blocks_quarantined_script_without_native_assessment() {
        let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: "/opt/homebrew/bin/codex",
            fileManager: MockFileManager(executables: []),
            hasExtendedAttribute: { _, name in name == "com.apple.quarantine" },
            spctlAssessment: { _ in nil },
            appSignatureIsTrusted: { _ in true },
            isMachOExecutable: { _ in false })

        #expect(!allowed)
    }

    @Test
    func Codex_launch_preflight_blocks_revoked_assessment() {
        let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: "/Applications/Codex.app/Contents/Resources/codex",
            fileManager: MockFileManager(executables: []),
            hasExtendedAttribute: { _, _ in false },
            spctlAssessment: { _ in .init(output: "rejected\nCSSMERR_TP_CERT_REVOKED", exitStatus: 3) },
            appSignatureIsTrusted: { _ in true },
            isMachOExecutable: { _ in true })

        #expect(!allowed)
    }

    @Test
    func Codex_launch_preflight_blocks_generic_Gatekeeper_rejection() {
        let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: "/opt/homebrew/bin/codex",
            fileManager: MockFileManager(executables: []),
            hasExtendedAttribute: { _, _ in false },
            spctlAssessment: { _ in .init(output: "rejected\nsource=no usable signature", exitStatus: 3) },
            appSignatureIsTrusted: { _ in true },
            isMachOExecutable: { _ in true })

        #expect(!allowed)
    }

    @Test
    func Codex_launch_preflight_allows_valid_signed_command_line_binary_assessment() {
        let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: "/opt/homebrew/bin/codex",
            fileManager: MockFileManager(executables: []),
            hasExtendedAttribute: { _, name in name == "com.apple.quarantine" },
            spctlAssessment: { path in
                .init(
                    output: "\(path): rejected (the code is valid but does not seem to be an app)",
                    exitStatus: 3)
            },
            appSignatureIsTrusted: { _ in true },
            isMachOExecutable: { _ in true })

        #expect(allowed)
    }

    @Test
    func Codex_launch_preflight_blocks_revoked_assessment_even_with_non_app_rejection_text() {
        let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: "/opt/homebrew/bin/codex",
            fileManager: MockFileManager(executables: []),
            hasExtendedAttribute: { _, name in name == "com.apple.quarantine" },
            spctlAssessment: { _ in
                .init(
                    output: """
                    rejected (the code is valid but does not seem to be an app)
                    CSSMERR_TP_CERT_REVOKED
                    """,
                    exitStatus: 3)
            },
            appSignatureIsTrusted: { _ in true },
            isMachOExecutable: { _ in true })

        #expect(!allowed)
    }

    @Test
    func Codex_launch_preflight_ignores_benign_text_in_path_when_verdict_is_generic_rejection() {
        let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: "/tmp/code is valid but does not seem to be an app/codex",
            fileManager: MockFileManager(executables: []),
            hasExtendedAttribute: { _, name in name == "com.apple.quarantine" },
            spctlAssessment: { path in
                .init(output: "\(path): rejected\nsource=no usable signature", exitStatus: 3)
            },
            appSignatureIsTrusted: { _ in true },
            isMachOExecutable: { _ in true })

        #expect(!allowed)
    }

    @Test
    func Codex_launch_preflight_ignores_benign_text_before_verdict_separator() {
        let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: "/tmp/x: code is valid but does not seem to be an app/codex",
            fileManager: MockFileManager(executables: []),
            hasExtendedAttribute: { _, name in name == "com.apple.quarantine" },
            spctlAssessment: { path in
                .init(output: "\(path): rejected\nsource=no usable signature", exitStatus: 3)
            },
            appSignatureIsTrusted: { _ in true },
            isMachOExecutable: { _ in true })

        #expect(!allowed)
    }

    @Test
    func Codex_launch_preflight_ignores_blocked_words_in_accepted_path_and_source_fields() {
        let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: "/tmp/rejected/quarantine/codex",
            fileManager: MockFileManager(executables: []),
            hasExtendedAttribute: { _, name in name == "com.apple.quarantine" },
            spctlAssessment: { path in
                .init(
                    output: """
                    \(path): accepted
                    source=revoked quarantine marker
                    origin=malware test fixture
                    """,
                    exitStatus: 0)
            },
            appSignatureIsTrusted: { _ in true },
            isMachOExecutable: { _ in true })

        #expect(allowed)
    }
    #endif

    @Test
    func resolves_codex_from_interactive_shell() {
        let fm = MockFileManager(executables: ["/shell/bin/codex"])
        let commandV: (String, String?, TimeInterval, FileManager) -> String? = { tool, shell, timeout, fileManager in
            #expect(tool == "codex")
            #expect(shell == "/bin/zsh")
            #expect(timeout == 2.0)
            _ = fileManager
            return "/shell/bin/codex"
        }

        let resolved = BinaryLocator.resolveCodexBinary(
            env: ["SHELL": "/bin/zsh"],
            loginPATH: nil,
            commandV: commandV,
            fileManager: fm,
            home: "/home/test")
        #expect(resolved == "/shell/bin/codex")
    }

    @Test
    func resolves_claude_from_interactive_shell() {
        let fm = MockFileManager(executables: ["/shell/bin/claude"])
        let commandV: (String, String?, TimeInterval, FileManager) -> String? = { tool, shell, timeout, fileManager in
            #expect(tool == "claude")
            #expect(shell == "/bin/zsh")
            #expect(timeout == 2.0)
            _ = fileManager
            return "/shell/bin/claude"
        }

        let resolved = BinaryLocator.resolveClaudeBinary(
            env: ["SHELL": "/bin/zsh"],
            loginPATH: nil,
            commandV: commandV,
            fileManager: fm,
            home: "/home/test")
        #expect(resolved == "/shell/bin/claude")
    }

    @Test
    func resolves_gemini_from_interactive_shell() {
        let fm = MockFileManager(executables: ["/shell/bin/gemini"])
        let commandV: (String, String?, TimeInterval, FileManager) -> String? = { tool, shell, timeout, fileManager in
            #expect(tool == "gemini")
            #expect(shell == "/bin/zsh")
            #expect(timeout == 2.0)
            _ = fileManager
            return "/shell/bin/gemini"
        }

        let resolved = BinaryLocator.resolveGeminiBinary(
            env: ["SHELL": "/bin/zsh"],
            loginPATH: nil,
            commandV: commandV,
            fileManager: fm,
            home: "/home/test")
        #expect(resolved == "/shell/bin/gemini")
    }

    @Test
    func resolves_claude_from_login_path() {
        let fm = MockFileManager(executables: ["/login/bin/claude"])
        let resolved = BinaryLocator.resolveClaudeBinary(
            env: ["PATH": "/env/bin"],
            loginPATH: ["/login/bin"],
            fileManager: fm,
            home: "/home/test")
        #expect(resolved == "/login/bin/claude")
    }

    @Test
    func resolves_claude_from_alias_when_other_lookups_fail() {
        let aliasPath = "/home/test/.claude/local/bin/claude"
        let fm = MockFileManager(executables: [aliasPath])
        var aliasCalled = false
        let aliasResolver: (String, String?, TimeInterval, FileManager, String)
            -> String? = { tool, shell, timeout, _, home in
                aliasCalled = true
                #expect(tool == "claude")
                #expect(shell == "/bin/zsh")
                #expect(timeout == 2.0)
                #expect(home == "/home/test")
                return aliasPath
            }
        let commandV: (String, String?, TimeInterval, FileManager) -> String? = { _, _, _, _ in
            nil
        }

        let resolved = BinaryLocator.resolveClaudeBinary(
            env: ["SHELL": "/bin/zsh"],
            loginPATH: nil,
            commandV: commandV,
            aliasResolver: aliasResolver,
            fileManager: fm,
            home: "/home/test")

        #expect(aliasCalled)
        #expect(resolved == aliasPath)
    }

    @Test
    func resolves_codex_from_alias_when_other_lookups_fail() {
        let aliasPath = "/home/test/.codex/bin/codex"
        let fm = MockFileManager(executables: [aliasPath])
        var aliasCalled = false
        let aliasResolver: (String, String?, TimeInterval, FileManager, String)
            -> String? = { tool, shell, timeout, _, home in
                aliasCalled = true
                #expect(tool == "codex")
                #expect(shell == "/bin/zsh")
                #expect(timeout == 2.0)
                #expect(home == "/home/test")
                return aliasPath
            }
        let commandV: (String, String?, TimeInterval, FileManager) -> String? = { _, _, _, _ in
            nil
        }

        let resolved = BinaryLocator.resolveCodexBinary(
            env: ["SHELL": "/bin/zsh"],
            loginPATH: nil,
            commandV: commandV,
            aliasResolver: aliasResolver,
            fileManager: fm,
            home: "/home/test")

        #expect(aliasCalled)
        #expect(resolved == aliasPath)
    }

    @Test
    func resolves_claude_from_well_known_cmux_path_when_shell_lookups_fail() {
        let cmuxPath = "/Applications/cmux.app/Contents/Resources/bin/claude"
        let fm = MockFileManager(executables: [cmuxPath])
        let commandV: (String, String?, TimeInterval, FileManager) -> String? = { _, _, _, _ in nil }
        let aliasResolver: (String, String?, TimeInterval, FileManager, String) -> String? = { _, _, _, _, _ in nil }

        let resolved = BinaryLocator.resolveClaudeBinary(
            env: ["SHELL": "/bin/zsh"],
            loginPATH: nil,
            commandV: commandV,
            aliasResolver: aliasResolver,
            fileManager: fm,
            home: "/Users/test")
        #expect(resolved == cmuxPath)
    }

    @Test
    func resolves_claude_from_well_known_home_dir_path() {
        let homePath = "/Users/test/.claude/bin/claude"
        let fm = MockFileManager(executables: [homePath])
        let commandV: (String, String?, TimeInterval, FileManager) -> String? = { _, _, _, _ in nil }
        let aliasResolver: (String, String?, TimeInterval, FileManager, String) -> String? = { _, _, _, _, _ in nil }

        let resolved = BinaryLocator.resolveClaudeBinary(
            env: ["SHELL": "/bin/zsh"],
            loginPATH: nil,
            commandV: commandV,
            aliasResolver: aliasResolver,
            fileManager: fm,
            home: "/Users/test")
        #expect(resolved == homePath)
    }

    @Test
    func resolves_claude_from_native_installer_path() {
        let nativePath = "/Users/test/.local/bin/claude"
        let fm = MockFileManager(executables: [nativePath])
        let commandV: (String, String?, TimeInterval, FileManager) -> String? = { _, _, _, _ in nil }
        let aliasResolver: (String, String?, TimeInterval, FileManager, String) -> String? = { _, _, _, _, _ in nil }

        let resolved = BinaryLocator.resolveClaudeBinary(
            env: ["SHELL": "/bin/zsh"],
            loginPATH: nil,
            commandV: commandV,
            aliasResolver: aliasResolver,
            fileManager: fm,
            home: "/Users/test")
        #expect(resolved == nativePath)
    }

    @Test
    func prefers_migrated_local_claude_path_over_legacy_home_dir_path() {
        let migratedPath = "/Users/test/.claude/local/claude"
        let legacyPath = "/Users/test/.claude/bin/claude"
        let fm = MockFileManager(executables: [migratedPath, legacyPath])
        let commandV: (String, String?, TimeInterval, FileManager) -> String? = { _, _, _, _ in nil }
        let aliasResolver: (String, String?, TimeInterval, FileManager, String) -> String? = { _, _, _, _, _ in nil }

        let resolved = BinaryLocator.resolveClaudeBinary(
            env: ["SHELL": "/bin/zsh"],
            loginPATH: nil,
            commandV: commandV,
            aliasResolver: aliasResolver,
            fileManager: fm,
            home: "/Users/test")
        #expect(resolved == migratedPath)
    }

    @Test
    func prefers_user_managed_well_known_path_over_cmux_path() {
        let homePath = "/Users/test/.claude/bin/claude"
        let cmuxPath = "/Applications/cmux.app/Contents/Resources/bin/claude"
        let fm = MockFileManager(executables: [homePath, cmuxPath])
        let commandV: (String, String?, TimeInterval, FileManager) -> String? = { _, _, _, _ in nil }
        let aliasResolver: (String, String?, TimeInterval, FileManager, String) -> String? = { _, _, _, _, _ in nil }

        let resolved = BinaryLocator.resolveClaudeBinary(
            env: ["SHELL": "/bin/zsh"],
            loginPATH: nil,
            commandV: commandV,
            aliasResolver: aliasResolver,
            fileManager: fm,
            home: "/Users/test")
        #expect(resolved == homePath)
    }

    @Test
    func prefers_homebrew_arm_path_over_usr_local_fallback() {
        let fm = MockFileManager(executables: [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ])
        let commandV: (String, String?, TimeInterval, FileManager) -> String? = { _, _, _, _ in nil }
        let aliasResolver: (String, String?, TimeInterval, FileManager, String) -> String? = { _, _, _, _, _ in nil }

        let resolved = BinaryLocator.resolveClaudeBinary(
            env: ["SHELL": "/bin/zsh"],
            loginPATH: nil,
            commandV: commandV,
            aliasResolver: aliasResolver,
            fileManager: fm,
            home: "/Users/test")
        #expect(resolved == "/opt/homebrew/bin/claude")
    }

    @Test
    func prefers_well_known_paths_over_interactive_shell_lookup() {
        let shellPath = "/custom/bin/claude"
        let cmuxPath = "/Applications/cmux.app/Contents/Resources/bin/claude"
        let fm = MockFileManager(executables: [shellPath, cmuxPath])
        var shellLookupCalled = false
        let commandV: (String, String?, TimeInterval, FileManager) -> String? = { _, _, _, _ in
            shellLookupCalled = true
            return shellPath
        }

        let resolved = BinaryLocator.resolveClaudeBinary(
            env: ["SHELL": "/bin/zsh"],
            loginPATH: nil,
            commandV: commandV,
            fileManager: fm,
            home: "/Users/test")
        #expect(!shellLookupCalled)
        #expect(resolved == cmuxPath)
    }

    @Test
    func skips_alias_when_command_V_resolves() {
        let path = "/shell/bin/claude"
        let fm = MockFileManager(executables: [path])
        var aliasCalled = false
        let aliasResolver: (String, String?, TimeInterval, FileManager, String) -> String? = { _, _, _, _, _ in
            aliasCalled = true
            return "/alias/claude"
        }
        let commandV: (String, String?, TimeInterval, FileManager) -> String? = { _, _, _, _ in
            path
        }

        let resolved = BinaryLocator.resolveClaudeBinary(
            env: ["SHELL": "/bin/zsh"],
            loginPATH: nil,
            commandV: commandV,
            aliasResolver: aliasResolver,
            fileManager: fm,
            home: "/home/test")

        #expect(!aliasCalled)
        #expect(resolved == path)
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

private final class LoginShellPathCaptureStub: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [[String]?]
    private var callCountStorage = 0

    var callCount: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.callCountStorage
    }

    init(_ results: [[String]?]) {
        self.results = results
    }

    func next() -> [String]? {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.callCountStorage += 1
        return self.results.isEmpty ? nil : self.results.removeFirst()
    }
}

private final class MockFileManager: FileManager {
    private let executables: Set<String>

    init(executables: Set<String>) {
        self.executables = executables
    }

    override func isExecutableFile(atPath path: String) -> Bool {
        self.executables.contains(path)
    }
}
