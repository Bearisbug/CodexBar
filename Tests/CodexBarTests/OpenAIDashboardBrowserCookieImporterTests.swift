import Foundation
import Testing
@testable import CodexBarCore

private final class CookieCallbackHarness: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable () -> Void)?

    func capture(_ callback: @escaping @Sendable () -> Void) {
        self.lock.withLock { self.callback = callback }
    }

    func finish() {
        let callback = self.lock.withLock {
            let callback = self.callback
            self.callback = nil
            return callback
        }
        callback?()
    }
}

private final class CookieCallbackFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        self.lock.withLock { self.storedValue }
    }

    func set() {
        self.lock.withLock { self.storedValue = true }
    }
}

private final class CookieOperationLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    var snapshot: [String] {
        self.lock.withLock { self.entries }
    }

    func append(_ entry: String) {
        self.lock.withLock { self.entries.append(entry) }
    }
}

private final class CookieTimeoutProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedFiredAt: Date?

    var firedAt: Date? {
        self.lock.withLock { self.storedFiredAt }
    }

    func record() {
        self.lock.withLock {
            if self.storedFiredAt == nil {
                self.storedFiredAt = Date()
            }
        }
    }
}

struct OpenAIDashboardBrowserCookieImporterTests {
    @Test
    func profile_denial_names_exact_running_component() {
        let hint = OpenAIDashboardBrowserCookieImporter.browserProfileAccessHint(
            for: .chrome,
            issue: .accessDenied,
            processName: "CodexBarCLI",
            executablePath: "/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI")

        #expect(hint.contains("macOS denied Chrome profile access"))
        #expect(hint.contains("CodexBarCLI (/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI)"))
        #expect(hint.contains("Full Disk Access"))
    }

    @Test
    func profile_denial_names_app_bundle_for_menu_refresh() {
        let hint = OpenAIDashboardBrowserCookieImporter.browserProfileAccessHint(
            for: .chrome,
            issue: .accessDenied,
            processName: "CodexBar",
            executablePath: "/Applications/CodexBar.app/Contents/MacOS/CodexBar")

        #expect(hint.contains("CodexBar.app (/Applications/CodexBar.app)"))
    }

    @Test
    func browser_cookie_timeout_remains_distinct_from_permission_denial() {
        let error = OpenAIDashboardBrowserCookieImporter.browserCookieLoadTimeoutError(
            for: .chrome,
            processName: "CodexBarCLI",
            executablePath: "/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI")

        if case .browserCookieLoadTimedOut = error {
            // Expected: a shared deadline does not prove macOS denied access.
        } else {
            Issue.record("Expected browser cookie load timeout")
        }
        #expect(error.localizedDescription.contains("Chrome did not finish before the web timeout"))
        #expect(!error.localizedDescription.contains("access denied"))
        #expect(error.localizedDescription.contains("CodexBarCLI"))
        #expect(error.localizedDescription.contains("Keychain prompt"))
        #expect(error.localizedDescription.contains("Full Disk Access"))
    }

    @Test
    func shared_deadline_clamps_each_local_timeout_to_remaining_budget() throws {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let deadline = start.addingTimeInterval(30)

        let remaining = try OpenAIDashboardBrowserCookieImporter.remainingTimeout(
            until: deadline,
            cappedAt: 10,
            now: start.addingTimeInterval(27))

        #expect(remaining == 3)
    }

    @Test
    func shared_deadline_preserves_smaller_local_timeout() throws {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let deadline = start.addingTimeInterval(30)

        let remaining = try OpenAIDashboardBrowserCookieImporter.remainingTimeout(
            until: deadline,
            cappedAt: 10,
            now: start.addingTimeInterval(5))

        #expect(remaining == 10)
    }

