import AppKit
import CodexBarCore

/// Bridges the CLI's interactive sign-in to the Accounts pane (REQ-009, ADR-006):
/// it starts the PTY session, opens the link in a private window, and parks the
/// transaction until the user pastes the code back into the sheet.
@MainActor
@Observable
final class ClaudeAccountLoginPresenter {
    static let shared = ClaudeAccountLoginPresenter()

    private(set) var authorizationURL: URL?
    private(set) var isAwaitingCode = false
    private(set) var openedPrivately = false

    @ObservationIgnored private var session: ClaudeAccountLoginSession?
    @ObservationIgnored private var codeContinuation: CheckedContinuation<String, any Error>?

    /// Injected into `ClaudeAccountService` as its login runner: it must not return
    /// until the CLI has written the new credential position, because the service
    /// captures the freshly signed-in account as soon as this call finishes.
    func runInteractiveLogin() async throws {
        let session = ClaudeAccountLoginSession()
        self.session = session
        defer { self.finish() }

        let url = try await session.start()
        self.authorizationURL = url
        self.isAwaitingCode = true
        self.openedPrivately = Self.openInPrivateWindow(url)

        let code = try await withCheckedThrowingContinuation { continuation in
            self.codeContinuation = continuation
        }
        try await session.submitCode(code)
    }

    func submit(code: String) {
        guard let continuation = self.codeContinuation else { return }
        self.codeContinuation = nil
        self.isAwaitingCode = false
        continuation.resume(returning: code)
    }

    func cancel() {
        let continuation = self.codeContinuation
        self.codeContinuation = nil
        self.isAwaitingCode = false
        let session = self.session
        Task { await session?.cancel() }
        continuation?.resume(throwing: ClaudeAccountLoginRunnerError.cancelled)
    }

    func reopenAuthorizationURL() {
        guard let url = self.authorizationURL else { return }
        self.openedPrivately = Self.openInPrivateWindow(url)
    }

    func copyAuthorizationURL() {
        guard let url = self.authorizationURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func finish() {
        self.session = nil
        self.codeContinuation = nil
        self.isAwaitingCode = false
        self.authorizationURL = nil
        self.openedPrivately = false
    }

    /// Opens the link in a Chromium private window so the browser's existing claude.com
    /// session cannot authorise the account the user is trying to move away from.
    /// Returns false when only the default browser was available.
    private static func openInPrivateWindow(_ url: URL) -> Bool {
        let candidates: [(bundleID: String, flag: String)] = [
            ("com.microsoft.edgemac", "--inprivate"),
            ("com.google.Chrome", "--incognito"),
        ]
        for candidate in candidates {
            guard let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: candidate.bundleID)
            else { continue }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-na", appURL.path, "--args", candidate.flag, url.absoluteString]
            if (try? process.run()) != nil {
                return true
            }
        }
        NSWorkspace.shared.open(url)
        return false
    }
}
