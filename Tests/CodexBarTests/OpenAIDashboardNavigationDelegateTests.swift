import Foundation
import Testing
import WebKit
@testable import CodexBarCore

@Suite(.serialized)
struct OpenAIDashboardNavigationDelegateTests {
    final class DelegateBox: @unchecked Sendable {
        var delegate: NavigationDelegate?
    }

    @MainActor
    private func waitForResult(
        _ result: @escaping () -> Result<Void, Error>?,
        timeout: TimeInterval = NavigationDelegate.postCommitSuccessDelay + 10.0) async -> Result<Void, Error>?
    {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let result = result() { return result }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return result()
    }

    @Test
    func ignores_NSURLErrorCancelled() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        #expect(NavigationDelegate.shouldIgnoreNavigationError(error))
    }

    @Test
    func ignores_WebKit_frame_load_interrupted_by_policy_change() {
        let error = NSError(domain: "WebKitErrorDomain", code: 102)
        #expect(NavigationDelegate.shouldIgnoreNavigationError(error))
    }

    @Test
    func does_not_ignore_non_cancelled_URL_errors() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        #expect(!NavigationDelegate.shouldIgnoreNavigationError(error))
    }

    @MainActor
    @Test
    func cancelled_failure_is_ignored_until_finish() {
        let webView = WKWebView()
        var result: Result<Void, Error>?
        let delegate = NavigationDelegate { result = $0 }

        delegate.webView(webView, didFail: nil, withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        #expect(result == nil)
        delegate.webView(webView, didFinish: nil)

        switch result {
        case .success?:
            #expect(Bool(true))
        default:
            #expect(Bool(false))
        }
    }

    @MainActor
    @Test
    func explicit_cancel_completes_with_cancellation_error() {
        var result: Result<Void, Error>?
        let delegate = NavigationDelegate { result = $0 }

        delegate.cancel()

        switch result {
        case let .failure(error)?:
            #expect(error is CancellationError)
        default:
            #expect(Bool(false))
        }
    }

    @MainActor
    @Test
    func commit_completes_navigation_successfully_after_grace_period() async {
        let webView = WKWebView()
        var result: Result<Void, Error>?
        let box = DelegateBox()
        box.delegate = NavigationDelegate { result = $0 }

        box.delegate?.webView(webView, didCommit: nil)
        #expect(result == nil)

        let completed = await self.waitForResult { result }
        box.delegate = nil

        switch completed {
        case .success?:
            #expect(Bool(true))
        default:
            #expect(Bool(false))
        }
    }

    @MainActor
    @Test
    func post_commit_failure_wins_before_delayed_success() async {
        let webView = WKWebView()
        var result: Result<Void, Error>?
        let box = DelegateBox()
        box.delegate = NavigationDelegate { result = $0 }

        box.delegate?.webView(webView, didCommit: nil)
        let timeout = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        box.delegate?.webView(webView, didFail: nil, withError: timeout)

        let completed = await self.waitForResult { result }
        box.delegate = nil

        switch completed {
        case let .failure(error as NSError)?:
            #expect(error.domain == NSURLErrorDomain)
            #expect(error.code == NSURLErrorTimedOut)
        default:
            #expect(Bool(false))
        }
    }

    @MainActor
    @Test
    func cancelled_provisional_failure_is_ignored_until_real_failure() {
        let webView = WKWebView()
        var result: Result<Void, Error>?
        let delegate = NavigationDelegate { result = $0 }

        delegate.webView(
            webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        #expect(result == nil)

        let timeout = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        delegate.webView(webView, didFailProvisionalNavigation: nil, withError: timeout)

        switch result {
        case let .failure(error as NSError)?:
            #expect(error.domain == NSURLErrorDomain)
            #expect(error.code == NSURLErrorTimedOut)
        default:
            #expect(Bool(false))
        }
    }

    @MainActor
    @Test
    func frame_load_interrupted_provisional_failure_is_ignored_until_finish() {
        let webView = WKWebView()
        var result: Result<Void, Error>?
        let delegate = NavigationDelegate { result = $0 }

        delegate.webView(
            webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: "WebKitErrorDomain", code: 102))
        #expect(result == nil)

        delegate.webView(webView, didFinish: nil)

        switch result {
        case .success?:
            #expect(Bool(true))
        default:
            #expect(Bool(false))
        }
    }

    @Test
    func navigation_timeout_fails_with_timed_out_error() async {
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, Error>, Never>) in
            Task { @MainActor in
                let box = DelegateBox()
                box.delegate = NavigationDelegate { result in
                    continuation.resume(returning: result)
                    box.delegate = nil
                }
                box.delegate?.armTimeout(seconds: 0.01)
            }
        }

        switch result {
        case let .failure(error as URLError):
            #expect(error.code == .timedOut)
        default:
            #expect(Bool(false))
        }
    }
}
