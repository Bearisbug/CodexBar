import CodexBarCore
import Foundation
import Testing

struct CodexSessionRolloutTests {
    @Test
    func first_rollout_line_maps_to_file_only_agent_session() throws {
        let url = try AgentSessionParserTests.fixtureURL("agent-session-rollout", extension: "jsonl")
        let metadata = try #require(CodexRolloutFirstLineParser.read(from: url))
        let now = Date(timeIntervalSince1970: 10000)
        let modifiedAt = now.addingTimeInterval(-60)
        let session = try #require(CodexRolloutFirstLineParser.makeSession(
            metadata: metadata,
            transcriptURL: url,
            modifiedAt: modifiedAt,
            host: "local-mac",
            now: now))

        #expect(session.id == "019f-session-fixture")
        #expect(session.cwd == "/Users/test/Projects/alpha")
        #expect(session.projectName == "alpha")
        #expect(session.source == .cli)
        #expect(session.state == .active)
        #expect(session.pid == nil)
    }

    @Test
    func file_only_rollout_outside_window_is_excluded_while_live_process_remains() throws {
        let url = try AgentSessionParserTests.fixtureURL("agent-session-rollout", extension: "jsonl")
        let metadata = try #require(CodexRolloutFirstLineParser.read(from: url))
        let now = Date(timeIntervalSince1970: 10000)
        let modifiedAt = now.addingTimeInterval(-1801)

        #expect(CodexRolloutFirstLineParser.makeSession(
            metadata: metadata,
            transcriptURL: url,
            modifiedAt: modifiedAt,
            host: "local-mac",
            now: now) == nil)
        #expect(CodexRolloutFirstLineParser.makeSession(
            metadata: metadata,
            transcriptURL: url,
            modifiedAt: modifiedAt,
            pid: 42,
            host: "local-mac",
            now: now)?.state == .idle)
    }

    @Test
    func app_server_presence_classifies_unknown_file_only_rollout_as_desktop() {
        #expect(AgentSessionCorrelation.fileOnlyCodexSource(
            metadataSource: .unknown,
            appServerPresent: true) == .desktopApp)
        #expect(AgentSessionCorrelation.fileOnlyCodexSource(
            metadataSource: .unknown,
            appServerPresent: false) == .unknown)
    }

    @Test
    func codex_cwd_matching_rejects_missing_paths() {
        #expect(AgentSessionCorrelation.codexWorkingDirectoriesMatch("/repo/alpha", "/repo/./alpha"))
        #expect(!AgentSessionCorrelation.codexWorkingDirectoriesMatch(nil, nil))
        #expect(!AgentSessionCorrelation.codexWorkingDirectoriesMatch("/repo/alpha", nil))
    }
}
