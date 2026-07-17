import Foundation
import Testing
@testable import CodexBarCore

struct DeepSeekProviderDescriptorTests {
    private actor CancellationProbe {
        private(set) var wasCancelled = false

        func markCancelled() {
            self.wasCancelled = true
        }
    }

    private actor ResolutionInputProbe {
        private(set) var profileID: String?
        private(set) var requiresExplicitSelection = false
        private(set) var includesPlatformBalance = false
        private(set) var includesOptionalUsage = true

        func record(
            profileID: String?,
            requiresExplicitSelection: Bool,
            includesPlatformBalance: Bool = false,
            includesOptionalUsage: Bool = true)
        {
            self.profileID = profileID
            self.requiresExplicitSelection = requiresExplicitSelection
            self.includesPlatformBalance = includesPlatformBalance
            self.includesOptionalUsage = includesOptionalUsage
        }
    }

    private actor UsageInputProbe {
        private(set) var platformTokens: [String?] = []

        func record(platformToken: String?) {
            self.platformTokens.append(platformToken)
        }
    }

    @Test
    func balance_failure_cancels_automatic_session_resolution_promptly() async {
        let probe = CancellationProbe()
        let operations = DeepSeekProviderDescriptor.FetchOperations(
            fetchUsage: { _, _, _ in
                throw DeepSeekUsageError.apiError("invalid key")
            },
            resolveAutomaticSession: { _, _, _, _, _, _ in
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    await probe.markCancelled()
                }
                return Self.unavailableResolution
            })
        let startedAt = ContinuousClock.now

        do {
            _ = try await DeepSeekProviderDescriptor._loadUsageForTesting(
                apiKey: "invalid",
                context: Self.makeContext(),
                optionalResolutionJoinGrace: .seconds(5),
                operations: operations)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                error as? DeepSeekUsageError == .apiError("invalid key")
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }

