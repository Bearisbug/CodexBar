import Foundation
import Testing
@testable import CodexBarCore

struct OpenAIAPICreditBalanceTests {
    private func makeContext(
        apiKey: String = "sk-test",
        usesAdminKey: Bool = false,
        projectID: String? = nil,
        selectedTokenAccountID: UUID? = nil,
        historyDays: Int = 30) -> ProviderFetchContext
    {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        let apiKeyEnvironmentKey = usesAdminKey
            ? OpenAIAPISettingsReader.adminAPIKeyEnvironmentKey
            : OpenAIAPISettingsReader.apiKeyEnvironmentKey
        var env = [apiKeyEnvironmentKey: apiKey]
        if let projectID {
            env[OpenAIAPISettingsReader.projectIDEnvironmentKey] = projectID
        }
        return ProviderFetchContext(
            runtime: .app,
            sourceMode: .api,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: nil,
            fetcher: UsageFetcher(environment: env),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection,
            selectedTokenAccountID: selectedTokenAccountID,
            costUsageHistoryDays: historyDays)
    }

    @Test
    func prefers_admin_key_environment_variable() {
        let token = OpenAIAPISettingsReader.apiKey(environment: [
            "OPENAI_API_KEY": "sk-project",
            "OPENAI_ADMIN_KEY": "sk-admin",
        ])

        #expect(token == "sk-admin")
    }

