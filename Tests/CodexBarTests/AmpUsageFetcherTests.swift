import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct AmpUsageFetcherTests {
    private func makeContext(
        sourceMode: ProviderSourceMode,
        env: [String: String] = [:]) -> ProviderFetchContext
    {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        return ProviderFetchContext(
            runtime: .app,
            sourceMode: sourceMode,
            includeCredits: true,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: nil,
            fetcher: UsageFetcher(),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection)
    }

    @Test
    func uses_amp_internal_usage_endpoint() {
        #expect(
            AmpUsageFetcher.usageURL.absoluteString ==
                "https://ampcode.com/api/internal?userDisplayBalanceInfo")
    }

    @Test
    func provider_dashboard_points_to_current_usage_page() {
        #expect(AmpProviderDescriptor.descriptor.metadata.dashboardURL == "https://ampcode.com/settings/usage")
    }

    @Test
    func web_fallback_requires_browser_import_or_a_manual_session_cookie() {
        let disabled = ProviderSettingsSnapshot.AmpProviderSettings(cookieSource: .off, manualCookieHeader: nil)
        let invalidManual = ProviderSettingsSnapshot.AmpProviderSettings(
            cookieSource: .manual,
            manualCookieHeader: "other=value")
        let validManual = ProviderSettingsSnapshot.AmpProviderSettings(
            cookieSource: .manual,
            manualCookieHeader: "session=test")

        #expect(AmpStatusFetchStrategy.canUseWebFallback(
            settings: nil,
            canImportBrowserCookies: false) == false)
        #expect(AmpStatusFetchStrategy.canUseWebFallback(
            settings: nil,
            canImportBrowserCookies: true))
        #expect(AmpStatusFetchStrategy.canUseWebFallback(
            settings: disabled,
            canImportBrowserCookies: true) == false)
        #expect(AmpStatusFetchStrategy.canUseWebFallback(
            settings: invalidManual,
            canImportBrowserCookies: false) == false)
        #expect(AmpStatusFetchStrategy.canUseWebFallback(
            settings: validManual,
            canImportBrowserCookies: false))
    }

    @Test
    func cli_cancellation_does_not_fall_back_to_web() {
        let strategy = AmpCLIFetchStrategy()
        let context = self.makeContext(sourceMode: .auto)

        #expect(!strategy.shouldFallback(on: CancellationError(), context: context))
        #expect(!strategy.shouldFallback(on: URLError(.cancelled), context: context))
        #expect(strategy.shouldFallback(on: AmpUsageError.parseFailed("missing"), context: context))
        #expect(!strategy.shouldFallback(
            on: AmpUsageError.parseFailed("missing"),
            context: self.makeContext(sourceMode: .cli)))
    }

    @Test
    func api_request_uses_bearer_token_without_cookies() throws {
        let request = try AmpUsageFetcher.makeUsageAPIRequest(apiToken: "sgamp_test")

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sgamp_test")
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test
    func api_strategy_falls_back_only_from_auto_mode_and_preserves_cancellation() {
        let strategy = AmpAPIFetchStrategy()
        let auto = self.makeContext(sourceMode: .auto)

        #expect(strategy.shouldFallback(on: AmpUsageError.missingAPIToken, context: auto))
        #expect(strategy.shouldFallback(on: AmpUsageError.invalidAPIToken, context: auto))
        #expect(strategy.shouldFallback(on: URLError(.timedOut), context: auto))
        #expect(!strategy.shouldFallback(on: CancellationError(), context: auto))
        #expect(!strategy.shouldFallback(on: URLError(.cancelled), context: auto))
        #expect(!strategy.shouldFallback(
            on: AmpUsageError.invalidAPIToken,
            context: self.makeContext(sourceMode: .api)))
    }

    @Test
    func amp_config_token_resolves_through_environment() {
        let env = [AmpSettingsReader.apiTokenKey: " 'sgamp_test' "]

        #expect(ProviderTokenResolver.ampToken(environment: env) == "sgamp_test")
    }

    @Test
    func attaches_cookie_for_amp_hosts() {
        #expect(AmpUsageFetcher.shouldAttachCookie(to: URL(string: "https://ampcode.com/settings")))
        #expect(AmpUsageFetcher.shouldAttachCookie(to: URL(string: "https://www.ampcode.com")))
        #expect(AmpUsageFetcher.shouldAttachCookie(to: URL(string: "https://app.ampcode.com/path")))
    }

    @Test
    func rejects_non_amp_hosts() {
        #expect(!AmpUsageFetcher.shouldAttachCookie(to: URL(string: "https://example.com")))
        #expect(!AmpUsageFetcher.shouldAttachCookie(to: URL(string: "https://ampcode.com.evil.com")))
        #expect(!AmpUsageFetcher.shouldAttachCookie(to: nil))
    }

    @Test
    func rejects_non_https_amp_urls() {
        #expect(!AmpUsageFetcher.shouldAttachCookie(to: URL(string: "http://ampcode.com/settings")))
        #expect(!AmpUsageFetcher.shouldAttachCookie(to: URL(string: "http://www.ampcode.com")))
        #expect(!AmpUsageFetcher.shouldAttachCookie(to: URL(string: "http://app.ampcode.com/path")))
    }

    @Test
    func detects_login_redirects() throws {
        let signIn = try #require(URL(string: "https://ampcode.com/auth/sign-in?returnTo=%2Fsettings"))
        #expect(AmpUsageFetcher.isLoginRedirect(signIn))

        let downgradedSignIn = try #require(URL(string: "http://ampcode.com/auth/sign-in?returnTo=%2Fsettings"))
        #expect(AmpUsageFetcher.isLoginRedirect(downgradedSignIn))
        #expect(!AmpUsageFetcher.shouldAttachCookie(to: downgradedSignIn))

        let sso = try #require(URL(string: "https://ampcode.com/auth/sso?returnTo=%2Fsettings"))
        #expect(AmpUsageFetcher.isLoginRedirect(sso))

        let login = try #require(URL(string: "https://ampcode.com/login"))
        #expect(AmpUsageFetcher.isLoginRedirect(login))

        let signin = try #require(URL(string: "https://www.ampcode.com/signin"))
        #expect(AmpUsageFetcher.isLoginRedirect(signin))

        let hostedAuth = try #require(URL(
            string: "https://auth.ampcode.com/?client_id=test&redirect_uri=https%3A%2F%2Fampcode.com%2Fauth%2Fcallback"))
        #expect(AmpUsageFetcher.isLoginRedirect(hostedAuth))
    }

    @Test
    func ignores_non_login_UR_ls() throws {
        let settings = try #require(URL(string: "https://ampcode.com/settings"))
        #expect(!AmpUsageFetcher.isLoginRedirect(settings))

        let signOut = try #require(URL(string: "https://ampcode.com/auth/sign-out"))
        #expect(!AmpUsageFetcher.isLoginRedirect(signOut))

        let evil = try #require(URL(string: "https://ampcode.com.evil.com/auth/sign-in"))
        #expect(!AmpUsageFetcher.isLoginRedirect(evil))
    }

    @Test
    func temporary_API_session_is_finished_after_a_successful_request() async throws {
        defer { AmpStubURLProtocol.handler = nil }
        AmpStubURLProtocol.handler = { request in
            let displayText = "Amp Free: $8/$10 remaining (replenishes +$0.5/hour)"
            let data = try JSONSerialization.data(withJSONObject: [
                "ok": true,
                "result": ["displayText": displayText],
            ])
            return try Self.makeResponse(request: request, data: data)
        }
        let recorder = AmpSessionFinishRecorder()
        let fetcher = self.makeFetcher(recorder: recorder)

        _ = try await fetcher.fetch(apiToken: "test")

        #expect(recorder.count == 1)
    }

    @Test
    func temporary_API_session_is_finished_after_a_transport_failure() async {
        defer { AmpStubURLProtocol.handler = nil }
        AmpStubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let recorder = AmpSessionFinishRecorder()
        let fetcher = self.makeFetcher(recorder: recorder)

        await #expect(throws: URLError.self) {
            _ = try await fetcher.fetch(apiToken: "test")
        }
        #expect(recorder.count == 1)
    }

    @Test
    func temporary_web_session_is_finished_after_a_successful_request() async throws {
        defer { AmpStubURLProtocol.handler = nil }
        AmpStubURLProtocol.handler = { request in
            let html = """
            <script>
            __sveltekit_x.data = {user:{},
            freeTierUsage:{bucket:"ubi",quota:1000,hourlyReplenishment:42,windowHours:24,used:338.5}};
            </script>
            """
            return try Self.makeResponse(request: request, data: Data(html.utf8))
        }
        let recorder = AmpSessionFinishRecorder()
        let fetcher = self.makeFetcher(recorder: recorder)

        _ = try await fetcher.fetch(cookieHeaderOverride: "session=test")

        #expect(recorder.count == 1)
    }

    @Test
    func temporary_web_session_is_finished_after_a_transport_failure() async {
        defer { AmpStubURLProtocol.handler = nil }
        AmpStubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let recorder = AmpSessionFinishRecorder()
        let fetcher = self.makeFetcher(recorder: recorder)

        await #expect(throws: URLError.self) {
            _ = try await fetcher.fetch(cookieHeaderOverride: "session=test")
        }
        #expect(recorder.count == 1)
    }

    private func makeFetcher(recorder: AmpSessionFinishRecorder) -> AmpUsageFetcher {
        AmpUsageFetcher(
            browserDetection: BrowserDetection(cacheTTL: 0),
            makeURLSession: { delegate in
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [AmpStubURLProtocol.self]
                return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            },
            finishURLSession: { session in
                recorder.record(session)
                session.finishTasksAndInvalidate()
            })
    }

    private static func makeResponse(
        request: URLRequest,
        data: Data,
        statusCode: Int = 200) throws -> (HTTPURLResponse, Data)
    {
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]))
        return (response, data)
    }
}

private final class AmpSessionFinishRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [URLSession] = []

    var count: Int {
        self.lock.withLock { self.sessions.count }
    }

    func record(_ session: URLSession) {
        self.lock.withLock {
            self.sessions.append(session)
        }
    }
}

private final class AmpStubURLProtocol: URLProtocol {
    private static let _handlerBox = LockIsolated<((URLRequest) throws -> (HTTPURLResponse, Data))?>(nil)
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { Self._handlerBox.value }
        set { Self._handlerBox.setValue(newValue) }
    }

    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix("ampcode.com") == true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(self.request)
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        } catch {
            self.client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
