import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct OllamaUsageFetcherRetryMappingTests {
    private func makeContext(
        sourceMode: ProviderSourceMode,
        env: [String: String] = [:],
        settings: ProviderSettingsSnapshot? = nil) -> ProviderFetchContext
    {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        return ProviderFetchContext(
            runtime: .cli,
            sourceMode: sourceMode,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: settings,
            fetcher: UsageFetcher(),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection)
    }

    @Test
    func api_key_reader_trims_configured_environment_key() {
        let token = OllamaAPISettingsReader.apiKey(environment: ["OLLAMA_API_KEY": " 'ollama-test' "])

        #expect(token == "ollama-test")
    }

    @Test
    func api_tags_response_maps_to_API_key_identity() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = try OllamaAPIUsageFetcher._parseTagsForTesting(
            Data(#"{"models":[{"name":"gpt-oss:120b"}]}"#.utf8),
            now: now)
        let usage = snapshot.toUsageSnapshot()

        #expect(snapshot.modelCount == 1)
        #expect(usage.primary == nil)
        #expect(usage.identity?.providerID == .ollama)
        #expect(usage.identity?.loginMethod == "API key")
        #expect(usage.updatedAt == now)
    }

    @Test
    func auto_mode_keeps_web_quota_strategy_before_api_key_verification() async {
        let descriptor = OllamaProviderDescriptor.makeDescriptor()
        let context = self.makeContext(
            sourceMode: .auto,
            env: ["OLLAMA_API_KEY": "ollama-test"],
            settings: ProviderSettingsSnapshot.make(
                ollama: .init(cookieSource: .auto, manualCookieHeader: nil)))

        let strategies = await descriptor.fetchPlan.pipeline.resolveStrategies(context)

        #expect(strategies.map(\.id) == ["ollama.web", "ollama.api"])
    }

    @Test
    func auto_mode_uses_api_only_when_ollama_cookies_are_off() async {
        let descriptor = OllamaProviderDescriptor.makeDescriptor()
        let context = self.makeContext(
            sourceMode: .auto,
            env: ["OLLAMA_API_KEY": "ollama-test"],
            settings: ProviderSettingsSnapshot.make(
                ollama: .init(cookieSource: .off, manualCookieHeader: nil)))

        let strategies = await descriptor.fetchPlan.pipeline.resolveStrategies(context)

        #expect(strategies.map(\.id) == ["ollama.api"])
    }

    @Test
    func web_strategy_falls_back_to_api_key_in_auto_mode() {
        let context = self.makeContext(
            sourceMode: .auto,
            env: ["OLLAMA_API_KEY": "ollama-test"])
        let strategy = OllamaStatusFetchStrategy()

        #expect(strategy.shouldFallback(on: OllamaUsageError.parseFailed("missing"), context: context))
    }

    @Test(arguments: [401, 403])
    func api_fetch_sends_bearer_token_and_rejects_unauthorized_key(statusCode: Int) async throws {
        let url = try #require(URL(string: "https://ollama.com/api/web_search"))
        let transport = ProviderHTTPTransportHandler { request in
            #expect(request.url == url)
            #expect(request.httpMethod == "POST")
            #expect(request.httpBody == Data(#"{"query":""}"#.utf8))
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ollama-test")
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil)!
            return (Data("{}".utf8), response)
        }

        do {
            _ = try await OllamaAPIUsageFetcher.fetchUsage(apiKey: "ollama-test", transport: transport)
            Issue.record("Expected unauthorized API error")
        } catch let error as OllamaUsageError {
            guard case .apiUnauthorized = error else {
                Issue.record("Expected apiUnauthorized, got \(error)")
                return
            }
            #expect(error.localizedDescription == "Ollama API key is invalid or revoked.")
        } catch {
            Issue.record("Expected OllamaUsageError.apiUnauthorized, got \(error)")
        }
    }

    @Test
    func authorized_validation_continues_to_model_catalog() async throws {
        let validationURL = try #require(URL(string: "https://ollama.test/api/web_search"))
        let tagsURL = try #require(URL(string: "https://ollama.test/api/tags"))
        let transport = ProviderHTTPTransportHandler { request in
            let statusCode: Int
            let data: Data
            switch request.url {
            case validationURL:
                statusCode = 400
                data = Data(#"{"error":"query is required"}"#.utf8)
            case tagsURL:
                statusCode = 200
                data = Data(#"{"models":[{}]}"#.utf8)
            default:
                Issue.record("Unexpected Ollama API URL")
                statusCode = 500
                data = Data()
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil)!
            return (data, response)
        }

        let snapshot = try await OllamaAPIUsageFetcher.fetchUsage(
            apiKey: "ollama-test",
            tagsURL: tagsURL,
            validationURL: validationURL,
            transport: transport)

        #expect(snapshot.modelCount == 1)
    }

    @Test(arguments: [401, 403])
    func authorized_validation_still_rejects_unauthorized_model_catalog(statusCode: Int) async throws {
        let validationURL = try #require(URL(string: "https://ollama.test/api/web_search"))
        let tagsURL = try #require(URL(string: "https://ollama.test/api/tags"))
        let transport = ProviderHTTPTransportHandler { request in
            let responseStatus = request.url == validationURL ? 400 : statusCode
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: responseStatus,
                httpVersion: "HTTP/1.1",
                headerFields: nil)!
            return (Data("{}".utf8), response)
        }

        do {
            _ = try await OllamaAPIUsageFetcher.fetchUsage(
                apiKey: "ollama-test",
                tagsURL: tagsURL,
                validationURL: validationURL,
                transport: transport)
            Issue.record("Expected unauthorized model catalog error")
        } catch let error as OllamaUsageError {
            guard case .apiUnauthorized = error else {
                Issue.record("Expected apiUnauthorized, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected OllamaUsageError.apiUnauthorized, got \(error)")
        }
    }

    @Test
    func custom_catalog_derives_validation_on_the_same_origin() async throws {
        let tagsURL = try #require(URL(string: "https://private.example/prefix/api/tags"))
        let validationURL = try #require(URL(string: "https://private.example/prefix/api/web_search"))
        let transport = ProviderHTTPTransportHandler { request in
            let statusCode: Int
            let data: Data
            switch request.url {
            case validationURL:
                statusCode = 400
                data = Data(#"{"error":"query is required"}"#.utf8)
            case tagsURL:
                statusCode = 200
                data = Data(#"{"models":[{}]}"#.utf8)
            default:
                Issue.record("Unexpected Ollama API URL")
                statusCode = 500
                data = Data()
            }
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer private-key")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil)!
            return (data, response)
        }

        let snapshot = try await OllamaAPIUsageFetcher.fetchUsage(
            apiKey: "private-key",
            tagsURL: tagsURL,
            transport: transport)

        #expect(snapshot.modelCount == 1)
    }

    @Test
    func cross_origin_validation_endpoint_is_rejected_before_sending_credentials() async throws {
        let tagsURL = try #require(URL(string: "https://private.example/api/tags"))
        let validationURL = try #require(URL(string: "https://ollama.com/api/web_search"))
        let transport = ProviderHTTPTransportHandler { _ in
            Issue.record("Cross-origin endpoints must fail before transport")
            throw URLError(.badURL)
        }

        do {
            _ = try await OllamaAPIUsageFetcher.fetchUsage(
                apiKey: "private-key",
                tagsURL: tagsURL,
                validationURL: validationURL,
                transport: transport)
            Issue.record("Expected a same-origin validation error")
        } catch let error as OllamaUsageError {
            guard case let .networkError(message) = error else {
                Issue.record("Expected networkError, got \(error)")
                return
            }
            #expect(message == "Ollama key validation and model catalog endpoints must share an origin.")
        } catch {
            Issue.record("Expected OllamaUsageError.networkError, got \(error)")
        }
    }

    @Test
    func non_loopback_HTTP_catalog_is_rejected_before_sending_credentials() async throws {
        let tagsURL = try #require(URL(string: "http://private.example/api/tags"))
        let transport = ProviderHTTPTransportHandler { _ in
            Issue.record("Insecure non-loopback endpoints must fail before transport")
            throw URLError(.badURL)
        }

        do {
            _ = try await OllamaAPIUsageFetcher.fetchUsage(
                apiKey: "private-key",
                tagsURL: tagsURL,
                transport: transport)
            Issue.record("Expected an insecure endpoint error")
        } catch let error as OllamaUsageError {
            guard case let .networkError(message) = error else {
                Issue.record("Expected networkError, got \(error)")
                return
            }
            #expect(message == "Ollama API endpoints must use HTTPS or loopback HTTP.")
        } catch {
            Issue.record("Expected OllamaUsageError.networkError, got \(error)")
        }
    }

    @Test
    func api_validation_preserves_cancellation() async {
        let transport = ProviderHTTPTransportHandler { _ in
            throw CancellationError()
        }

        await #expect(throws: CancellationError.self) {
            _ = try await OllamaAPIUsageFetcher.fetchUsage(apiKey: "ollama-test", transport: transport)
        }
    }

    @Test
    func model_catalog_fetch_preserves_URL_cancellation() async throws {
        let validationURL = try #require(URL(string: "https://ollama.test/api/web_search"))
        let tagsURL = try #require(URL(string: "https://ollama.test/api/tags"))
        let transport = ProviderHTTPTransportHandler { request in
            guard request.url == validationURL else { throw URLError(.cancelled) }
            let response = HTTPURLResponse(
                url: validationURL,
                statusCode: 400,
                httpVersion: "HTTP/1.1",
                headerFields: nil)!
            return (Data(#"{"error":"query is required"}"#.utf8), response)
        }

        await #expect(throws: CancellationError.self) {
            _ = try await OllamaAPIUsageFetcher.fetchUsage(
                apiKey: "ollama-test",
                tagsURL: tagsURL,
                validationURL: validationURL,
                transport: transport)
        }
    }

    @Test
    func unproven_validation_status_fails_closed() async throws {
        let validationURL = try #require(URL(string: "https://ollama.test/api/web_search"))
        let tagsURL = try #require(URL(string: "https://ollama.test/api/tags"))
        let transport = ProviderHTTPTransportHandler { request in
            #expect(request.url == validationURL)
            let response = HTTPURLResponse(
                url: validationURL,
                statusCode: 422,
                httpVersion: "HTTP/1.1",
                headerFields: nil)!
            return (Data(#"{"error":"unprocessable"}"#.utf8), response)
        }

        do {
            _ = try await OllamaAPIUsageFetcher.fetchUsage(
                apiKey: "ollama-test",
                tagsURL: tagsURL,
                validationURL: validationURL,
                transport: transport)
            Issue.record("Expected an HTTP 422 network error")
        } catch let error as OllamaUsageError {
            guard case let .networkError(message) = error else {
                Issue.record("Expected networkError, got \(error)")
                return
            }
            #expect(message == "HTTP 422")
        } catch {
            Issue.record("Expected OllamaUsageError.networkError, got \(error)")
        }
    }

    @Test
    func missing_usage_shape_surfaces_public_parse_failed_message() async {
        defer { OllamaRetryMappingStubURLProtocol.handler = nil }

        OllamaRetryMappingStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let body = "<html><body>No usage data rendered.</body></html>"
            return Self.makeResponse(url: url, body: body, statusCode: 200)
        }

        let fetcher = self.makeCookieFetcher()
        do {
            _ = try await fetcher.fetch(
                cookieHeaderOverride: "session=test-cookie",
                manualCookieMode: true)
            Issue.record("Expected OllamaUsageError.parseFailed")
        } catch let error as OllamaUsageError {
            guard case let .parseFailed(message) = error else {
                Issue.record("Expected parseFailed, got \(error)")
                return
            }
            #expect(message == "Missing Ollama usage data.")
        } catch {
            Issue.record("Expected OllamaUsageError.parseFailed, got \(error)")
        }
    }

    @Test
    func workos_sign_in_landing_surfaces_invalid_credentials_before_parsing() async throws {
        defer { OllamaRetryMappingStubURLProtocol.handler = nil }

        let landingURL = try #require(URL(
            string: "https://signin.ollama.com/?client_id=test&authorization_session_id=expired"))
        OllamaRetryMappingStubURLProtocol.handler = { request in
            #expect(request.url == URL(string: "https://ollama.com/settings"))
            let body = "<html><body>Sign in to Ollama</body></html>"
            return Self.makeResponse(url: landingURL, body: body, statusCode: 200)
        }

        let fetcher = self.makeCookieFetcher()
        do {
            _ = try await fetcher.fetch(
                cookieHeaderOverride: "session=expired-cookie",
                manualCookieMode: true)
            Issue.record("Expected OllamaUsageError.invalidCredentials")
        } catch let error as OllamaUsageError {
            guard case .invalidCredentials = error else {
                Issue.record("Expected invalidCredentials, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected OllamaUsageError.invalidCredentials, got \(error)")
        }
    }

    @Test
    func workos_sign_in_service_failure_remains_a_network_error() async throws {
        defer { OllamaRetryMappingStubURLProtocol.handler = nil }

        let landingURL = try #require(URL(string: "https://signin.ollama.com/"))
        OllamaRetryMappingStubURLProtocol.handler = { _ in
            Self.makeResponse(url: landingURL, body: "Service unavailable", statusCode: 503)
        }

        let fetcher = self.makeCookieFetcher()
        do {
            _ = try await fetcher.fetch(
                cookieHeaderOverride: "session=expired-cookie",
                manualCookieMode: true)
            Issue.record("Expected OllamaUsageError.networkError")
        } catch let error as OllamaUsageError {
            guard case let .networkError(message) = error else {
                Issue.record("Expected networkError, got \(error)")
                return
            }
            #expect(message == "HTTP 503")
        } catch {
            Issue.record("Expected OllamaUsageError.networkError, got \(error)")
        }
    }

    @Test
    func temporary_session_is_finished_after_a_failed_request() async throws {
        defer { OllamaRetryMappingStubURLProtocol.handler = nil }

        let landingURL = try #require(URL(string: "https://ollama.com/settings"))
        OllamaRetryMappingStubURLProtocol.handler = { _ in
            Self.makeResponse(url: landingURL, body: "Service unavailable", statusCode: 503)
        }
        let recorder = OllamaSessionFinishRecorder()
        let fetcher = self.makeCookieFetcher(finishURLSession: { session in
            recorder.record(session)
            session.finishTasksAndInvalidate()
        })

        do {
            _ = try await fetcher.fetch(
                cookieHeaderOverride: "session=expired-cookie",
                manualCookieMode: true)
            Issue.record("Expected OllamaUsageError.networkError")
        } catch is OllamaUsageError {
            #expect(recorder.count == 1)
        }
    }

    @Test
    func temporary_session_is_finished_after_a_successful_request() async throws {
        defer { OllamaRetryMappingStubURLProtocol.handler = nil }

        OllamaRetryMappingStubURLProtocol.handler = { request in
            let url = try #require(request.url)
            let body = """
            <div>
              <span>Session usage</span>
              <span>1.2% used</span>
              <span>Weekly usage</span>
              <span>3.4% used</span>
            </div>
            """
            return Self.makeResponse(url: url, body: body, statusCode: 200)
        }
        let recorder = OllamaSessionFinishRecorder()
        let fetcher = self.makeCookieFetcher(finishURLSession: { session in
            recorder.record(session)
            session.finishTasksAndInvalidate()
        })

        _ = try await fetcher.fetch(
            cookieHeaderOverride: "session=test-cookie",
            manualCookieMode: true)

        #expect(recorder.count == 1)
    }

    @Test
    func temporary_session_is_finished_after_a_transport_failure() async {
        defer { OllamaRetryMappingStubURLProtocol.handler = nil }

        OllamaRetryMappingStubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let recorder = OllamaSessionFinishRecorder()
        let fetcher = self.makeCookieFetcher(finishURLSession: { session in
            recorder.record(session)
            session.finishTasksAndInvalidate()
        })

        await #expect(throws: URLError.self) {
            _ = try await fetcher.fetch(
                cookieHeaderOverride: "session=test-cookie",
                manualCookieMode: true)
        }
        #expect(recorder.count == 1)
    }

    private func makeCookieFetcher(
        finishURLSession: @escaping @Sendable (URLSession) -> Void = { $0.finishTasksAndInvalidate() })
        -> OllamaUsageFetcher
    {
        OllamaUsageFetcher(
            browserDetection: BrowserDetection(cacheTTL: 0),
            makeURLSession: { delegate in
                let config = URLSessionConfiguration.ephemeral
                config.protocolClasses = [OllamaRetryMappingStubURLProtocol.self]
                return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            },
            finishURLSession: finishURLSession)
    }

    private static func makeResponse(
        url: URL,
        body: String,
        statusCode: Int) -> (HTTPURLResponse, Data)
    {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/html"])!
        return (response, Data(body.utf8))
    }
}

private final class OllamaSessionFinishRecorder: @unchecked Sendable {
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

final class OllamaRetryMappingStubURLProtocol: URLProtocol {
    private static let _handlerBox = LockIsolated<((URLRequest) throws -> (HTTPURLResponse, Data))?>(nil)
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { Self._handlerBox.value }
        set { Self._handlerBox.setValue(newValue) }
    }

    override static func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host?.lowercased() else { return false }
        return host == "ollama.com" || host == "www.ollama.com"
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