    @Test
    func parses_credit_grants_balance() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        {
          "object": "credit_summary",
          "total_granted": 25.5,
          "total_used": 7.25,
          "total_available": 18.25,
          "grants": {
            "object": "list",
            "data": [
              {
                "grant_amount": 10.0,
                "used_amount": 1.0,
                "effective_at": 1690000000,
                "expires_at": 1800000000
              }
            ]
          }
        }
        """

        let snapshot = try OpenAIAPICreditBalanceFetcher._parseSnapshotForTesting(Data(json.utf8), now: now)

        #expect(snapshot.totalGranted == 25.5)
        #expect(snapshot.totalUsed == 7.25)
        #expect(snapshot.totalAvailable == 18.25)
        #expect(snapshot.nextGrantExpiry == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test
    func maps_balance_to_usage_snapshot() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let balance = OpenAIAPICreditBalanceSnapshot(
            totalGranted: 100,
            totalUsed: 40,
            totalAvailable: 60,
            nextGrantExpiry: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: now)

        let usage = balance.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 40)
        #expect(usage.primary?.resetDescription == "$60.00 available")
        #expect(usage.providerCost?.used == 40)
        #expect(usage.providerCost?.limit == 100)
        #expect(usage.identity?.providerID == .openai)
        #expect(usage.identity?.loginMethod == "API balance: $60.00")
    }

    @Test
    func maps_unauthorized_legacy_balance_to_admin_key_guidance() async {
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil)!
            return (Data("{}".utf8), response)
        }

        do {
            _ = try await OpenAIAPICreditBalanceFetcher.fetchBalance(
                apiKey: "sk-test",
                session: transport)
            Issue.record("Expected credential rejection")
        } catch let error as OpenAIAPICreditBalanceError {
            #expect(error == .unauthorized)
            #expect(error.errorDescription?.contains("organization Admin API key") == true)
            #expect(error.errorDescription?.contains("service-account keys") == true)
        } catch {
            Issue.record("Expected OpenAIAPICreditBalanceError, got \(error)")
        }
    }

    @Test
    func falls_back_to_legacy_billing_when_admin_usage_rejects_credentials() async throws {
        let strategy = OpenAIAPIBalanceFetchStrategy(
            usageFetcher: { _, _ in
                throw OpenAIAPIUsageError.apiError(endpoint: "costs", statusCode: 403)
            },
            balanceFetcher: { _ in
                OpenAIAPICreditBalanceSnapshot(
                    totalGranted: 100,
                    totalUsed: 25,
                    totalAvailable: 75,
                    nextGrantExpiry: nil,
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
            })

        let result = try await strategy.fetch(self.makeContext())

        #expect(result.sourceLabel == "billing-api")
        #expect(result.usage.identity?.loginMethod == "API balance: $75.00")
    }

    @Test
    func legacy_API_key_without_project_ID_falls_back_to_legacy_billing() async throws {
        let strategy = OpenAIAPIBalanceFetchStrategy(
            usageFetcher: { credential, historyDays in
                #expect(credential.apiKey == "sk-test")
                #expect(credential.projectID == nil)
                #expect(historyDays == 30)
                throw OpenAIAPIUsageError.apiError(endpoint: "costs", statusCode: 403)
            },
            balanceFetcher: { apiKey in
                #expect(apiKey == "sk-test")
                return OpenAIAPICreditBalanceSnapshot(
                    totalGranted: 100,
                    totalUsed: 25,
                    totalAvailable: 75,
                    nextGrantExpiry: nil,
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
            })

        let result = try await strategy.fetch(self.makeContext())

        #expect(result.sourceLabel == "billing-api")
        #expect(result.usage.identity?.loginMethod == "API balance: $75.00")
        #expect(result.usage.identity?.accountOrganization == nil)
    }

    @Test
    func selected_token_account_uses_scrubbed_final_environment_for_legacy_fallback() async throws {
        let accountID = UUID()
        let strategy = OpenAIAPIBalanceFetchStrategy(
            usageFetcher: { credential, historyDays in
                #expect(credential.apiKey == "account-token")
                #expect(credential.projectID == nil)
                #expect(historyDays == 30)
                throw OpenAIAPIUsageError.apiError(endpoint: "costs", statusCode: 403)
            },
            balanceFetcher: { apiKey in
                #expect(apiKey == "account-token")
                return OpenAIAPICreditBalanceSnapshot(
                    totalGranted: 100,
                    totalUsed: 25,
                    totalAvailable: 75,
                    nextGrantExpiry: nil,
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
            })

        let result = try await strategy.fetch(self.makeContext(
            apiKey: "account-token",
            usesAdminKey: true,
            selectedTokenAccountID: accountID))

        #expect(result.sourceLabel == "billing-api")
        #expect(result.usage.identity?.loginMethod == "API balance: $75.00")
        #expect(result.usage.identity?.accountOrganization == nil)
    }

    @Test
    func preserves_admin_usage_error_when_legacy_fallback_also_fails() async {
        let usageFailure = OpenAIAPIUsageError.parseFailed(endpoint: "costs", message: "changed")
        let strategy = OpenAIAPIBalanceFetchStrategy(
            usageFetcher: { _, _ in throw usageFailure },
            balanceFetcher: { _ in throw OpenAIAPICreditBalanceError.forbidden })

        do {
            _ = try await strategy.fetch(self.makeContext())
            Issue.record("Expected admin usage failure")
        } catch let error as OpenAIAPIUsageError {
            #expect(error == usageFailure)
        } catch {
            Issue.record("Expected OpenAIAPIUsageError, got \(error)")
        }
    }

    @Test
    func falls_back_to_credit_balance_when_admin_usage_endpoint_is_unavailable() async throws {
        let strategy = OpenAIAPIBalanceFetchStrategy(
            usageFetcher: { credential, historyDays in
                #expect(credential.apiKey == "sk-test")
                #expect(credential.projectID == nil)
                #expect(historyDays == 90)
                throw OpenAIAPIUsageError.apiError(endpoint: "costs", statusCode: 500)
            },
            balanceFetcher: { apiKey in
                #expect(apiKey == "sk-test")
                return OpenAIAPICreditBalanceSnapshot(
                    totalGranted: 100,
                    totalUsed: 25,
                    totalAvailable: 75,
                    nextGrantExpiry: nil,
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
            })

        let result = try await strategy.fetch(self.makeContext(historyDays: 90))

        #expect(result.sourceLabel == "billing-api")
        #expect(result.usage.providerCost?.used == 25)
        #expect(result.usage.providerCost?.limit == 100)
    }
}
