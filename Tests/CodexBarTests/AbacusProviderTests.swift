import Foundation
import Testing
@testable import CodexBarCore

// MARK: - Descriptor Tests

struct AbacusDescriptorTests {
    @Test
    func descriptor_has_correct_identity() {
        let descriptor = AbacusProviderDescriptor.descriptor
        #expect(descriptor.id == .abacus)
        #expect(descriptor.metadata.displayName == "Abacus AI")
        #expect(descriptor.metadata.cliName == "abacusai")
    }

    @Test
    func descriptor_does_not_expose_a_separate_credits_panel() {
        let meta = AbacusProviderDescriptor.descriptor.metadata
        #expect(meta.supportsCredits == false)
        #expect(meta.supportsOpus == false)
    }

    @Test
    func descriptor_is_not_primary_provider() {
        let meta = AbacusProviderDescriptor.descriptor.metadata
        #expect(meta.isPrimaryProvider == false)
        #expect(meta.defaultEnabled == false)
    }

    @Test
    func descriptor_supports_auto_and_web_source_modes() {
        let descriptor = AbacusProviderDescriptor.descriptor
        #expect(descriptor.fetchPlan.sourceModes.contains(.auto))
        #expect(descriptor.fetchPlan.sourceModes.contains(.web))
    }

    @Test
    func descriptor_has_no_version_detector() {
        let descriptor = AbacusProviderDescriptor.descriptor
        #expect(descriptor.cli.versionDetector == nil)
    }

    @Test
    func descriptor_does_not_support_token_cost() {
        let descriptor = AbacusProviderDescriptor.descriptor
        #expect(descriptor.tokenCost.supportsTokenCost == false)
    }

    @Test
    func cli_aliases_include_abacus_ai() {
        let descriptor = AbacusProviderDescriptor.descriptor
        #expect(descriptor.cli.aliases.contains("abacus-ai"))
    }

    @Test
    func dashboard_url_points_to_compute_points_page() {
        let meta = AbacusProviderDescriptor.descriptor.metadata
        #expect(meta.dashboardURL?.contains("compute-points") == true)
    }
}

// MARK: - Usage Snapshot Conversion Tests

struct AbacusUsageSnapshotTests {
    @Test
    func converts_full_snapshot_to_usage_snapshot() throws {
        let resetDate = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = AbacusUsageSnapshot(
            creditsUsed: 250,
            creditsTotal: 1000,
            resetsAt: resetDate,
            planName: "Pro")

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary != nil)
        #expect(abs((usage.primary?.usedPercent ?? 0) - 25.0) < 0.01)
        #expect(usage.primary?.resetDescription == "250 / 1,000 credits")
        #expect(usage.primary?.resetsAt == resetDate)
        // Window derived from actual billing cycle (1 calendar month before resetDate)
        let cycleStart = try #require(Calendar.current.date(byAdding: .month, value: -1, to: resetDate))
        let expectedMinutes = Int(resetDate.timeIntervalSince(cycleStart) / 60)
        #expect(usage.primary?.windowMinutes == expectedMinutes)
        #expect(usage.secondary == nil)
        #expect(usage.tertiary == nil)
        #expect(usage.identity?.providerID == .abacus)
        #expect(usage.identity?.loginMethod == "Pro")
    }

    @Test
    func handles_zero_usage() {
        let snapshot = AbacusUsageSnapshot(
            creditsUsed: 0,
            creditsTotal: 500,
            resetsAt: nil,
            planName: "Basic")

        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.usedPercent == 0.0)
        #expect(usage.primary?.resetDescription == "0 / 500 credits")
    }

    @Test
    func handles_full_usage() {
        let snapshot = AbacusUsageSnapshot(
            creditsUsed: 1000,
            creditsTotal: 1000,
            resetsAt: nil,
            planName: nil)

        let usage = snapshot.toUsageSnapshot()
        #expect(abs((usage.primary?.usedPercent ?? 0) - 100.0) < 0.01)
        #expect(usage.primary?.resetDescription == "1,000 / 1,000 credits")
    }

    @Test
    func handles_nil_credits_gracefully() {
        let snapshot = AbacusUsageSnapshot(
            creditsUsed: nil,
            creditsTotal: nil,
            resetsAt: nil,
            planName: nil)

        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.usedPercent == 0.0)
        #expect(usage.primary?.resetDescription == nil)
    }

    @Test
    func handles_nil_total_with_non_nil_used() {
        let snapshot = AbacusUsageSnapshot(
            creditsUsed: 100,
            creditsTotal: nil,
            resetsAt: nil,
            planName: nil)

        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.usedPercent == 0.0)
    }

    @Test
    func handles_zero_total_credits() {
        let snapshot = AbacusUsageSnapshot(
            creditsUsed: 0,
            creditsTotal: 0,
            resetsAt: nil,
            planName: nil)

        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.usedPercent == 0.0)
    }

    @Test
    func formats_large_credit_values_with_comma_grouping() {
        let snapshot = AbacusUsageSnapshot(
            creditsUsed: 12345,
            creditsTotal: 50000,
            resetsAt: nil,
            planName: nil)

        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.resetDescription == "12,345 / 50,000 credits")
    }

    @Test
    func formats_fractional_credit_values() {
        let snapshot = AbacusUsageSnapshot(
            creditsUsed: 42.5,
            creditsTotal: 100,
            resetsAt: nil,
            planName: nil)

        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.resetDescription == "42.5 / 100 credits")
    }

    @Test
    func window_minutes_represents_monthly_cycle() {
        let snapshot = AbacusUsageSnapshot(
            creditsUsed: 0,
            creditsTotal: 100,
            resetsAt: nil,
            planName: nil)

        let usage = snapshot.toUsageSnapshot()
        // 30 days * 24 hours * 60 minutes = 43200
        #expect(usage.primary?.windowMinutes == 43200)
    }

    @Test
    func identity_has_no_email_or_organization() {
        let snapshot = AbacusUsageSnapshot(
            creditsUsed: 0,
            creditsTotal: 100,
            resetsAt: nil,
            planName: "Pro")

        let usage = snapshot.toUsageSnapshot()
        #expect(usage.identity?.accountEmail == nil)
        #expect(usage.identity?.accountOrganization == nil)
    }
}

