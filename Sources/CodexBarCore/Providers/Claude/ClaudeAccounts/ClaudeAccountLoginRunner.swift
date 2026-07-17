import Foundation

public enum ClaudeAccountLoginRunnerError: LocalizedError, Equatable, Sendable {
    case cliNotFound

    public var errorDescription: String? {
        switch self {
        case .cliNotFound:
            "The `claude` CLI was not found. Install Claude Code, then retry."
        }
    }
}

/// Runs `claude auth login` for the login-new-account flow (REQ-009), mirroring
/// CCSwitcher: the subprocess opens the browser OAuth flow and is awaited to its
/// natural exit — no timeout, the user signs in at their own pace.
public enum ClaudeAccountLoginRunner {
    public static func runLogin() async throws {
        guard let binary = BinaryLocator.resolveClaudeBinary() else {
            throw ClaudeAccountLoginRunnerError.cliNotFound
        }
        var environment = ProcessInfo.processInfo.environment
        // npm-installed claude needs node discoverable on PATH.
        environment["PATH"] = PathBuilder.effectivePATH(purposes: [.nodeTooling])
        _ = try await SubprocessRunner.runToCompletion(
            binary: binary,
            arguments: ["auth", "login"],
            environment: environment,
            acceptsNonZeroExit: false,
            label: "claude auth login")
        // Give the keychain a moment to settle after the CLI writes (CCSwitcher parity).
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }
}
