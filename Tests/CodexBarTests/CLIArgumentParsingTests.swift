import CodexBarCore
import Commander
import Foundation
import Testing
@testable import CodexBarCLI

struct CLIArgumentParsingTests {
    @Test
    func json_shortcut_does_not_enable_json_logs() throws {
        let signature = CodexBarCLI._usageSignatureForTesting()
        let parser = CommandParser(signature: signature)
        let parsed = try parser.parse(arguments: ["--json"])

        #expect(parsed.flags.contains("jsonShortcut"))
        #expect(!parsed.flags.contains("jsonOutput"))
        #expect(CodexBarCLI._decodeFormatForTesting(from: parsed) == .json)
    }

    @Test
    func json_output_flag_enables_json_logs() throws {
        let signature = CodexBarCLI._usageSignatureForTesting()
        let parser = CommandParser(signature: signature)
        let parsed = try parser.parse(arguments: ["--json-output"])

        #expect(parsed.flags.contains("jsonOutput"))
        #expect(!parsed.flags.contains("jsonShortcut"))
        #expect(CodexBarCLI._decodeFormatForTesting(from: parsed) == .text)
    }

    @Test
    func log_level_and_verbose_are_parsed() throws {
        let signature = CodexBarCLI._usageSignatureForTesting()
        let parser = CommandParser(signature: signature)
        let parsed = try parser.parse(arguments: ["--log-level", "info", "--verbose"])

        #expect(parsed.flags.contains("verbose"))
        #expect(parsed.options["logLevel"] == ["info"])
    }

    @Test
    func resolved_log_level_defaults_to_error() {
        #expect(CodexBarCLI.resolvedLogLevel(verbose: false, rawLevel: nil) == .error)
        #expect(CodexBarCLI.resolvedLogLevel(verbose: true, rawLevel: nil) == .debug)
        #expect(CodexBarCLI.resolvedLogLevel(verbose: false, rawLevel: "info") == .info)
    }

    @Test
    func format_option_overrides_json_shortcut() throws {
        let signature = CodexBarCLI._usageSignatureForTesting()
        let parser = CommandParser(signature: signature)
        let parsed = try parser.parse(arguments: ["--json", "--format", "text"])

        #expect(parsed.flags.contains("jsonShortcut"))
        #expect(parsed.options["format"] == ["text"])
        #expect(CodexBarCLI._decodeFormatForTesting(from: parsed) == .text)
    }

    @Test
    func json_only_enables_json_format() throws {
        let signature = CodexBarCLI._usageSignatureForTesting()
        let parser = CommandParser(signature: signature)
        let parsed = try parser.parse(arguments: ["--json-only"])

        #expect(parsed.flags.contains("jsonOnly"))
        #expect(!parsed.flags.contains("jsonOutput"))
        #expect(CodexBarCLI._decodeFormatForTesting(from: parsed) == .json)
    }

    @Test
    func diagnose_accepts_json_output_flag_but_discards_provider_logs() throws {
        let signature = CodexBarCLI._diagnoseSignatureForTesting()
        let parser = CommandParser(signature: signature)
        let parsed = try parser.parse(arguments: [
            "--provider", "minimax",
            "--format", "json",
            "--json-output",
        ])

        #expect(parsed.flags.contains("jsonOutput"))
        let config = CodexBarCLI.loggingConfiguration(path: ["diagnose"], values: parsed)
        switch config.destination {
        case .discard:
            break
        case .stderr, .oslog:
            Issue.record("diagnose should not emit provider logs beside the safe JSON export")
        }
    }

    @Test
    func diagnose_accepts_explicit_redact_and_output_path() throws {
        let signature = CodexBarCLI._diagnoseSignatureForTesting()
        let parser = CommandParser(signature: signature)
        let parsed = try parser.parse(arguments: [
            "--provider", "minimax",
            "--format", "json",
            "--redact",
            "--output", "diagnostic.json",
        ])

        #expect(parsed.flags.contains("redact"))
        #expect(parsed.options["output"] == ["diagnostic.json"])
    }

    @Test
    func Claude_OAuth_usage_does_not_detect_CLI_version() {
        #expect(!CodexBarCLI.shouldDetectVersion(
            provider: .claude,
            result: self.makeResult(kind: .oauth)))
        #expect(CodexBarCLI.shouldDetectVersion(
            provider: .claude,
            result: self.makeResult(kind: .cli)))
        #expect(CodexBarCLI.shouldDetectVersion(
            provider: .codex,
            result: self.makeResult(kind: .oauth)))
    }

    private func makeResult(kind: ProviderFetchKind) -> ProviderFetchResult {
        ProviderFetchResult(
            usage: UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 0)),
            credits: nil,
            dashboard: nil,
            sourceLabel: "test",
            strategyID: "test",
            strategyKind: kind)
    }
}
