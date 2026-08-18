import Foundation

#if canImport(Darwin)
import Darwin
#endif

public enum ClaudeAccountLoginRunnerError: LocalizedError, Equatable, Sendable {
    case cliNotFound
    case interactiveLoginUnavailable
    case ptyUnavailable(detail: String)
    case authorizationURLMissing(detail: String)
    case cancelled
    case exitFailure(status: Int32, detail: String)

    public var errorDescription: String? {
        switch self {
        case .cliNotFound:
            "The `claude` CLI was not found. Install Claude Code, then retry."
        case .interactiveLoginUnavailable:
            "Signing in needs the CodexBar app: run it from Preferences → Providers → Claude."
        case let .ptyUnavailable(detail):
            "Could not start an interactive `claude auth login` session: \(detail)"
        case let .authorizationURLMissing(detail):
            "`claude auth login` did not print a sign-in link. \(detail)"
        case .cancelled:
            "Sign-in was cancelled."
        case let .exitFailure(status, detail):
            detail.isEmpty
                ? "`claude auth login` failed with exit code \(status)."
                : "`claude auth login` failed: \(detail)"
        }
    }
}

/// Drives `claude auth login` through a PTY so its paste-the-code flow can complete
/// inside the app (REQ-009, design v1.10 / ADR-006).
///
/// Claude Code 2.1.x no longer signs in through a localhost callback: it prints an
/// authorization link, the browser hands the user a code, and the CLI reads that code
/// from an interactive stdin. A plain subprocess inherits the GUI app's closed stdin,
/// so the CLI dies with "Login failed: Socket is closed" — hence the PTY, and hence the
/// two-phase API: `start()` yields the link for the UI to open, `submitCode(_:)` answers
/// the CLI's prompt. `BROWSER` is neutralised so the caller decides where the link opens
/// (a private window, so an already signed-in session cannot hijack the new account).
public actor ClaudeAccountLoginSession {
    /// The CLI prints the link within a second; allow for a slow cold start.
    private static let authorizationURLTimeout: TimeInterval = 45
    /// The token exchange is a single request once the code is pasted.
    private static let completionTimeout: TimeInterval = 120
    private static let pollInterval: TimeInterval = 0.05
    private static let log = CodexBarLog.logger(LogCategories.claudeAccounts)

    private var process: Process?
    private var primaryFD: Int32 = -1
    private var primaryHandle: FileHandle?
    private var secondaryHandle: FileHandle?
    private var transcript = ""

    public init() {}

    /// Launches the CLI and returns the authorization link it prints.
    public func start() async throws -> URL {
        guard let binary = BinaryLocator.resolveClaudeBinary() else {
            throw ClaudeAccountLoginRunnerError.cliNotFound
        }
        try self.launch(binary: binary)
        Self.log.info("login session started")

        let deadline = Date().addingTimeInterval(Self.authorizationURLTimeout)
        while Date() < deadline {
            self.drainAvailableOutput()
            if let url = Self.authorizationURL(in: self.transcript) {
                Self.log.info("login session captured the sign-in link")
                return url
            }
            if let process = self.process, !process.isRunning {
                self.drainAvailableOutput()
                if let url = Self.authorizationURL(in: self.transcript) {
                    return url
                }
                let status = process.terminationStatus
                self.cleanup()
                throw ClaudeAccountLoginRunnerError.exitFailure(
                    status: status,
                    detail: Self.failureDetail(in: self.transcript))
            }
            try await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
        }
        self.cleanup()
        throw ClaudeAccountLoginRunnerError.authorizationURLMissing(
            detail: "Timed out after \(Int(Self.authorizationURLTimeout))s.")
    }

    /// Answers the CLI's "Paste code here" prompt and waits for the sign-in to finish.
    public func submitCode(_ code: String) async throws {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ClaudeAccountLoginRunnerError.cancelled
        }
        guard let process = self.process, process.isRunning else {
            throw ClaudeAccountLoginRunnerError.exitFailure(
                status: self.process?.terminationStatus ?? -1,
                detail: Self.failureDetail(in: self.transcript))
        }
        // The CLI's prompt is line-based: a carriage return submits the pasted code.
        try self.writeToPTY(trimmed + "\r")
        Self.log.info("login session submitted the pasted code")

        let deadline = Date().addingTimeInterval(Self.completionTimeout)
        while Date() < deadline {
            self.drainAvailableOutput()
            if !process.isRunning {
                self.drainAvailableOutput()
                let status = process.terminationStatus
                let transcript = self.transcript
                self.cleanup()
                guard status == 0 else {
                    throw ClaudeAccountLoginRunnerError.exitFailure(
                        status: status,
                        detail: Self.failureDetail(in: transcript))
                }
                Self.log.info("login session completed")
                // The CLI writes the credential position on its way out; give the
                // keychain a moment to settle before the capture reads it back.
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                return
            }
            try await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
        }
        let transcript = self.transcript
        self.cleanup()
        throw ClaudeAccountLoginRunnerError.exitFailure(
            status: -1,
            detail: Self.failureDetail(in: transcript).isEmpty
                ? "Timed out waiting for the sign-in to finish."
                : Self.failureDetail(in: transcript))
    }

    /// Terminates the CLI when the user dismisses the sign-in sheet.
    public func cancel() {
        guard self.process != nil else { return }
        Self.log.info("login session cancelled")
        self.cleanup()
    }

    // MARK: - Output parsing

    /// Extracts the authorization link, tolerating ANSI colouring and OSC 8 hyperlinks
    /// (the CLI emits the URL twice: once as the hyperlink target, once as visible text).
    static func authorizationURL(in transcript: String) -> URL? {
        let text = TextParsing.stripANSICodes(transcript)
        guard let range = text.range(of: "https://claude.com/", options: .literal) else { return nil }
        let terminators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{07}\u{1b}\""))
        let tail = text[range.lowerBound...]
        let candidate = tail.unicodeScalars.prefix { !terminators.contains($0) }
        let raw = String(String.UnicodeScalarView(candidate))
        // A truncated link (still streaming) has no query yet; wait for the full one.
        guard raw.contains("oauth/authorize"), raw.contains("code_challenge") else { return nil }
        return URL(string: raw)
    }

    /// Picks the CLI's own failure line out of the transcript for the error surface.
    static func failureDetail(in transcript: String) -> String {
        let text = TextParsing.stripANSICodes(transcript)
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let failure = lines.last(where: { $0.localizedCaseInsensitiveContains("failed") }) {
            return failure
        }
        return lines.last ?? ""
    }

    // MARK: - PTY plumbing

    private func launch(binary: String) throws {
        var primaryFD: Int32 = -1
        var secondaryFD: Int32 = -1
        var win = winsize(ws_row: 50, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primaryFD, &secondaryFD, nil, nil, &win) == 0 else {
            throw ClaudeAccountLoginRunnerError.ptyUnavailable(detail: "openpty failed")
        }
        _ = fcntl(primaryFD, F_SETFL, O_NONBLOCK)

        let primaryHandle = FileHandle(fileDescriptor: primaryFD, closeOnDealloc: true)
        let secondaryHandle = FileHandle(fileDescriptor: secondaryFD, closeOnDealloc: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["auth", "login"]
        process.standardInput = secondaryHandle
        process.standardOutput = secondaryHandle
        process.standardError = secondaryHandle

        var environment = ClaudeCLISession.launchEnvironment()
        // The caller opens the link itself (private window); stop the CLI from racing
        // it with the default browser, where the current account is already signed in.
        environment["BROWSER"] = "/usr/bin/true"
        process.environment = environment

        do {
            try process.run()
        } catch {
            try? primaryHandle.close()
            try? secondaryHandle.close()
            throw ClaudeAccountLoginRunnerError.ptyUnavailable(detail: error.localizedDescription)
        }
        // Own the process group so cancellation cannot leave the CLI waiting on the PTY.
        _ = setpgid(process.processIdentifier, process.processIdentifier)

        self.process = process
        self.primaryFD = primaryFD
        self.primaryHandle = primaryHandle
        self.secondaryHandle = secondaryHandle
        self.transcript = ""
    }

    private func drainAvailableOutput() {
        guard self.primaryFD >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = buffer.withUnsafeMutableBytes { pointer in
                read(self.primaryFD, pointer.baseAddress, pointer.count)
            }
            guard count > 0 else { return }
            let chunk = Data(buffer.prefix(count))
            // Chunks split mid-codepoint; the lossy conversion keeps the scan going and
            // the link is re-scanned on every poll until it parses.
            self.transcript += String(bytes: chunk, encoding: .utf8)
                ?? String(bytes: chunk, encoding: .isoLatin1)
                ?? ""
        }
    }

    private func writeToPTY(_ text: String) throws {
        guard self.primaryFD >= 0 else {
            throw ClaudeAccountLoginRunnerError.ptyUnavailable(detail: "session is closed")
        }
        let bytes = Array(text.utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { pointer in
                Darwin.write(self.primaryFD, pointer.baseAddress!.advanced(by: offset), pointer.count - offset)
            }
            if written > 0 {
                offset += written
                continue
            }
            if errno == EAGAIN || errno == EINTR {
                usleep(20000)
                continue
            }
            throw ClaudeAccountLoginRunnerError.ptyUnavailable(detail: "write failed (errno \(errno))")
        }
    }

    private func cleanup() {
        if let process = self.process, process.isRunning {
            let pid = process.processIdentifier
            process.terminate()
            kill(-pid, SIGTERM)
            usleep(100_000)
            if process.isRunning {
                kill(-pid, SIGKILL)
            }
        }
        try? self.primaryHandle?.close()
        try? self.secondaryHandle?.close()
        self.primaryHandle = nil
        self.secondaryHandle = nil
        self.primaryFD = -1
        self.process = nil
    }
}