        #expect(startedAt.duration(to: .now) < .seconds(1))
        let cancellationDeadline = ContinuousClock.now.advanced(by: .milliseconds(200))
        while await !(probe.wasCancelled), ContinuousClock.now < cancellationDeadline {
            await Task.yield()
        }
        #expect(await probe.wasCancelled)
    }

    @Test
    func automatic_session_resolution_cannot_hold_balance_past_its_grace() async throws {
        let probe = CancellationProbe()
        let operations = DeepSeekProviderDescriptor.FetchOperations(
            fetchUsage: { _, _, _ in Self.balance },
            resolveAutomaticSession: { _, _, _, _, _, _ in
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    await probe.markCancelled()
                }
                return Self.unavailableResolution
            })
        let startedAt = ContinuousClock.now

        let snapshot = try await DeepSeekProviderDescriptor._loadUsageForTesting(
            apiKey: "valid",
            context: Self.makeContext(),
            optionalResolutionJoinGrace: .milliseconds(20),
            operations: operations)

        #expect(snapshot.primary?.resetDescription?.contains("$8.06") == true)
        #expect(snapshot.deepseekUsage == nil)
        #expect(snapshot.deepseekDetailedUsageState == .unavailable)
        #expect(startedAt.duration(to: .now) < .seconds(1))
        let cancellationDeadline = ContinuousClock.now.advanced(by: .milliseconds(200))
        while await !(probe.wasCancelled), ContinuousClock.now < cancellationDeadline {
            await Task.yield()
        }
        #expect(await probe.wasCancelled)
    }

    @Test
    func automatic_session_result_enriches_the_required_balance() async throws {
        let summary = DeepSeekUsageSummary(
            todayTokens: 123,
            currentMonthTokens: 456,
            todayCost: 0.1,
            currentMonthCost: 0.2,
            requestCount: 3,
            currentMonthRequestCount: 4,
            topModel: "deepseek-chat",
            categoryBreakdown: [],
            daily: [],
            currency: "USD",
            updatedAt: Date(timeIntervalSince1970: 1))
        let operations = DeepSeekProviderDescriptor.FetchOperations(
            fetchUsage: { _, _, _ in Self.balance },
            resolveAutomaticSession: { _, _, _, _, _, _ in
                DeepSeekPlatformTokenImporter.Resolution(
                    profiles: [DeepSeekPlatformProfile(id: "chrome:Default", name: "Chrome — Personal")],
                    selectedSummary: summary,
                    detailedUsageState: .available)
            })

        let snapshot = try await DeepSeekProviderDescriptor._loadUsageForTesting(
            apiKey: "valid",
            context: Self.makeContext(),
            optionalResolutionJoinGrace: .seconds(1),
            operations: operations)

        #expect(snapshot.primary?.resetDescription?.contains("$8.06") == true)
        #expect(snapshot.deepseekUsage?.todayTokens == 123)
        #expect(snapshot.deepseekDetailedUsageState == .available)
        #expect(snapshot.deepseekPlatformProfiles.map(\.id) == ["chrome:Default"])
    }

    @Test
    func automatic_resolution_timeout_is_hard_when_the_resolver_ignores_cancellation() async throws {
        let operations = DeepSeekProviderDescriptor.FetchOperations(
            fetchUsage: { _, _, _ in Self.balance },
            resolveAutomaticSession: { _, _, _, _, _, _ in
                let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
                while ContinuousClock.now < deadline {
                    await Task.yield()
                }
                return Self.unavailableResolution
            })
        let startedAt = ContinuousClock.now

        let snapshot = try await DeepSeekProviderDescriptor._loadUsageForTesting(
            apiKey: "valid",
            context: Self.makeContext(),
            optionalResolutionJoinGrace: .milliseconds(20),
            operations: operations)

        #expect(snapshot.primary?.resetDescription?.contains("$8.06") == true)
        #expect(startedAt.duration(to: .now) < .milliseconds(200))
    }

    @Test
    func profile_selection_from_another_api_account_requires_explicit_replacement() async throws {
        let probe = ResolutionInputProbe()
        let selectedAccountID = UUID()
        let otherAccountID = UUID()
        let operations = DeepSeekProviderDescriptor.FetchOperations(
            fetchUsage: { _, _, _ in Self.balance },
            resolveAutomaticSession: { profileID, requiresExplicitSelection, _, _, _, _ in
                await probe.record(
                    profileID: profileID,
                    requiresExplicitSelection: requiresExplicitSelection)
                return Self.unavailableResolution
            })
        let otherAccountScope = try #require(DeepSeekSettingsReader.profileScope(
            selectedTokenAccountID: otherAccountID,
            apiKey: "valid"))
        let environment = [
            DeepSeekSettingsReader.profileIDEnvironmentKey: "chrome:Default",
            DeepSeekSettingsReader.profileScopeEnvironmentKey: otherAccountScope,
        ]

        _ = try await DeepSeekProviderDescriptor._loadUsageForTesting(
            apiKey: "valid",
            context: Self.makeContext(environment: environment, selectedTokenAccountID: selectedAccountID),
            optionalResolutionJoinGrace: .seconds(1),
            operations: operations)

        #expect(await probe.profileID == nil)
        #expect(await probe.requiresExplicitSelection)
    }

    @Test
    func replacing_an_api_key_in_the_same_account_requires_explicit_profile_replacement() async throws {
        let probe = ResolutionInputProbe()
        let selectedAccountID = UUID()
        let operations = DeepSeekProviderDescriptor.FetchOperations(
            fetchUsage: { _, _, _ in Self.balance },
            resolveAutomaticSession: { profileID, requiresExplicitSelection, _, _, _, _ in
                await probe.record(profileID: profileID, requiresExplicitSelection: requiresExplicitSelection)
                return Self.unavailableResolution
            })
        let oldScope = try #require(DeepSeekSettingsReader.profileScope(
            selectedTokenAccountID: selectedAccountID,
            apiKey: "old-key"))
        let environment = [
            DeepSeekSettingsReader.profileIDEnvironmentKey: "chrome:Default",
            DeepSeekSettingsReader.profileScopeEnvironmentKey: oldScope,
        ]

        _ = try await DeepSeekProviderDescriptor._loadUsageForTesting(
            apiKey: "new-key",
            context: Self.makeContext(environment: environment, selectedTokenAccountID: selectedAccountID),
            optionalResolutionJoinGrace: .seconds(1),
            operations: operations)

        #expect(await probe.profileID == nil)
        #expect(await probe.requiresExplicitSelection)
    }

    @Test
    func changing_the_environment_api_key_requires_explicit_profile_replacement() async throws {
        let probe = ResolutionInputProbe()
        let operations = DeepSeekProviderDescriptor.FetchOperations(
            fetchUsage: { _, _, _ in Self.balance },
            resolveAutomaticSession: { profileID, requiresExplicitSelection, _, _, _, _ in
                await probe.record(profileID: profileID, requiresExplicitSelection: requiresExplicitSelection)
                return Self.unavailableResolution
            })
        let oldScope = try #require(DeepSeekSettingsReader.profileScope(
            selectedTokenAccountID: nil,
            apiKey: "old-key"))
        let environment = [
            DeepSeekSettingsReader.profileIDEnvironmentKey: "chrome:Default",
            DeepSeekSettingsReader.profileScopeEnvironmentKey: oldScope,
        ]

        _ = try await DeepSeekProviderDescriptor._loadUsageForTesting(
            apiKey: "new-key",
            context: Self.makeContext(environment: environment),
            optionalResolutionJoinGrace: .seconds(1),
            operations: operations)

        #expect(await probe.profileID == nil)
        #expect(await probe.requiresExplicitSelection)
    }

    @Test
    func platform_session_from_another_account_does_not_enrich_api_balance() async throws {
        let probe = UsageInputProbe()
        let activeAccountID = UUID()
        let credential = "api-key-value"
        let otherAccountScope = try #require(DeepSeekSettingsReader.profileScope(
            selectedTokenAccountID: UUID(),
            apiKey: credential))
        let environment = [
            DeepSeekSettingsReader.platformTokenEnvironmentKey: "platform-session",
            DeepSeekSettingsReader.profileScopeEnvironmentKey: otherAccountScope,
        ]
        let operations = DeepSeekProviderDescriptor.FetchOperations(
            fetchUsage: { _, platformToken, _ in
                await probe.record(platformToken: platformToken)
                return Self.balance
            },
            resolveAutomaticSession: { _, _, _, _, _, _ in Self.unavailableResolution })

        _ = try await DeepSeekProviderDescriptor._loadUsageForTesting(
            apiKey: credential,
            context: Self.makeContext(
                environment: environment,
                selectedTokenAccountID: activeAccountID),
            optionalResolutionJoinGrace: .seconds(1),
            operations: operations)

        #expect(await probe.platformTokens == [nil])
    }

    @Test
    func browser_only_mode_returns_Platform_balance_and_usage_without_an_API_key() async throws {
        let probe = ResolutionInputProbe()
        let summary = DeepSeekUsageSummary(
            todayTokens: 123,
            currentMonthTokens: 456,
            todayCost: 0.1,
            currentMonthCost: 0.2,
            requestCount: 3,
            currentMonthRequestCount: 4,
            topModel: "deepseek-chat",
            categoryBreakdown: [],
            daily: [],
            currency: "USD",
            updatedAt: Date(timeIntervalSince1970: 1))
        let operations = DeepSeekProviderDescriptor.FetchOperations(
            fetchUsage: { _, _, _ in
                throw DeepSeekUsageError.missingCredentials
            },
            resolveAutomaticSession: { profileID, explicit, includeBalance, includeOptional, _, _ in
                await probe.record(
                    profileID: profileID,
                    requiresExplicitSelection: explicit,
                    includesPlatformBalance: includeBalance,
                    includesOptionalUsage: includeOptional)
                return DeepSeekPlatformTokenImporter.Resolution(
                    profiles: [DeepSeekPlatformProfile(id: "chrome:Default", name: "Chrome — Yuqing")],
                    selectedSummary: summary,
                    selectedBalance: Self.balance,
                    detailedUsageState: .available)
            })

        let snapshot = try await DeepSeekProviderDescriptor._loadPlatformUsageForTesting(
            context: Self.makeContext(sourceMode: .auto),
            operations: operations)

        #expect(snapshot.primary?.resetDescription?.contains("$8.06") == true)
        #expect(snapshot.deepseekUsage == summary)
        #expect(snapshot.deepseekDetailedUsageState == .available)
        #expect(snapshot.deepseekPlatformProfiles.map(\.id) == ["chrome:Default"])
        #expect(await probe.profileID == nil)
        #expect(await probe.requiresExplicitSelection == false)
        #expect(await probe.includesPlatformBalance)
        #expect(await probe.includesOptionalUsage)
    }

    @Test
    func forced_web_mode_preserves_the_active_credential_profile_scope() async throws {
        let probe = ResolutionInputProbe()
        let selectedAccountID = UUID()
        let credential = "api-key-value"
        let scope = try #require(DeepSeekSettingsReader.profileScope(
            selectedTokenAccountID: selectedAccountID,
            apiKey: credential))
        let environment = [
            DeepSeekSettingsReader.apiKeyEnvironmentKey: credential,
            DeepSeekSettingsReader.profileIDEnvironmentKey: "chrome:Profile 2",
            DeepSeekSettingsReader.profileScopeEnvironmentKey: scope,
        ]
        let operations = DeepSeekProviderDescriptor.FetchOperations(
            fetchUsage: { _, _, _ in
                throw DeepSeekUsageError.missingCredentials
            },
            resolveAutomaticSession: { profileID, explicit, includeBalance, includeOptional, _, _ in
                await probe.record(
                    profileID: profileID,
                    requiresExplicitSelection: explicit,
                    includesPlatformBalance: includeBalance,
                    includesOptionalUsage: includeOptional)
                return DeepSeekPlatformTokenImporter.Resolution(
                    profiles: [DeepSeekPlatformProfile(id: "chrome:Profile 2", name: "Chrome — Work")],
                    selectedSummary: nil,
                    selectedBalance: Self.balance,
                    detailedUsageState: .available)
            })

        _ = try await DeepSeekProviderDescriptor._loadPlatformUsageForTesting(
            context: Self.makeContext(
                environment: environment,
                selectedTokenAccountID: selectedAccountID,
                sourceMode: .web),
            operations: operations)

        #expect(await probe.profileID == "chrome:Profile 2")
        #expect(await probe.requiresExplicitSelection == false)
        #expect(await probe.includesPlatformBalance)
    }

    @Test
    func browser_only_mode_skips_optional_usage_when_extras_are_disabled() async throws {
        let probe = ResolutionInputProbe()
        let operations = DeepSeekProviderDescriptor.FetchOperations(
            fetchUsage: { _, _, _ in
                throw DeepSeekUsageError.missingCredentials
            },
            resolveAutomaticSession: { profileID, explicit, includeBalance, includeOptional, _, _ in
                await probe.record(
                    profileID: profileID,
                    requiresExplicitSelection: explicit,
                    includesPlatformBalance: includeBalance,
                    includesOptionalUsage: includeOptional)
                return DeepSeekPlatformTokenImporter.Resolution(
                    profiles: [DeepSeekPlatformProfile(id: "chrome:Default", name: "Chrome — Yuqing")],
                    selectedSummary: nil,
                    selectedBalance: Self.balance,
                    detailedUsageState: .notRequested)
            })

        let snapshot = try await DeepSeekProviderDescriptor._loadPlatformUsageForTesting(
            context: Self.makeContext(sourceMode: .auto, includeOptionalUsage: false),
            operations: operations)

        #expect(snapshot.primary != nil)
        #expect(snapshot.deepseekUsage == nil)
        #expect(snapshot.deepseekDetailedUsageState == .notRequested)
        #expect(await probe.includesPlatformBalance)
        #expect(await probe.includesOptionalUsage == false)
    }

    @Test
    func browser_only_resolution_timeout_is_hard_when_Chrome_ignores_cancellation() async throws {
        let operations = DeepSeekProviderDescriptor.FetchOperations(
            fetchUsage: { _, _, _ in Self.balance },
            resolveAutomaticSession: { _, _, _, _, _, _ in
                let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
                while ContinuousClock.now < deadline {
                    await Task.yield()
                }
                return Self.unavailableResolution
            })
        let startedAt = ContinuousClock.now

        do {
            _ = try await DeepSeekProviderDescriptor._loadPlatformUsageForTesting(
                context: Self.makeContext(sourceMode: .auto),
                resolutionJoinGrace: .milliseconds(20),
                operations: operations)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case let DeepSeekUsageError.networkError(message) = error else { return false }
                return message.contains("timed out")
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
        #expect(startedAt.duration(to: .now) < .milliseconds(200))
    }

    @Test
    func browser_only_mode_asks_for_Chrome_sign_in_instead_of_an_API_key() async throws {
        let operations = DeepSeekProviderDescriptor.FetchOperations(
            fetchUsage: { _, _, _ in
                throw DeepSeekUsageError.missingCredentials
            },
            resolveAutomaticSession: { _, _, _, _, _, _ in
                DeepSeekPlatformTokenImporter.Resolution(
                    profiles: [],
                    selectedSummary: nil,
                    detailedUsageState: .webSessionRequired)
            })

        let snapshot = try await DeepSeekProviderDescriptor._loadPlatformUsageForTesting(
            context: Self.makeContext(sourceMode: .auto),
            operations: operations)

        #expect(snapshot.primary == nil)
        #expect(snapshot.deepseekDetailedUsageState == .webSessionRequired)
    }

    @Test
    func automatic_source_uses_Chrome_session_when_API_key_is_absent() async {
        let strategies = await DeepSeekProviderDescriptor.descriptor.fetchPlan.pipeline.resolveStrategies(
            Self.makeContext(sourceMode: .auto))

        #expect(strategies.map(\.id) == ["deepseek.web"])
    }

    @Test
    func automatic_source_keeps_API_path_when_API_key_is_present() async {
        let strategies = await DeepSeekProviderDescriptor.descriptor.fetchPlan.pipeline.resolveStrategies(
            Self.makeContext(
                environment: [DeepSeekSettingsReader.apiKeyEnvironmentKey: "test-api-key"],
                sourceMode: .auto))

        #expect(strategies.map(\.id) == ["deepseek.api"])
    }

    private static let balance = DeepSeekUsageSnapshot(
        isAvailable: true,
        currency: "USD",
        totalBalance: 8.06,
        grantedBalance: 0,
        toppedUpBalance: 8.06,
        updatedAt: Date(timeIntervalSince1970: 1))

    private static let unavailableResolution = DeepSeekPlatformTokenImporter.Resolution(
        profiles: [],
        selectedSummary: nil,
        detailedUsageState: .unavailable)

    private static func makeContext(
        environment: [String: String] = [:],
        selectedTokenAccountID: UUID? = nil,
        sourceMode: ProviderSourceMode = .api,
        includeOptionalUsage: Bool = true) -> ProviderFetchContext
    {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        return ProviderFetchContext(
            runtime: .app,
            sourceMode: sourceMode,
            includeCredits: false,
            includeOptionalUsage: includeOptionalUsage,
            webTimeout: 60,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: nil,
            fetcher: UsageFetcher(environment: [:]),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection,
            selectedTokenAccountID: selectedTokenAccountID)
    }
}
