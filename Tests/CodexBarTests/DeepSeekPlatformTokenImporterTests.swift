import Foundation
import Testing
@testable import CodexBarCore

struct DeepSeekPlatformTokenImporterTests {
    @Test
    func extracts_plain_user_token() {
        let token = "browser-user-token-1234567890"
        #expect(DeepSeekPlatformTokenImporter._extractUserTokenForTesting(token) == token)
    }

    @Test
    func extracts_JSON_encoded_user_token() {
        let token = "browser-user-token-abcdefghij"
        let value = "{\"userToken\":\"\(token)\"}"
        #expect(DeepSeekPlatformTokenImporter._extractUserTokenForTesting(value) == token)
    }

    @Test
    func extracts_DeepSeek_value_wrapped_user_token() {
        let token = "browser-user-token-value-wrapped"
        let value = "{\"value\":\"\(token)\",\"expiresAt\":1234567890}"
        #expect(DeepSeekPlatformTokenImporter._extractUserTokenForTesting(value) == token)
    }

    @Test
    func does_not_treat_an_unrecognized_JSON_object_as_a_token() {
        #expect(DeepSeekPlatformTokenImporter._extractUserTokenForTesting("{\"expiresAt\":1234567890}") == nil)
    }

    @Test
    func rejects_short_or_whitespace_values() {
        #expect(DeepSeekPlatformTokenImporter._extractUserTokenForTesting("short") == nil)
        #expect(DeepSeekPlatformTokenImporter._extractUserTokenForTesting("token with embedded spaces 12345") == nil)
    }

    #if os(macOS)
    @Test
    func imports_platform_token_through_browser_local_storage_host_API() {
        let localStorage = BrowserLocalStorageAPI { _, _, _, _ in
            [
                BrowserLocalStorageAPI.Profile(
                    id: "chrome:Profile 2",
                    label: "Chrome — Work",
                    entries: [
                        BrowserLocalStorageAPI.Entry(
                            key: "userToken",
                            value: "browser-user-token-through-host-api"),
                    ]),
            ]
        }

        let tokens = DeepSeekPlatformTokenImporter.importTokens(
            browserDetection: BrowserDetection(cacheTTL: 0),
            localStorage: localStorage)

        #expect(tokens.map(\.id) == ["chrome:Profile 2"])
        #expect(tokens.map(\.sourceLabel) == ["Chrome — Work"])
    }
    #endif

    @Test
    func multiple_profiles_expose_only_server_accepted_sessions() async {
        let candidates = [
            Self.candidate(id: "profile-1", token: "valid-1"),
            Self.candidate(id: "profile-2", token: "expired"),
            Self.candidate(id: "profile-3", token: "valid-3"),
        ]

        let resolution = await DeepSeekPlatformTokenImporter._resolveForTesting(
            candidates: candidates,
            selectedProfileID: nil,
            validate: { token in
                guard token != "expired" else { throw DeepSeekUsageError.invalidPlatformToken }
                return Self.summary(marker: token == "valid-1" ? 1 : 3)
            })

        #expect(resolution.profiles.map(\.id) == ["profile-1", "profile-3"])
        #expect(resolution.selectedSummary == nil)
        #expect(resolution.detailedUsageState == .profileSelectionRequired)
    }

    @Test
    func single_accepted_profile_is_selected_automatically() async {
        let candidates = [
            Self.candidate(id: "profile-1", token: "expired-1"),
            Self.candidate(id: "profile-2", token: "valid-2"),
            Self.candidate(id: "profile-3", token: "expired-3"),
        ]

        let resolution = await DeepSeekPlatformTokenImporter._resolveForTesting(
            candidates: candidates,
            selectedProfileID: nil,
            validate: { token in
                guard token == "valid-2" else { throw DeepSeekUsageError.invalidPlatformToken }
                return Self.summary(marker: 2)
            })

        #expect(resolution.profiles.map(\.id) == ["profile-2"])
        #expect(resolution.selectedSummary?.todayTokens == 2)
        #expect(resolution.detailedUsageState == .available)
    }

    @Test
    func selected_profile_preserves_its_detailed_usage_state() async {
        let resolution = await DeepSeekPlatformTokenImporter._resolveForTesting(
            candidates: [Self.candidate(id: "profile-1", token: "valid-1")],
            selectedProfileID: nil,
            detailedUsageState: .notRequested,
            validate: { _ in Self.summary(marker: 1) })

        #expect(resolution.selectedSummary?.todayTokens == 1)
        #expect(resolution.detailedUsageState == .notRequested)
    }

    @Test
    func explicit_selection_requirement_does_not_auto_select_a_single_accepted_profile() async {
        let resolution = await DeepSeekPlatformTokenImporter._resolveForTesting(
            candidates: [Self.candidate(id: "profile-1", token: "valid-1")],
            selectedProfileID: nil,
            requiresExplicitSelection: true,
            validate: { _ in Self.summary(marker: 1) })

        #expect(resolution.profiles.map(\.id) == ["profile-1"])
        #expect(resolution.selectedSummary == nil)
        #expect(resolution.detailedUsageState == .profileSelectionRequired)
    }