// MARK: - Error Description Tests

struct AbacusErrorTests {
    @Test
    func noSessionCookie_error_mentions_login() {
        let error = AbacusUsageError.noSessionCookie
        #expect(error.errorDescription?.contains("log in") == true)
    }

    @Test
    func sessionExpired_error_mentions_expired() {
        let error = AbacusUsageError.sessionExpired
        #expect(error.errorDescription?.contains("expired") == true)
    }

    @Test
    func networkError_includes_message() {
        let error = AbacusUsageError.networkError("HTTP 500")
        #expect(error.errorDescription?.contains("HTTP 500") == true)
    }

    @Test
    func parseFailed_includes_message() {
        let error = AbacusUsageError.parseFailed("Invalid JSON")
        #expect(error.errorDescription?.contains("Invalid JSON") == true)
    }

    @Test
    func unauthorized_error_mentions_login() {
        let error = AbacusUsageError.unauthorized
        #expect(error.errorDescription?.contains("log in") == true)
    }
}

// MARK: - Error Classification Tests

struct AbacusErrorClassificationTests {
    @Test
    func unauthorized_is_recoverable_and_auth_related() {
        let error = AbacusUsageError.unauthorized
        #expect(error.isRecoverable == true)
        #expect(error.isAuthRelated == true)
    }

    @Test
    func sessionExpired_is_recoverable_and_auth_related() {
        let error = AbacusUsageError.sessionExpired
        #expect(error.isRecoverable == true)
        #expect(error.isAuthRelated == true)
    }

    @Test
    func parseFailed_is_not_recoverable() {
        let error = AbacusUsageError.parseFailed("bad json")
        #expect(error.isRecoverable == false)
        #expect(error.isAuthRelated == false)
        #expect(error.shouldTryNextImportedSession == true)
        #expect(error.shouldClearCachedCookie == true)
    }

    @Test
    func networkError_is_not_recoverable() {
        let error = AbacusUsageError.networkError("timeout")
        #expect(error.isRecoverable == false)
        #expect(error.isAuthRelated == false)
        #expect(error.shouldTryNextImportedSession == true)
        #expect(error.shouldClearCachedCookie == false)
    }

    @Test
    func noSessionCookie_is_not_recoverable() {
        let error = AbacusUsageError.noSessionCookie
        #expect(error.isRecoverable == false)
        #expect(error.isAuthRelated == false)
        #expect(error.shouldTryNextImportedSession == false)
        #expect(error.shouldClearCachedCookie == false)
    }

    @Test
    func auth_failures_continue_imported_session_scanning() {
        #expect(AbacusUsageError.unauthorized.shouldTryNextImportedSession == true)
        #expect(AbacusUsageError.sessionExpired.shouldTryNextImportedSession == true)
        #expect(AbacusUsageError.unauthorized.shouldClearCachedCookie == true)
        #expect(AbacusUsageError.sessionExpired.shouldClearCachedCookie == true)
    }
}
