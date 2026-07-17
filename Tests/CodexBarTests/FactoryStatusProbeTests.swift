import Foundation
import Testing
@testable import CodexBarCore

struct FactoryProviderDescriptorTests {
    @Test
    func descriptor_keeps_legacy_labels_by_default() {
        let metadata = FactoryProviderDescriptor.descriptor.metadata

        #expect(metadata.sessionLabel == "Standard")
        #expect(metadata.weeklyLabel == "Premium")
        #expect(metadata.opusLabel == nil)
        #expect(!metadata.supportsOpus)
    }
}

struct FactoryStatusSnapshotTests {
    @Test
    func maps_usage_snapshot_windows_and_login_method() {
        let periodEnd = Date(timeIntervalSince1970: 1_738_368_000) // Feb 1, 2025
        let snapshot = FactoryStatusSnapshot(
            standardUserTokens: 50,
            standardOrgTokens: 0,
            standardAllowance: 100,
            premiumUserTokens: 25,
            premiumOrgTokens: 0,
            premiumAllowance: 50,
            periodStart: nil,
            periodEnd: periodEnd,
            planName: "Pro",
            tier: "enterprise",
            organizationName: "Acme",
            accountEmail: "user@example.com",
            userId: "user-1",
            rawJSON: nil)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 50)
        #expect(usage.primary?.resetsAt == periodEnd)
        #expect(usage.primary?.resetDescription?.hasPrefix("Resets ") == true)
        #expect(usage.secondary?.usedPercent == 50)
        #expect(usage.loginMethod(for: .factory) == "Factory Enterprise - Pro")
    }

    @Test
    func treats_large_allowances_as_unlimited() {
        let snapshot = FactoryStatusSnapshot(
            standardUserTokens: 50_000_000,
            standardOrgTokens: 0,
            standardAllowance: 2_000_000_000_000,
            premiumUserTokens: 0,
            premiumOrgTokens: 0,
            premiumAllowance: 0,
            periodStart: nil,
            periodEnd: nil,
            planName: nil,
            tier: nil,
            organizationName: nil,
            accountEmail: nil,
            userId: nil,
            rawJSON: nil)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 50)
    }

    @Test
    func prefers_API_used_ratio_when_allowance_missing() {
        let snapshot = FactoryStatusSnapshot(
            standardUserTokens: 72_311_737,
            standardOrgTokens: 72_311_737,
            standardAllowance: 0,
            standardUsedRatio: 0.3615586850,
            premiumUserTokens: 0,
            premiumOrgTokens: 0,
            premiumAllowance: 0,
            premiumUsedRatio: 0.0,
            periodStart: nil,
            periodEnd: nil,
            planName: "Max",
            tier: nil,
            organizationName: nil,
            accountEmail: nil,
            userId: nil,
            rawJSON: nil)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent ?? 0 > 36)
        #expect(usage.primary?.usedPercent ?? 0 < 37)
    }

    @Test
    func uses_percent_scale_ratio_when_allowance_missing() {
        let snapshot = FactoryStatusSnapshot(
            standardUserTokens: 0,
            standardOrgTokens: 0,
            standardAllowance: 0,
            standardUsedRatio: 10.0,
            premiumUserTokens: 0,
            premiumOrgTokens: 0,
            premiumAllowance: 0,
            premiumUsedRatio: nil,
            periodStart: nil,
            periodEnd: nil,
            planName: nil,
            tier: nil,
            organizationName: nil,
            accountEmail: nil,
            userId: nil,
            rawJSON: nil)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 10)
    }

    @Test
    func falls_back_to_calculation_when_API_ratio_is_zero_but_usage_and_allowance_are_present() {
        let snapshot = FactoryStatusSnapshot(
            standardUserTokens: 5_826_293,
            standardOrgTokens: 0,
            standardAllowance: 20_000_000,
            standardUsedRatio: 0,
            premiumUserTokens: 0,
            premiumOrgTokens: 0,
            premiumAllowance: 0,
            premiumUsedRatio: 0,
            periodStart: nil,
            periodEnd: nil,
            planName: nil,
            tier: nil,
            organizationName: nil,
            accountEmail: nil,
            userId: nil,
            rawJSON: nil)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent ?? 0 > 29)
        #expect(usage.primary?.usedPercent ?? 0 < 30)
        #expect(usage.secondary?.usedPercent == 0)
    }

    @Test
    func falls_back_to_calculation_when_API_ratio_missing() {
        let snapshot = FactoryStatusSnapshot(
            standardUserTokens: 50_000_000,
            standardOrgTokens: 0,
            standardAllowance: 100_000_000,
            standardUsedRatio: nil,
            premiumUserTokens: 0,
            premiumOrgTokens: 0,
            premiumAllowance: 0,
            premiumUsedRatio: nil,
            periodStart: nil,
            periodEnd: nil,
            planName: nil,
            tier: nil,
            organizationName: nil,
            accountEmail: nil,
            userId: nil,
            rawJSON: nil)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 50)
    }

    @Test
    func falls_back_when_API_ratio_is_invalid() {
        let snapshot = FactoryStatusSnapshot(
            standardUserTokens: 50_000_000,
            standardOrgTokens: 0,
            standardAllowance: 100_000_000,
            standardUsedRatio: 1.5,
            premiumUserTokens: 0,
            premiumOrgTokens: 0,
            premiumAllowance: 0,
            premiumUsedRatio: -0.5,
            periodStart: nil,
            periodEnd: nil,
            planName: nil,
            tier: nil,
            organizationName: nil,
            accountEmail: nil,
            userId: nil,
            rawJSON: nil)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 50)
    }

    @Test
    func clamps_slightly_out_of_range_ratios() {
        let snapshot = FactoryStatusSnapshot(
            standardUserTokens: 100_000_000,
            standardOrgTokens: 0,
            standardAllowance: 100_000_000,
            standardUsedRatio: 1.0005,
            premiumUserTokens: 0,
            premiumOrgTokens: 0,
            premiumAllowance: 0,
            premiumUsedRatio: nil,
            periodStart: nil,
            periodEnd: nil,
            planName: nil,
            tier: nil,
            organizationName: nil,
            accountEmail: nil,
            userId: nil,
            rawJSON: nil)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 100)
    }
}

struct FactoryStatusProbeWorkOSTests {
    @Test
    func detects_missing_refresh_token_payload() {
        let payload = Data("""
        {"error":"invalid_request","error_description":"Missing refresh token."}
        """.utf8)

        #expect(FactoryStatusProbe.isMissingWorkOSRefreshToken(payload))
    }
}
