import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct AgentSessionMenuDescriptorTests {
    @Test
    func fresh_settings_omit_agent_sessions_until_explicitly_enabled() {
        let settings = testSettingsStore(suiteName: "AgentSessionMenuDescriptorTests-default-off")
        settings.statusChecksEnabled = false
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let session = Self.session(id: "local", host: "local-mac", activity: Date())

        let buildDescriptor = {
            MenuDescriptor.build(
                provider: .codex,
                store: store,
                settings: settings,
                account: AccountInfo(email: nil, plan: nil),
                updateReady: false,
                agentSessionsEnabled: settings.agentSessionsEnabled,
                localAgentSessions: [session])
        }

        let disabledEntries = buildDescriptor().sections.flatMap(\.entries)
        #expect(!Self.containsAgentSessions(in: disabledEntries))

        settings.agentSessionsEnabled = true

        let enabledEntries = buildDescriptor().sections.flatMap(\.entries)
        #expect(Self.containsAgentSessions(in: enabledEntries))
        #expect(enabledEntries.contains { entry in
            guard case .action(_, .focusAgentSession) = entry else { return false }
            return true
        })
    }

    @Test
    func session_section_counts_groups_and_renders_unreachable_hosts() {
        let now = Date(timeIntervalSince1970: 1000)
        let local = Self.session(id: "local", host: "local-mac", activity: now.addingTimeInterval(-60))
        let remote = Self.session(id: "remote", host: "clawmac", activity: now.addingTimeInterval(-720))
        let section = MenuDescriptor.agentSessionsSection(
            localSessions: [local],
            remoteHosts: [
                RemoteSessionHostResult(host: "clawmac", sessions: [remote], error: nil),
                RemoteSessionHostResult(host: "offline", sessions: [], error: "Connection timed out"),
            ],
            now: now)

        guard case let .text(header, .headline) = section.entries[0] else {
            Issue.record("Expected session headline")
            return
        }
        #expect(header == "Agent Sessions (2)")
        guard case let .action(localTitle, .focusAgentSession(_, remoteHost)) = section.entries[1] else {
            Issue.record("Expected local session action")
            return
        }
        #expect(localTitle.contains("alpha — codex · cli · 1m"))
        #expect(remoteHost == nil)
        guard case let .text(remoteGroup, .secondary) = section.entries[2] else {
            Issue.record("Expected remote group")
            return
        }
        #expect(remoteGroup == "clawmac — 1")
        guard case let .unavailable(title, tooltip) = section.entries[4] else {
            Issue.record("Expected unreachable host")
            return
        }
        #expect(title == "offline — unreachable")
        #expect(tooltip == "Connection timed out")
    }

    @Test
    func reachable_empty_remote_host_keeps_zero_count_section_actionable() {
        let section = MenuDescriptor.agentSessionsSection(
            localSessions: [],
            remoteHosts: [RemoteSessionHostResult(host: "clawmac", sessions: [], error: nil)])

        #expect(section.entries.contains { entry in
            guard case let .unavailable(title, _) = entry else { return false }
            return title == "No agent sessions found"
        })
    }

    @Test
    func remote_refresh_gate_retries_changed_settings_and_rejects_stale_result() throws {
        var gate = AgentSessionRemoteRefreshGate()
        let initialGenerationCandidate = gate.begin()
        let initialGeneration = try #require(initialGenerationCandidate)
        gate.settingsDidChange()
        #expect(gate.begin() == nil)

        let staleOutcome = gate.finish(generation: initialGeneration)
        #expect(!staleOutcome.shouldPublish)
        #expect(staleOutcome.shouldRetry)

        let currentGenerationCandidate = gate.begin()
        let currentGeneration = try #require(currentGenerationCandidate)
        let currentOutcome = gate.finish(generation: currentGeneration)
        #expect(currentOutcome.shouldPublish)
        #expect(!currentOutcome.shouldRetry)
    }

    @Test
    func remote_refresh_gate_coalesces_ordinary_overlaps_without_retry() throws {
        var gate = AgentSessionRemoteRefreshGate()
        let generationCandidate = gate.begin()
        let generation = try #require(generationCandidate)
        #expect(gate.begin() == nil)

        let outcome = gate.finish(generation: generation)
        #expect(outcome.shouldPublish)
        #expect(!outcome.shouldRetry)
    }

    @Test
    func remote_refresh_gate_coalesces_multiple_ordinary_overlaps_into_one_pass() throws {
        var gate = AgentSessionRemoteRefreshGate()
        let generationCandidate = gate.begin()
        let generation = try #require(generationCandidate)
        for _ in 0..<5 {
            #expect(gate.begin() == nil)
        }

        let outcome = gate.finish(generation: generation)
        #expect(outcome.shouldPublish)
        #expect(!outcome.shouldRetry)
        #expect(Self.remotePassCount(for: .ordinaryOverlaps(count: 5)) == 1)
    }

    @Test
    func remote_refresh_gate_still_retries_after_ordinary_overlap_then_settings_change() throws {
        var gate = AgentSessionRemoteRefreshGate()
        let staleGenerationCandidate = gate.begin()
        let staleGeneration = try #require(staleGenerationCandidate)
        #expect(gate.begin() == nil)
        gate.settingsDidChange()

        let staleOutcome = gate.finish(generation: staleGeneration)
        #expect(!staleOutcome.shouldPublish)
        #expect(staleOutcome.shouldRetry)

        let currentGenerationCandidate = gate.begin()
        let currentGeneration = try #require(currentGenerationCandidate)
        let currentOutcome = gate.finish(generation: currentGeneration)
        #expect(currentOutcome.shouldPublish)
        #expect(!currentOutcome.shouldRetry)
        #expect(Self.remotePassCount(for: .ordinaryOverlapThenSettingsChange) == 2)
    }

    @Test
    func remote_refresh_gate_pass_counts_stay_at_one_for_overlap_and_two_for_settings_change() {
        #expect(Self.remotePassCount(for: .ordinaryOverlaps(count: 1)) == 1)
        #expect(Self.remotePassCount(for: .settingsChangeDuringFlight) == 2)
    }

    private static func session(id: String, host: String, activity: Date) -> AgentSession {
        AgentSession(
            id: id,
            provider: .codex,
            source: .cli,
            state: .active,
            pid: 42,
            cwd: "/Users/test/alpha",
            projectName: "alpha",
            startedAt: nil,
            lastActivityAt: activity,
            transcriptPath: nil,
            host: host)
    }

    private static func containsAgentSessions(in entries: [MenuDescriptor.Entry]) -> Bool {
        entries.contains { entry in
            guard case let .text(title, .headline) = entry else { return false }
            return title.hasPrefix("Agent Sessions (")
        }
    }

    private enum RemoteRefreshScenario {
        case ordinaryOverlaps(count: Int)
        case settingsChangeDuringFlight
        case ordinaryOverlapThenSettingsChange
    }

    /// Pure state-machine pass counter: each successful `begin()`/`finish()` pair is one remote pass.
    private static func remotePassCount(for scenario: RemoteRefreshScenario) -> Int {
        var gate = AgentSessionRemoteRefreshGate()
        var passes = 0

        guard let generation = gate.begin() else { return 0 }
        passes += 1

        switch scenario {
        case let .ordinaryOverlaps(count):
            for _ in 0..<count {
                _ = gate.begin()
            }
        case .settingsChangeDuringFlight:
            gate.settingsDidChange()
        case .ordinaryOverlapThenSettingsChange:
            _ = gate.begin()
            gate.settingsDidChange()
        }

        let outcome = gate.finish(generation: generation)
        guard outcome.shouldRetry, let nextGeneration = gate.begin() else {
            return passes
        }
        passes += 1
        _ = gate.finish(generation: nextGeneration)
        return passes
    }
}
