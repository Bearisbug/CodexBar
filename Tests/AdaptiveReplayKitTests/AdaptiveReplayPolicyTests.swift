import AdaptiveReplayKit
import Foundation
import Testing

struct AdaptiveReplayPolicyTests {
    private static let referenceNow = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func input(
        ageSeconds: TimeInterval?,
        lowPowerModeEnabled: Bool = false,
        thermalState: ReplayThermalState = .nominal) -> ReplayPolicyInput
    {
        ReplayPolicyInput(
            now: Self.referenceNow,
            lastMenuOpenAt: ageSeconds.map { Self.referenceNow.addingTimeInterval(-$0) },
            lowPowerModeEnabled: lowPowerModeEnabled,
            thermalState: thermalState)
    }

    @Test(arguments: [
        (0.0, "recentInteraction", 120.0),
        (301.0, "warm", 300.0),
        (3601.0, "idle", 900.0),
        (14400.0, "longIdle", 1800.0),
    ])
    func replay_adapter_preserves_canonical_decisions(
        ageSeconds: TimeInterval,
        expectedReason: String,
        expectedDelaySeconds: TimeInterval)
    {
        let decision = AdaptiveReplayPolicy().decide(self.input(ageSeconds: ageSeconds))
        #expect(decision.reason == expectedReason)
        #expect(decision.delaySeconds == expectedDelaySeconds)
    }

    @Test(arguments: [ReplayThermalState.serious, .critical])
    func replay_adapter_maps_serious_and_critical_thermal_states_to_constrained(
        thermalState: ReplayThermalState)
    {
        let decision = AdaptiveReplayPolicy().decide(self.input(ageSeconds: 0, thermalState: thermalState))
        #expect(decision.reason == "constrained")
        #expect(decision.delaySeconds == TimeInterval(30 * 60))
    }

    @Test
    func replay_adapter_preserves_low_power_precedence() {
        let decision = AdaptiveReplayPolicy().decide(self.input(
            ageSeconds: 0,
            lowPowerModeEnabled: true,
            thermalState: .nominal))
        #expect(decision.reason == "constrained")
        #expect(decision.delaySeconds == TimeInterval(30 * 60))
    }

    @Test(arguments: [ReplayThermalState.nominal, .fair])
    func replay_adapter_maps_nominal_and_fair_thermal_states_to_unconstrained(
        thermalState: ReplayThermalState)
    {
        let decision = AdaptiveReplayPolicy().decide(self.input(ageSeconds: 0, thermalState: thermalState))
        #expect(decision.reason == "recentInteraction")
        #expect(decision.delaySeconds == TimeInterval(2 * 60))
    }

    @Test
    func only_adaptive_replay_advances_on_interaction() {
        #expect(AdaptiveReplayPolicy().advancesOnInteraction)
        #expect(!FixedIntervalPolicy(minutes: 5).advancesOnInteraction)
        #expect(!ManualPolicy().advancesOnInteraction)
    }

    @Test
    func fixed_interval_conversion_cannot_overflow_integer_multiplication() {
        let decision = FixedIntervalPolicy(minutes: Int.max).decide(self.input(ageSeconds: 0))
        #expect(decision.delaySeconds == TimeInterval(Int.max) * 60)
        #expect(decision.delaySeconds?.isFinite == true)
    }
}
