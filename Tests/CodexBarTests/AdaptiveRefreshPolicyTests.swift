import Foundation
import Testing
@testable import CodexBar

struct AdaptiveRefreshPolicyTests {
    private static let referenceNow = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func decision(
        ageSeconds: TimeInterval? = 0,
        lowPowerModeEnabled: Bool,
        thermalState: ProcessInfo.ThermalState) -> AdaptiveRefreshPolicy.Decision
    {
        UsageStore.adaptiveRefreshDecision(
            now: Self.referenceNow,
            lastMenuOpenAt: ageSeconds.map { Self.referenceNow.addingTimeInterval(-$0) },
            lowPowerModeEnabled: lowPowerModeEnabled,
            thermalState: thermalState)
    }

    @Test(arguments: [ProcessInfo.ThermalState.nominal, .fair])
    func app_adapter_maps_nominal_and_fair_thermal_states_to_unconstrained(
        thermalState: ProcessInfo.ThermalState)
    {
        let decision = self.decision(lowPowerModeEnabled: false, thermalState: thermalState)
        #expect(decision.reason == .recentInteraction)
        #expect(decision.delay == .seconds(2 * 60))
    }

    @Test(arguments: [ProcessInfo.ThermalState.serious, .critical])
    func app_adapter_maps_serious_and_critical_thermal_states_to_constrained(
        thermalState: ProcessInfo.ThermalState)
    {
        let decision = self.decision(lowPowerModeEnabled: false, thermalState: thermalState)
        #expect(decision.reason == .constrained)
        #expect(decision.delay == .seconds(30 * 60))
    }

    @Test
    func app_adapter_preserves_low_power_precedence() {
        let decision = self.decision(lowPowerModeEnabled: true, thermalState: .nominal)
        #expect(decision.reason == .constrained)
        #expect(decision.delay == .seconds(30 * 60))
    }

    @Test
    func app_adapter_forwards_timestamps_and_nil_history() {
        let warm = self.decision(
            ageSeconds: 301,
            lowPowerModeEnabled: false,
            thermalState: .nominal)
        #expect(warm.reason == .warm)
        #expect(warm.delay == .seconds(5 * 60))

        let noHistory = self.decision(
            ageSeconds: nil,
            lowPowerModeEnabled: false,
            thermalState: .nominal)
        #expect(noHistory.reason == .longIdle)
        #expect(noHistory.delay == .seconds(30 * 60))
    }
}
