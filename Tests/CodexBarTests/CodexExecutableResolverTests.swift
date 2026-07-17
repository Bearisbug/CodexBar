import Foundation
import Testing
@testable import CodexBarCore

struct CodexExecutableResolverTests {
    @Test
    func explicit_native_override_skips_login_path_capture() {
        let resolved = resolveCodexExecutableForRPC(
            environment: ["CODEX_CLI_PATH": "/usr/bin/true"],
            executable: "codex",
            captureLoginPATH: {
                Issue.record("Native override should not capture a login-shell PATH")
                return nil
            })

        #expect(resolved?.executable == "/usr/bin/true")
        #expect(resolved?.loginPATH == nil)
    }

    @Test
    func explicit_script_override_captures_login_path_for_env_based_launchers() throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-script-override-\(UUID().uuidString)")
        try Data("#!/usr/bin/env node\n".utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let loginPATH = ["/custom/node/bin", "/usr/bin"]
        var captureCount = 0
        let resolved = resolveCodexExecutableForRPC(
            environment: ["CODEX_CLI_PATH": scriptURL.path],
            executable: "codex",
            captureLoginPATH: {
                captureCount += 1
                return loginPATH
            })

        #expect(resolved?.executable == scriptURL.path)
        #expect(resolved?.loginPATH == loginPATH)
        #expect(captureCount == 1)
    }
}
