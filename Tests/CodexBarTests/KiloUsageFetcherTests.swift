import Foundation
import Testing
@testable import CodexBarCore

struct KiloUsageFetcherTests {
    private struct StubClaudeFetcher: ClaudeUsageFetching {
        func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot {
            throw ClaudeUsageError.parseFailed("stub")
        }

        func debugRawProbe(model _: String) async -> String {
            "stub"
        }

        func detectVersion() -> String? {
            nil
        }
    }

    private func makeContext(
        env: [String: String] = [:],
        sourceMode: ProviderSourceMode = .api) -> ProviderFetchContext
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
            settings: nil,
            fetcher: UsageFetcher(environment: env),
            claudeFetcher: StubClaudeFetcher(),
            browserDetection: browserDetection)
    }

    @Test
    func batch_URL_uses_authenticated_TRPC_batch_format() throws {
        let baseURL = try #require(URL(string: "https://kilo.example/trpc"))
        let url = try KiloUsageFetcher._buildBatchURLForTesting(baseURL: baseURL)

        #expect(url.path.contains("user.getCreditBlocks,kiloPass.getState,user.getAutoTopUpPaymentMethod"))

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let batch = components.queryItems?.first(where: { $0.name == "batch" })?.value
        let inputValue = components.queryItems?.first(where: { $0.name == "input" })?.value

        #expect(batch == "1")
        let requiredInput = try #require(inputValue)
        let inputData = Data(requiredInput.utf8)
        let inputObject = try #require(try JSONSerialization.jsonObject(with: inputData) as? [String: Any])
        let first = try #require(inputObject["0"] as? [String: Any])
        let second = try #require(inputObject["1"] as? [String: Any])
        let third = try #require(inputObject["2"] as? [String: Any])

        #expect(inputObject.keys.contains("0"))
        #expect(inputObject.keys.contains("1"))
        #expect(inputObject.keys.contains("2"))
        #expect(first["json"] is NSNull)
        #expect(second["json"] is NSNull)
        #expect(third["json"] is NSNull)
    }

    @Test
    func parse_snapshot_maps_business_fields_and_identity() throws {
        let json = """
        [
          {
            "result": {
              "data": {
                "json": {
                  "blocks": [
                    {
                      "usedCredits": 25,
                      "totalCredits": 100,
                      "remainingCredits": 75
                    }
                  ]
                }
              }
            }
          },
          {
            "result": {
              "data": {
                "json": {
                  "plan": {
                    "name": "Kilo Pass Pro"
                  }
                }
              }
            }
          },
          {
            "result": {
              "data": {
                "json": {
                  "enabled": true,
                  "paymentMethod": "visa"
                }
              }
            }
          }
        ]
        """

        let parsed = try KiloUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let snapshot = parsed.toUsageSnapshot()

        #expect(snapshot.primary?.usedPercent == 25)
        #expect(snapshot.identity?.providerID == .kilo)
        #expect(snapshot.loginMethod(for: .kilo)?.contains("Kilo Pass Pro") == true)
        #expect(snapshot.loginMethod(for: .kilo)?.contains("Auto top-up") == true)
    }

    @Test
    func parse_snapshot_maps_kilo_pass_window_from_subscription_state() throws {
        let json = """
        [
          {
            "result": {
              "data": {
                "creditBlocks": [
                  {
                    "id": "cb-1",
                    "effective_date": "2026-02-01T00:00:00Z",
                    "expiry_date": null,
                    "balance_mUsd": 19000000,
                    "amount_mUsd": 19000000,
                    "is_free": false
                  }
                ],
                "totalBalance_mUsd": 19000000,
                "autoTopUpEnabled": false
              }
            }
          },
          {
            "result": {
              "data": {
                "subscription": {
                  "tier": "tier_19",
                  "currentPeriodUsageUsd": 0,
                  "currentPeriodBaseCreditsUsd": 19.0,
                  "currentPeriodBonusCreditsUsd": 9.5,
                  "nextBillingAt": "2026-03-28T04:00:00.000Z"
                }
              }
            }
          },
          {
            "result": {
              "data": {
                "enabled": false,
                "amountCents": 5000,
                "paymentMethod": null
              }
            }
          }
        ]
        """

        let parsed = try KiloUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let snapshot = parsed.toUsageSnapshot()

        #expect(snapshot.primary?.usedPercent == 0)
        #expect(snapshot.secondary?.usedPercent == 0)
        #expect(snapshot.secondary?.resetsAt != nil)
        #expect(snapshot.secondary?.resetDescription == "$0.00 / $19.00 (+ $9.50 bonus)")
        #expect(snapshot.loginMethod(for: .kilo) == "Starter · Auto top-up: off")
    }

    @Test
    func parse_snapshot_maps_known_tier_names_and_defaults_to_kilo_pass() throws {
        let proTierJSON = """
        [
          { "result": { "data": { "creditBlocks": [], "totalBalance_mUsd": 0, "autoTopUpEnabled": false } } },
          { "result": { "data": { "subscription": { "tier": "tier_49" } } } },
          { "result": { "data": { "enabled": false, "paymentMethod": null } } }
        ]
        """
        let proTierSnapshot = try KiloUsageFetcher._parseSnapshotForTesting(Data(proTierJSON.utf8)).toUsageSnapshot()
        #expect(proTierSnapshot.loginMethod(for: .kilo) == "Pro · Auto top-up: off")

        let noTierJSON = """
        [
          { "result": { "data": { "creditBlocks": [], "totalBalance_mUsd": 0, "autoTopUpEnabled": false } } },
          { "result": { "data": { "subscription": {
            "currentPeriodUsageUsd": 1.0,
            "currentPeriodBaseCreditsUsd": 19.0
          } } } },
          { "result": { "data": { "enabled": false, "paymentMethod": null } } }
        ]
        """
        let noTierSnapshot = try KiloUsageFetcher._parseSnapshotForTesting(Data(noTierJSON.utf8)).toUsageSnapshot()
        #expect(noTierSnapshot.loginMethod(for: .kilo) == "Kilo Pass · Auto top-up: off")
    }

    @Test
    func parse_snapshot_uses_auto_top_up_amount_when_enabled_without_payment_method() throws {
        let json = """
        [
          { "result": { "data": { "creditBlocks": [], "totalBalance_mUsd": 0, "autoTopUpEnabled": true } } },
          { "result": { "data": { "subscription": null } } },
          { "result": { "data": { "enabled": true, "amountCents": 5000, "paymentMethod": null } } }
        ]
        """

        let snapshot = try KiloUsageFetcher._parseSnapshotForTesting(Data(json.utf8)).toUsageSnapshot()
        #expect(snapshot.loginMethod(for: .kilo) == "Auto top-up: $50")
    }

    @Test
    func parse_snapshot_fallback_pass_fields_use_micro_dollar_scale() throws {
        let json = """
        [
          {
            "result": {
              "data": {
                "json": {
                  "blocks": [
                    {
                      "usedCredits": 0,
                      "totalCredits": 19,
                      "remainingCredits": 19
                    }
                  ]
                }
              }
            }
          },
          {
            "result": {
              "data": {
                "json": {
                  "planName": "Starter",
                  "amount_mUsd": 28500000,
                  "used_mUsd": 3500000,
                  "bonus_mUsd": 9500000,
                  "nextRenewalAt": "2026-03-28T04:00:00.000Z"
                }
              }
            }
          },
          {
            "result": {
              "data": {
                "json": {
                  "enabled": false,
                  "paymentMethod": null
                }
              }
            }
          }
        ]
        """

        let snapshot = try KiloUsageFetcher._parseSnapshotForTesting(Data(json.utf8)).toUsageSnapshot()
        #expect(snapshot.secondary?.resetDescription == "$3.50 / $19.00 (+ $9.50 bonus)")
        #expect(snapshot.loginMethod(for: .kilo) == "Starter · Auto top-up: off")
    }

    @Test
    func parse_snapshot_treats_empty_and_null_business_fields_as_no_data_success() throws {
        let json = """
        [
          {
            "result": {
              "data": {
                "json": {
                  "blocks": []
                }
              }
            }
          },
          {
            "result": {
              "data": {
                "json": {
                  "plan": {
                    "name": null
                  }
                }
              }
            }
          },
          {
            "result": {
              "data": {
                "json": {
                  "enabled": null,
                  "paymentMethod": null
                }
              }
            }
          }
        ]
        """

        let parsed = try KiloUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let snapshot = parsed.toUsageSnapshot()

        #expect(snapshot.primary == nil)
        #expect(snapshot.identity?.providerID == .kilo)
        #expect(snapshot.loginMethod(for: .kilo) == nil)
    }

    @Test
    func parse_snapshot_keeps_sparse_indexed_object_routing_by_procedure_index() throws {
        let json = """
        {
          "0": {
            "result": {
              "data": {
                "json": {
                  "creditsUsed": 10,
                  "creditsRemaining": 90
                }
              }
            }
          },
          "2": {
            "result": {
              "data": {
                "json": {
                  "planName": "wrong-route",
                  "enabled": true,
                  "method": "visa"
                }
              }
            }
          }
        }
        """

        let parsed = try KiloUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let snapshot = parsed.toUsageSnapshot()

        #expect(snapshot.primary?.usedPercent == 10)
        #expect(snapshot.loginMethod(for: .kilo) == "Auto top-up: visa")
    }

    @Test
    func parse_snapshot_uses_top_level_credits_used_fallback() throws {
        let json = """
        [
          {
            "result": {
              "data": {
                "json": {
                  "creditsUsed": 40,
                  "creditsRemaining": 60
                }
              }
            }
          }
        ]
        """

        let parsed = try KiloUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let snapshot = parsed.toUsageSnapshot()

        #expect(snapshot.primary?.usedPercent == 40)
        #expect(snapshot.primary?.resetDescription == "40/100 credits")
    }

    @Test
    func parse_snapshot_keeps_zero_total_visible_when_activity_exists() throws {
        let json = """
        [
          {
            "result": {
              "data": {
                "json": {
                  "creditsUsed": 0,
                  "creditsRemaining": 0
                }
              }
            }
          },
          {
            "result": {
              "data": {
                "json": {
                  "planName": "Kilo Pass Pro"
                }
              }
            }
          },
          {
            "result": {
              "data": {
                "json": {
                  "enabled": true,
                  "paymentMethod": "visa"
                }
              }
            }
          }
        ]
        """

        let parsed = try KiloUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let snapshot = parsed.toUsageSnapshot()

        #expect(snapshot.primary?.remainingPercent == 0)
        #expect(snapshot.primary?.usedPercent == 100)
        #expect(snapshot.primary?.resetDescription == "0/0 credits")
        #expect(snapshot.loginMethod(for: .kilo)?.contains("Auto top-up: visa") == true)
    }

    @Test
    func parse_snapshot_treats_zero_balance_without_credit_blocks_as_visible_zero_total() throws {
        let json = """
        [
          {
            "result": {
              "data": {
                "creditBlocks": [],
                "totalBalance_mUsd": 0,
                "isFirstPurchase": true,
                "autoTopUpEnabled": false
              }
            }
          },
          {
            "result": {
              "data": {
                "subscription": null
              }
            }
          },
          {
            "result": {
              "data": {
                "enabled": false,
                "amountCents": 5000,
                "paymentMethod": null
              }
            }
          }
        ]
        """

        let parsed = try KiloUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let snapshot = parsed.toUsageSnapshot()

        #expect(snapshot.primary?.usedPercent == 100)
        #expect(snapshot.primary?.remainingPercent == 0)
        #expect(snapshot.primary?.resetDescription == "0/0 credits")
        #expect(snapshot.loginMethod(for: .kilo) == "Auto top-up: off")
    }

    @Test
    func parse_snapshot_degrades_optional_auto_top_up_TRPC_error() throws {
        let json = """
        [
          {
            "result": {
              "data": {
                "json": {
                  "creditsUsed": 10,
                  "creditsRemaining": 90
                }
              }
            }
          },
          {
            "result": {
              "data": {
                "json": {
                  "planName": "Starter"
                }
              }
            }
          },
          {
            "error": {
              "json": {
                "message": "Internal server error",
                "data": {
                  "code": "INTERNAL_SERVER_ERROR"
                }
              }
            }
          }
        ]
        """

        let parsed = try KiloUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let snapshot = parsed.toUsageSnapshot()

        #expect(snapshot.primary?.usedPercent == 10)
        #expect(snapshot.loginMethod(for: .kilo) == "Starter")
    }

    @Test
    func parse_snapshot_keeps_required_procedure_TRPC_error_fatal() {
        let json = """
        [
          {
            "result": {
              "data": {
                "json": {
                  "creditsUsed": 10,
                  "creditsRemaining": 90
                }
              }
            }
          },
          {
            "error": {
              "json": {
                "message": "Unauthorized",
                "data": {
                  "code": "UNAUTHORIZED"
                }
              }
            }
          }
        ]
        """

        do {
            _ = try KiloUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard let kiloError = error as? KiloUsageError else { return false }
                guard case .unauthorized = kiloError else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func parse_snapshot_maps_unauthorized_TRPC_error() {
        let json = """
        [
          {
            "error": {
              "json": {
                "message": "Unauthorized",
                "data": {
                  "code": "UNAUTHORIZED"
                }
              }
            }
          }
        ]
        """

        do {
            _ = try KiloUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard let kiloError = error as? KiloUsageError else { return false }
                guard case .unauthorized = kiloError else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func parse_snapshot_maps_invalid_JSON_to_parse_error() {
        do {
            _ = try KiloUsageFetcher._parseSnapshotForTesting(Data("not-json".utf8))
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard let kiloError = error as? KiloUsageError else { return false }
                guard case .parseFailed = kiloError else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func status_error_mapping_covers_auth_and_server_failures() {
        #expect(KiloUsageFetcher._statusErrorForTesting(401) == .unauthorized)
        #expect(KiloUsageFetcher._statusErrorForTesting(403) == .unauthorized)
        #expect(KiloUsageFetcher._statusErrorForTesting(404) == .endpointNotFound)

        guard let serviceError = KiloUsageFetcher._statusErrorForTesting(503) else {
            Issue.record("Expected service unavailable mapping")
            return
        }
        guard case let .serviceUnavailable(statusCode) = serviceError else {
            Issue.record("Expected service unavailable mapping")
            return
        }
        #expect(statusCode == 503)
    }

    @Test
    func fetch_usage_without_credentials_fails_fast() async {
        await #expect(throws: KiloUsageError.missingCredentials) {
            _ = try await KiloUsageFetcher.fetchUsage(apiKey: "  ", environment: [:])
        }
    }

    @Test
    func descriptor_fetch_outcome_without_credentials_returns_actionable_error() async {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .kilo)
        let outcome = await descriptor.fetchOutcome(context: self.makeContext())

        switch outcome.result {
        case .success:
            Issue.record("Expected missing credentials failure")
        case let .failure(error):
            #expect((error as? KiloUsageError) == .missingCredentials)
        }

        #expect(outcome.attempts.count == 1)
        #expect(outcome.attempts.first?.strategyID == "kilo.api")
        #expect(outcome.attempts.first?.wasAvailable == true)
    }

    @Test
    func descriptor_API_mode_ignores_CLI_session_fallback() async throws {
        let homeDirectory = try self.makeTemporaryHomeDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }
        try self.writeKiloAuthFile(
            homeDirectory: homeDirectory,
            contents: #"{"kilo":{"access":"file-token"}}"#)

        let descriptor = ProviderDescriptorRegistry.descriptor(for: .kilo)
        let outcome = await descriptor.fetchOutcome(context: self.makeContext(
            env: ["HOME": homeDirectory.path],
            sourceMode: .api))

        switch outcome.result {
        case .success:
            Issue.record("Expected missing API credentials failure")
        case let .failure(error):
            #expect((error as? KiloUsageError) == .missingCredentials)
        }

        #expect(outcome.attempts.count == 1)
        #expect(outcome.attempts.first?.strategyID == "kilo.api")
    }

    @Test
    func descriptor_CLI_mode_missing_session_returns_actionable_error() async throws {
        let homeDirectory = try self.makeTemporaryHomeDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }
        let expectedPath = KiloSettingsReader.defaultAuthFileURL(homeDirectory: homeDirectory).path

        let descriptor = ProviderDescriptorRegistry.descriptor(for: .kilo)
        let outcome = await descriptor.fetchOutcome(context: self.makeContext(
            env: ["HOME": homeDirectory.path],
            sourceMode: .cli))

        switch outcome.result {
        case .success:
            Issue.record("Expected missing CLI session failure")
        case let .failure(error):
            #expect((error as? KiloUsageError) == .cliSessionMissing(expectedPath))
        }

        #expect(outcome.attempts.count == 1)
        #expect(outcome.attempts.first?.strategyID == "kilo.cli")
    }

    @Test
    func descriptor_auto_mode_falls_back_from_API_to_CLI() async throws {
        let homeDirectory = try self.makeTemporaryHomeDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }
        let expectedPath = KiloSettingsReader.defaultAuthFileURL(homeDirectory: homeDirectory).path

        let descriptor = ProviderDescriptorRegistry.descriptor(for: .kilo)
        let outcome = await descriptor.fetchOutcome(context: self.makeContext(
            env: ["HOME": homeDirectory.path],
            sourceMode: .auto))

        switch outcome.result {
        case .success:
            Issue.record("Expected missing CLI session failure after API fallback")
        case let .failure(error):
            #expect((error as? KiloUsageError) == .cliSessionMissing(expectedPath))
        }

        #expect(outcome.attempts.count == 2)
        #expect(outcome.attempts.map(\.strategyID) == ["kilo.api", "kilo.cli"])
    }

    @Test
    func api_strategy_falls_back_on_unauthorized_only_in_auto_mode() {
        let strategy = KiloAPIFetchStrategy()
        #expect(strategy.shouldFallback(
            on: KiloUsageError.unauthorized,
            context: self.makeContext(sourceMode: .auto)))
        #expect(!strategy.shouldFallback(
            on: KiloUsageError.unauthorized,
            context: self.makeContext(sourceMode: .api)))
    }

    @Test
    func api_strategy_falls_back_on_missing_credentials_only_in_auto_mode() {
        let strategy = KiloAPIFetchStrategy()
        #expect(strategy.shouldFallback(
            on: KiloUsageError.missingCredentials,
            context: self.makeContext(sourceMode: .auto)))
        #expect(!strategy.shouldFallback(
            on: KiloUsageError.missingCredentials,
            context: self.makeContext(sourceMode: .api)))
    }

    @Test
    func request_builder_adds_org_header_for_organization_scope() throws {
        let baseURL = try #require(URL(string: "https://kilo.example/trpc"))
        let request = try KiloUsageFetcher._buildRequestForTesting(
            baseURL: baseURL,
            apiKey: "test-token",
            scope: .organization(id: "org_42", name: "Acme"))
        #expect(request.value(forHTTPHeaderField: "X-KILOCODE-ORGANIZATIONID") == "org_42")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    }

    @Test
    func request_builder_omits_org_header_for_personal_scope() throws {
        let baseURL = try #require(URL(string: "https://kilo.example/trpc"))
        let request = try KiloUsageFetcher._buildRequestForTesting(
            baseURL: baseURL,
            apiKey: "test-token",
            scope: .personal)
        #expect(request.value(forHTTPHeaderField: "X-KILOCODE-ORGANIZATIONID") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    }

    @Test
    func parseOrganizations_decodes_tRPC_array_shape() throws {
        let json = #"""
        [
          {
            "result": {
              "data": {
                "json": [
                  { "id": "org_1", "name": "Alpha", "role": "owner" },
                  { "id": "org_2", "name": "Beta", "role": "member" }
                ]
              }
            }
          }
        ]
        """#
        let orgs = try KiloUsageFetcher._parseOrganizationsForTesting(Data(json.utf8))
        #expect(orgs.count == 2)
        #expect(orgs[0].id == "org_1")
        #expect(orgs[0].name == "Alpha")
        #expect(orgs[0].role == "owner")
        #expect(orgs[1].id == "org_2")
        #expect(orgs[1].role == "member")
    }

    @Test
    func parseOrganizations_decodes_profile_REST_shape() throws {
        let json = #"""
        {
          "user": { "email": "test@example.com" },
          "organizations": [
            { "id": "org_42", "name": "Gamma" }
          ]
        }
        """#
        let orgs = try KiloUsageFetcher._parseOrganizationsForTesting(Data(json.utf8))
        #expect(orgs.count == 1)
        #expect(orgs[0].id == "org_42")
        #expect(orgs[0].role == nil)
    }

    @Test
    func parseOrganizations_returns_empty_for_no_orgs() throws {
        let json = #"""
        { "user": { "email": "x@y" }, "organizations": [] }
        """#
        let orgs = try KiloUsageFetcher._parseOrganizationsForTesting(Data(json.utf8))
        #expect(orgs.isEmpty)
    }

    private func makeTemporaryHomeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeKiloAuthFile(homeDirectory: URL, contents: String) throws {
        let fileURL = KiloSettingsReader.defaultAuthFileURL(homeDirectory: homeDirectory)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
