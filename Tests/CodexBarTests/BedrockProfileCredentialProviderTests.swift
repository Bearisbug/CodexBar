import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct BedrockProfileCredentialProviderTests {
    private func provider(
        stdout: String = "",
        stderr: String = "",
        throwsNonZero: Bool = false) -> BedrockProfileCredentialProvider
    {
        BedrockProfileCredentialProvider(awsBinaryPath: "/usr/bin/aws") { _, _ in
            if throwsNonZero {
                throw SubprocessRunnerError.nonZeroExit(code: 1, stderr: stderr)
            }
            return SubprocessResult(stdout: stdout, stderr: stderr)
        }
    }

    @Test
    func parses_export_credentials_json_with_session_token() async throws {
        let json = """
        {"Version":1,"AccessKeyId":"AKIA","SecretAccessKey":"secret",\
        "SessionToken":"token","Expiration":"2026-05-27T12:00:00Z"}
        """
        let creds = try await provider(stdout: json).exportCredentials(profile: "work")
        #expect(creds.accessKeyID == "AKIA")
        #expect(creds.secretAccessKey == "secret")
        #expect(creds.sessionToken == "token")
    }

    @Test
    func parses_export_credentials_json_without_session_token() async throws {
        let json = #"{"Version":1,"AccessKeyId":"AKIA","SecretAccessKey":"secret"}"#
        let creds = try await provider(stdout: json).exportCredentials(profile: "work")
        #expect(creds.accessKeyID == "AKIA")
        #expect(creds.sessionToken == nil)
    }

    @Test
    func maps_expired_SSO_stderr_to_profileSessionExpired() async {
        let stderr = "The SSO session associated with this profile has expired. " +
            "To refresh this SSO session run aws sso login with the corresponding profile."
        let sut = self.provider(stderr: stderr, throwsNonZero: true)
        await #expect(throws: BedrockUsageError.profileSessionExpired("work")) {
            try await sut.exportCredentials(profile: "work")
        }
    }

    @Test
    func maps_other_non_zero_exit_to_apiError() async {
        let sut = self.provider(stderr: "The config profile (work) could not be found", throwsNonZero: true)
        do {
            _ = try await sut.exportCredentials(profile: "work")
            Issue.record("expected an error")
        } catch let error as BedrockUsageError {
            if case .apiError = error { } else { Issue.record("expected apiError, got \(error)") }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test
    func malformed_json_throws_parseFailed() async {
        let sut = self.provider(stdout: "not json")
        do {
            _ = try await sut.exportCredentials(profile: "work")
            Issue.record("expected an error")
        } catch let error as BedrockUsageError {
            if case .parseFailed = error { } else { Issue.record("expected parseFailed, got \(error)") }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test
    func resolveRegion_returns_trimmed_value() async throws {
        let region = try await provider(stdout: "eu-west-1\n").resolveRegion(profile: "work")
        #expect(region == "eu-west-1")
    }

    @Test
    func resolveRegion_returns_nil_when_unset_non_zero_exit() async throws {
        let region = try await provider(throwsNonZero: true).resolveRegion(profile: "work")
        #expect(region == nil)
    }

    @Test
    func resolveRegion_returns_nil_for_empty_output() async throws {
        let region = try await provider(stdout: "\n").resolveRegion(profile: "work")
        #expect(region == nil)
    }
}