    @Test
    func expired_shared_deadline_throws_structured_timeout() {
        let deadline = Date(timeIntervalSinceReferenceDate: 1000)

        do {
            _ = try OpenAIDashboardBrowserCookieImporter.remainingTimeout(
                until: deadline,
                now: deadline)
            Issue.record("Expected deadline timeout")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func blocking_browser_cookie_load_cannot_exceed_shared_deadline() async throws {
        let start = Date()
        let timeoutProbe = CookieTimeoutProbe()

        do {
            _ = try await OpenAIDashboardBrowserCookieImporter.runBoundedCookieLoad(
                deadline: start.addingTimeInterval(0.05),
                timeoutObserver: timeoutProbe.record)
            {
                Thread.sleep(forTimeInterval: 0.5)
                return true
            }
            Issue.record("Expected cookie load timeout")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        let firedAt = try #require(timeoutProbe.firedAt)
        #expect(firedAt.timeIntervalSince(start) < 0.3)
    }

    @Test
    func timeout_observer_stays_silent_when_operation_wins() async throws {
        let timeoutProbe = CookieTimeoutProbe()

        let value = try await OpenAIDashboardBrowserCookieImporter.runBoundedCookieLoad(
            deadline: Date().addingTimeInterval(0.05),
            timeoutObserver: timeoutProbe.record)
        {
            true
        }
        try await Task.sleep(for: .milliseconds(100))

        #expect(value)
        #expect(timeoutProbe.firedAt == nil)
    }

    @Test
    func bounded_cookie_loads_preserve_explicit_retry_context() async throws {
        BrowserCookieAccessGate.resetForTesting()
        defer { BrowserCookieAccessGate.resetForTesting() }
        let start = Date()

        for deadline in [nil, Date().addingTimeInterval(1)] {
            BrowserCookieAccessGate.resetForTesting()
            BrowserCookieAccessGate.recordDenied(for: .arc, now: start)

            let allowed = try await BrowserCookieAccessGate.withExplicitRetry {
                try await ProviderInteractionContext.$current.withValue(.userInitiated) {
                    try await OpenAIDashboardBrowserCookieImporter.runBoundedCookieLoad(deadline: deadline) {
                        KeychainAccessGate.withTaskOverrideForTesting(false) {
                            ProviderInteractionContext.current == .userInitiated &&
                                BrowserCookieAccessGate.shouldAttempt(.arc, now: start.addingTimeInterval(1))
                        }
                    }
                }
            }
            #expect(allowed)
        }
    }

    @Test
    func timed_out_cookie_cache_work_stays_ordered_before_retry() async throws {
        let log = CookieOperationLog()
        let firstOperationStarted = DispatchSemaphore(value: 0)
        let allowFirstOperationToFinish = DispatchSemaphore(value: 0)

        do {
            _ = try await OpenAIDashboardBrowserCookieImporter.runBoundedCookieCacheOperation(
                deadline: Date().addingTimeInterval(0.05))
            {
                log.append("first-start")
                firstOperationStarted.signal()
                _ = allowFirstOperationToFinish.wait(timeout: .now() + 5)
                log.append("first-end")
                return true
            }
            Issue.record("Expected first cache operation timeout")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        let firstOperationStartResult = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: firstOperationStarted.wait(timeout: .now() + 5))
            }
        }
        #expect(firstOperationStartResult == .success)
        do {
            _ = try await OpenAIDashboardBrowserCookieImporter.runBoundedCookieCacheOperation(
                deadline: Date().addingTimeInterval(0.05))
            {
                log.append("second")
                return true
            }
            Issue.record("Expected retry to wait behind first cache operation")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        allowFirstOperationToFinish.signal()

        _ = try await OpenAIDashboardBrowserCookieImporter.runBoundedCookieCacheOperation(
            deadline: Date().addingTimeInterval(1)) { true }
        #expect(log.snapshot == ["first-start", "first-end", "second"])
    }

    @Test @MainActor
    func slow_callback_times_out_before_completion() async throws {
        let start = Date()
        let timeoutProbe = CookieTimeoutProbe()

        do {
            try await OpenAIDashboardBrowserCookieImporter.runBoundedCallback(
                deadline: start.addingTimeInterval(0.05),
                timeoutObserver: timeoutProbe.record)
            { completion in
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) {
                    completion()
                }
            }
            Issue.record("Expected callback timeout")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        let firedAt = try #require(timeoutProbe.firedAt)
        #expect(firedAt.timeIntervalSince(start) < 0.3)
    }

    @Test @MainActor
    func slow_value_callback_times_out_before_completion() async throws {
        let start = Date()
        let timeoutProbe = CookieTimeoutProbe()

        do {
            let _: [String] = try await OpenAIDashboardBrowserCookieImporter.runBoundedValueCallback(
                deadline: start.addingTimeInterval(0.05),
                timeoutObserver: timeoutProbe.record)
            { completion in
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) {
                    completion([])
                }
            }
            Issue.record("Expected value callback timeout")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        let firedAt = try #require(timeoutProbe.firedAt)
        #expect(firedAt.timeIntervalSince(start) < 0.3)
    }

    @Test @MainActor
    func retry_waits_for_timed_out_cookie_store_mutation() async throws {
        let keyOwner = NSObject()
        let key = ObjectIdentifier(keyOwner)
        let first = CookieCallbackHarness()

        do {
            try await OpenAIDashboardBrowserCookieImporter.runSerializedCallback(
                key: key,
                deadline: Date().addingTimeInterval(0.05),
                start: first.capture)
            Issue.record("Expected first mutation timeout")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        }

        let secondStarted = CookieCallbackFlag()
        let second = Task { @MainActor in
            try await OpenAIDashboardBrowserCookieImporter.runSerializedCallback(
                key: key,
                deadline: Date().addingTimeInterval(1))
            { completion in
                secondStarted.set()
                completion()
            }
        }

        try await Task.sleep(for: .milliseconds(50))
        #expect(!secondStarted.value)
        first.finish()
        try await second.value
        #expect(secondStarted.value)
    }

    @Test
    func mismatch_error_mentions_source_label() {
        let err = OpenAIDashboardBrowserCookieImporter.ImportError.noMatchingAccount(
            found: [
                .init(sourceLabel: "Safari", email: "a@example.com"),
                .init(sourceLabel: "Chrome", email: "b@example.com"),
            ])
        let msg = err.localizedDescription
        #expect(msg.contains("Safari=a@example.com"))
        #expect(msg.contains("Chrome=b@example.com"))
    }

    @Test
    func timed_out_persistent_validation_keeps_verified_session() {
        let failure = OpenAIDashboardBrowserCookieImporter.persistentValidationFailure(URLError(.timedOut))
        #expect(OpenAIDashboardBrowserCookieImporter.shouldTrustVerifiedSession(
            afterPersistFailure: failure))
    }

    @Test
    func raw_cookie_mutation_timeout_is_not_trusted() {
        #expect(!OpenAIDashboardBrowserCookieImporter.shouldTrustVerifiedSession(
            afterPersistFailure: URLError(.timedOut)))
    }

    @Test
    func non_timeout_persistent_validation_failures_are_not_trusted() {
        #expect(!OpenAIDashboardBrowserCookieImporter.shouldTrustVerifiedSession(
            afterPersistFailure: OpenAIDashboardBrowserCookieImporter.ImportError.dashboardStillRequiresLogin))
    }
}