    @Test
    func stored_selection_chooses_one_of_multiple_accepted_profiles() async {
        let candidates = [
            Self.candidate(id: "profile-1", token: "valid-1"),
            Self.candidate(id: "profile-2", token: "valid-2"),
        ]
        let cache = DeepSeekPlatformValidationCache()
        _ = await DeepSeekPlatformTokenImporter._resolveForTesting(
            candidates: candidates,
            selectedProfileID: nil,
            cache: cache,
            validate: { token in
                Self.summary(marker: token == "valid-1" ? 1 : 2)
            })

        let resolution = await DeepSeekPlatformTokenImporter._resolveForTesting(
            candidates: candidates,
            selectedProfileID: "profile-2",
            cache: cache,
            validate: { token in
                Self.summary(marker: token == "valid-1" ? 1 : 2)
            })

        #expect(resolution.profiles.map(\.id) == ["profile-1", "profile-2"])
        #expect(resolution.selectedSummary?.todayTokens == 2)
        #expect(resolution.detailedUsageState == .available)
    }

    @Test
    func stored_selection_does_not_wait_for_unrelated_profile_validation() async {
        let gate = DeepSeekPlatformValidationGate()
        let fallbackRelease = Task {
            try? await Task.sleep(for: .seconds(1))
            await gate.open()
        }
        let startedAt = ContinuousClock.now

        let resolution = await DeepSeekPlatformTokenImporter._resolveForTesting(
            candidates: [
                Self.candidate(id: "profile-1", token: "selected"),
                Self.candidate(id: "profile-2", token: "unselected"),
            ],
            selectedProfileID: "profile-1",
            validate: { token in
                if token == "unselected" {
                    await gate.wait()
                }
                return Self.summary(marker: token == "selected" ? 1 : 2)
            })

        let elapsed = startedAt.duration(to: .now)
        await gate.open()
        fallbackRelease.cancel()

        #expect(elapsed < .milliseconds(500))
        #expect(resolution.profiles.map(\.id) == ["profile-1"])
        #expect(resolution.selectedSummary?.todayTokens == 1)
        #expect(resolution.detailedUsageState == .available)
    }

    @Test
    func expired_stored_selection_does_not_silently_switch_to_another_profile() async {
        let candidates = [
            Self.candidate(id: "profile-1", token: "expired"),
            Self.candidate(id: "profile-2", token: "valid-2"),
        ]

        let resolution = await DeepSeekPlatformTokenImporter._resolveForTesting(
            candidates: candidates,
            selectedProfileID: "profile-1",
            validate: { token in
                guard token == "valid-2" else { throw DeepSeekUsageError.invalidPlatformToken }
                return Self.summary(marker: 2)
            })

        #expect(resolution.profiles.map(\.id) == ["profile-2"])
        #expect(resolution.selectedSummary == nil)
        #expect(resolution.detailedUsageState == .profileSelectionRequired)
    }

    @Test
    func temporary_validation_failure_is_unavailable_rather_than_signed_out() async {
        let resolution = await DeepSeekPlatformTokenImporter._resolveForTesting(
            candidates: [Self.candidate(id: "profile-1", token: "maybe-valid")],
            selectedProfileID: nil,
            validate: { _ in throw DeepSeekUsageError.networkError("offline") })

        #expect(resolution.profiles.isEmpty)
        #expect(resolution.selectedSummary == nil)
        #expect(resolution.detailedUsageState == .unavailable)
    }

    @Test
    func temporary_validation_failure_keeps_a_previously_accepted_profile() async {
        let candidate = Self.candidate(id: "profile-1", token: "valid-1")
        let cache = DeepSeekPlatformValidationCache(validityTTL: 0)
        _ = await DeepSeekPlatformTokenImporter._resolveForTesting(
            candidates: [candidate],
            selectedProfileID: nil,
            cache: cache,
            validate: { _ in Self.summary(marker: 1) })

        let resolution = await DeepSeekPlatformTokenImporter._resolveForTesting(
            candidates: [candidate],
            selectedProfileID: nil,
            cache: cache,
            validate: { _ in throw DeepSeekUsageError.networkError("offline") })

        #expect(resolution.profiles.map(\.id) == ["profile-1"])
        #expect(resolution.selectedSummary == nil)
        #expect(resolution.detailedUsageState == .unavailable)
    }

    private static func candidate(id: String, token: String) -> DeepSeekPlatformTokenImporter.TokenInfo {
        DeepSeekPlatformTokenImporter.TokenInfo(id: id, token: token, sourceLabel: "Chrome \(id)")
    }

    private static func summary(marker: Int) -> DeepSeekUsageSummary {
        DeepSeekUsageSummary(
            todayTokens: marker,
            currentMonthTokens: marker,
            todayCost: nil,
            currentMonthCost: nil,
            requestCount: marker,
            currentMonthRequestCount: marker,
            topModel: nil,
            categoryBreakdown: [],
            daily: [],
            currency: "USD",
            updatedAt: Date(timeIntervalSince1970: 0))
    }
}

private actor DeepSeekPlatformValidationGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !self.isOpen else { return }
        await withCheckedContinuation { continuation in
            self.continuations.append(continuation)
        }
    }

    func open() {
        self.isOpen = true
        let continuations = self.continuations
        self.continuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}
