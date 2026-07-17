import CodexBarCore
import Foundation
import Testing

@Suite(.serialized)
struct GeminiStatusProbePlanTests {
    @Test
    func selects_project_id_for_quota_requests() async throws {
        let env = try GeminiTestEnvironment()
        defer { env.cleanup() }
        try env.writeCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiry: Date().addingTimeInterval(3600),
            idToken: nil)

        let expectedProject = "gen-lang-client-123"
        let dataLoader = GeminiAPITestHelpers.dataLoader { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            switch host {
            case "cloudresourcemanager.googleapis.com":
                let json = GeminiAPITestHelpers.jsonData([
                    "projects": [
                        ["projectId": expectedProject],
                    ],
                ])
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 200, body: json)
            case "cloudcode-pa.googleapis.com":
                if url.path == "/v1internal:loadCodeAssist" {
                    return GeminiAPITestHelpers.response(
                        url: url.absoluteString,
                        status: 200,
                        body: GeminiAPITestHelpers.loadCodeAssistFreeTierResponse())
                }
                if url.path != "/v1internal:retrieveUserQuota" {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
                }
                let bodyText = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                if !bodyText.contains(expectedProject) {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 400, body: Data())
                }
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.sampleFlashQuotaResponse())
            default:
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
            }
        }

        let probe = GeminiStatusProbe(timeout: 1, homeDirectory: env.homeURL.path, dataLoader: dataLoader)
        let snapshot = try await probe.fetch()
        #expect(snapshot.modelQuotas.contains { $0.percentLeft == 40 })
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.secondary?.remainingPercent == 40)
        #expect(usage.tertiary == nil)
    }

    @Test
    func prefers_load_code_assist_project_for_quota_requests() async throws {
        let env = try GeminiTestEnvironment()
        defer { env.cleanup() }
        try env.writeCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiry: Date().addingTimeInterval(3600),
            idToken: nil)

        let loadCodeAssistProject = "cloudaicompanion-123"
        let fallbackProject = "gen-lang-client-should-not-use"
        let dataLoader = GeminiAPITestHelpers.dataLoader { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            switch host {
            case "cloudresourcemanager.googleapis.com":
                let json = GeminiAPITestHelpers.jsonData([
                    "projects": [
                        ["projectId": fallbackProject],
                    ],
                ])
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 200, body: json)
            case "cloudcode-pa.googleapis.com":
                if url.path == "/v1internal:loadCodeAssist" {
                    return GeminiAPITestHelpers.response(
                        url: url.absoluteString,
                        status: 200,
                        body: GeminiAPITestHelpers.loadCodeAssistResponse(
                            tierId: "free-tier",
                            projectId: loadCodeAssistProject))
                }
                if url.path != "/v1internal:retrieveUserQuota" {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
                }
                let bodyText = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                if !bodyText.contains(loadCodeAssistProject) {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 400, body: Data())
                }
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.sampleFlashQuotaResponse())
            default:
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
            }
        }

        let probe = GeminiStatusProbe(timeout: 1, homeDirectory: env.homeURL.path, dataLoader: dataLoader)
        let snapshot = try await probe.fetch()
        #expect(snapshot.modelQuotas.contains { $0.percentLeft == 40 })
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.secondary?.remainingPercent == 40)
        #expect(usage.tertiary == nil)
    }

    @Test
    func separates_flash_and_flash_lite_quota_buckets_from_api_response() async throws {
        let env = try GeminiTestEnvironment()
        defer { env.cleanup() }
        try env.writeCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiry: Date().addingTimeInterval(3600),
            idToken: nil)

        let dataLoader = GeminiAPITestHelpers.dataLoader { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            switch host {
            case "cloudresourcemanager.googleapis.com":
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.jsonData(["projects": []]))
            case "cloudcode-pa.googleapis.com":
                if url.path == "/v1internal:loadCodeAssist" {
                    return GeminiAPITestHelpers.response(
                        url: url.absoluteString,
                        status: 200,
                        body: GeminiAPITestHelpers.loadCodeAssistStandardTierResponse())
                }
                if url.path != "/v1internal:retrieveUserQuota" {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
                }
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.sampleQuotaResponse())
            default:
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
            }
        }

        let probe = GeminiStatusProbe(timeout: 1, homeDirectory: env.homeURL.path, dataLoader: dataLoader)
        let snapshot = try await probe.fetch()
        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.remainingPercent == 60.0)
        #expect(usage.secondary?.remainingPercent == 90.0)
        #expect(usage.tertiary?.remainingPercent == 80.0)
    }

    @Test
    func detects_paid_from_standard_tier() async throws {
        let env = try GeminiTestEnvironment()
        defer { env.cleanup() }
        try env.writeCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiry: Date().addingTimeInterval(3600),
            idToken: nil)

        let dataLoader = GeminiAPITestHelpers.dataLoader { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            switch host {
            case "cloudresourcemanager.googleapis.com":
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.jsonData(["projects": []]))
            case "cloudcode-pa.googleapis.com":
                if url.path == "/v1internal:loadCodeAssist" {
                    return GeminiAPITestHelpers.response(
                        url: url.absoluteString,
                        status: 200,
                        body: GeminiAPITestHelpers.loadCodeAssistStandardTierResponse())
                }
                if url.path != "/v1internal:retrieveUserQuota" {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
                }
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.sampleQuotaResponse())
            default:
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
            }
        }

        let probe = GeminiStatusProbe(timeout: 1, homeDirectory: env.homeURL.path, dataLoader: dataLoader)
        let snapshot = try await probe.fetch()
        #expect(snapshot.accountPlan == "Paid")
    }

    @Test
    func detects_workspace_from_free_tier_with_hosted_domain() async throws {
        let env = try GeminiTestEnvironment()
        defer { env.cleanup() }
        let idToken = GeminiAPITestHelpers.makeIDToken(email: "user@company.com", hostedDomain: "company.com")
        try env.writeCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiry: Date().addingTimeInterval(3600),
            idToken: idToken)

        let dataLoader = GeminiAPITestHelpers.dataLoader { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            switch host {
            case "cloudresourcemanager.googleapis.com":
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.jsonData(["projects": []]))
            case "cloudcode-pa.googleapis.com":
                if url.path == "/v1internal:loadCodeAssist" {
                    return GeminiAPITestHelpers.response(
                        url: url.absoluteString,
                        status: 200,
                        body: GeminiAPITestHelpers.loadCodeAssistFreeTierResponse())
                }
                if url.path != "/v1internal:retrieveUserQuota" {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
                }
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.sampleQuotaResponse())
            default:
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
            }
        }

        let probe = GeminiStatusProbe(timeout: 1, homeDirectory: env.homeURL.path, dataLoader: dataLoader)
        let snapshot = try await probe.fetch()
        #expect(snapshot.accountPlan == "Workspace")
    }

    @Test
    func detects_consumer_plus_from_free_tier_with_paid_tier_name() async throws {
        let env = try GeminiTestEnvironment()
        defer { env.cleanup() }
        let idToken = GeminiAPITestHelpers.makeIDToken(email: "user@gmail.com")
        try env.writeCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiry: Date().addingTimeInterval(3600),
            idToken: idToken)

        let dataLoader = GeminiAPITestHelpers.dataLoader { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            switch host {
            case "cloudresourcemanager.googleapis.com":
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.jsonData(["projects": []]))
            case "cloudcode-pa.googleapis.com":
                if url.path == "/v1internal:loadCodeAssist" {
                    return GeminiAPITestHelpers.response(
                        url: url.absoluteString,
                        status: 200,
                        body: GeminiAPITestHelpers.loadCodeAssistConsumerPlusResponse())
                }
                if url.path != "/v1internal:retrieveUserQuota" {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
                }
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.sampleQuotaResponse())
            default:
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
            }
        }

        let probe = GeminiStatusProbe(timeout: 1, homeDirectory: env.homeURL.path, dataLoader: dataLoader)
        let snapshot = try await probe.fetch()
        #expect(snapshot.accountPlan == "Plus")
    }

    @Test
    func uses_paid_tier_name_for_standard_tier_subscriptions() async throws {
        let env = try GeminiTestEnvironment()
        defer { env.cleanup() }
        try env.writeCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiry: Date().addingTimeInterval(3600),
            idToken: nil)

        let dataLoader = GeminiAPITestHelpers.dataLoader { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            switch host {
            case "cloudresourcemanager.googleapis.com":
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.jsonData(["projects": []]))
            case "cloudcode-pa.googleapis.com":
                if url.path == "/v1internal:loadCodeAssist" {
                    return GeminiAPITestHelpers.response(
                        url: url.absoluteString,
                        status: 200,
                        body: GeminiAPITestHelpers.loadCodeAssistGoogleOneProResponse())
                }
                if url.path != "/v1internal:retrieveUserQuota" {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
                }
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.sampleQuotaResponse())
            default:
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
            }
        }

        let probe = GeminiStatusProbe(timeout: 1, homeDirectory: env.homeURL.path, dataLoader: dataLoader)
        let snapshot = try await probe.fetch()
        #expect(snapshot.accountPlan == "Gemini Code Assist in Google One AI Pro")
    }

    @Test
    func paid_tier_name_overrides_workspace_fallback() async throws {
        let plan = try await Self.fetchPlan(
            tierId: "free-tier",
            hostedDomain: "example.com",
            paidTierName: "Plus")

        #expect(plan == "Plus")
    }

    @Test
    func paid_tier_name_survives_unknown_current_tier() async throws {
        let plan = try await Self.fetchPlan(
            tierId: "future-tier",
            hostedDomain: nil,
            paidTierName: "Gemini Code Assist in Google One AI Pro")

        #expect(plan == "Gemini Code Assist in Google One AI Pro")
    }

    @Test
    func paid_tier_name_survives_missing_current_tier() async throws {
        let plan = try await Self.fetchPlan(
            tierId: nil,
            hostedDomain: nil,
            paidTierName: "Plus")

        #expect(plan == "Plus")
    }

    @Test
    func detects_free_from_free_tier_without_hosted_domain() async throws {
        let env = try GeminiTestEnvironment()
        defer { env.cleanup() }
        let idToken = GeminiAPITestHelpers.makeIDToken(email: "user@gmail.com")
        try env.writeCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiry: Date().addingTimeInterval(3600),
            idToken: idToken)

        let dataLoader = GeminiAPITestHelpers.dataLoader { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            switch host {
            case "cloudresourcemanager.googleapis.com":
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.jsonData(["projects": []]))
            case "cloudcode-pa.googleapis.com":
                if url.path == "/v1internal:loadCodeAssist" {
                    return GeminiAPITestHelpers.response(
                        url: url.absoluteString,
                        status: 200,
                        body: GeminiAPITestHelpers.loadCodeAssistFreeTierResponse())
                }
                if url.path != "/v1internal:retrieveUserQuota" {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
                }
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.sampleFlashQuotaResponse())
            default:
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
            }
        }

        let probe = GeminiStatusProbe(timeout: 1, homeDirectory: env.homeURL.path, dataLoader: dataLoader)
        let snapshot = try await probe.fetch()
        #expect(snapshot.accountPlan == "Free")
    }

    @Test
    func detects_legacy_from_legacy_tier() async throws {
        let env = try GeminiTestEnvironment()
        defer { env.cleanup() }
        try env.writeCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiry: Date().addingTimeInterval(3600),
            idToken: nil)

        let dataLoader = GeminiAPITestHelpers.dataLoader { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            switch host {
            case "cloudresourcemanager.googleapis.com":
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.jsonData(["projects": []]))
            case "cloudcode-pa.googleapis.com":
                if url.path == "/v1internal:loadCodeAssist" {
                    return GeminiAPITestHelpers.response(
                        url: url.absoluteString,
                        status: 200,
                        body: GeminiAPITestHelpers.loadCodeAssistLegacyTierResponse())
                }
                if url.path != "/v1internal:retrieveUserQuota" {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
                }
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.sampleQuotaResponse())
            default:
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
            }
        }

        let probe = GeminiStatusProbe(timeout: 1, homeDirectory: env.homeURL.path, dataLoader: dataLoader)
        let snapshot = try await probe.fetch()
        #expect(snapshot.accountPlan == "Legacy")
    }

    @Test
    func leaves_blank_when_load_code_assist_fails() async throws {
        let env = try GeminiTestEnvironment()
        defer { env.cleanup() }
        try env.writeCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiry: Date().addingTimeInterval(3600),
            idToken: nil)

        let dataLoader = GeminiAPITestHelpers.dataLoader { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            switch host {
            case "cloudresourcemanager.googleapis.com":
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.jsonData(["projects": []]))
            case "cloudcode-pa.googleapis.com":
                if url.path == "/v1internal:loadCodeAssist" {
                    return GeminiAPITestHelpers.response(
                        url: url.absoluteString,
                        status: 500,
                        body: Data())
                }
                if url.path != "/v1internal:retrieveUserQuota" {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
                }
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.sampleQuotaResponse())
            default:
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
            }
        }

        let probe = GeminiStatusProbe(timeout: 1, homeDirectory: env.homeURL.path, dataLoader: dataLoader)
        let snapshot = try await probe.fetch()
        #expect(snapshot.accountPlan == nil)
    }

    private static func fetchPlan(
        tierId: String?,
        hostedDomain: String?,
        paidTierName: String) async throws -> String?
    {
        let env = try GeminiTestEnvironment()
        defer { env.cleanup() }
        let idToken = GeminiAPITestHelpers.makeIDToken(
            email: "user@example.com",
            hostedDomain: hostedDomain)
        try env.writeCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiry: Date().addingTimeInterval(3600),
            idToken: idToken)

        let dataLoader = GeminiAPITestHelpers.dataLoader { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            switch host {
            case "cloudresourcemanager.googleapis.com":
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.jsonData(["projects": []]))
            case "cloudcode-pa.googleapis.com":
                if url.path == "/v1internal:loadCodeAssist" {
                    return GeminiAPITestHelpers.response(
                        url: url.absoluteString,
                        status: 200,
                        body: GeminiAPITestHelpers.loadCodeAssistResponse(
                            tierId: tierId,
                            paidTierName: paidTierName))
                }
                if url.path == "/v1internal:retrieveUserQuota" {
                    return GeminiAPITestHelpers.response(
                        url: url.absoluteString,
                        status: 200,
                        body: GeminiAPITestHelpers.sampleQuotaResponse())
                }
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
            default:
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
            }
        }

        let probe = GeminiStatusProbe(timeout: 1, homeDirectory: env.homeURL.path, dataLoader: dataLoader)
        return try await probe.fetch().accountPlan
    }
}
