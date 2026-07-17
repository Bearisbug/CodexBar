import Foundation
import Testing
@testable import CodexBarCore

struct KiloBearerTokenResolverTests {
    private func writeAuthFile(_ json: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kilo-resolver-tests-\(UUID().uuidString)", isDirectory: true)
        let kiloDir = directory
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("kilo", isDirectory: true)
        try FileManager.default.createDirectory(at: kiloDir, withIntermediateDirectories: true)
        let authURL = kiloDir.appendingPathComponent("auth.json", isDirectory: false)
        try json.write(to: authURL, atomically: true, encoding: .utf8)
        return directory
    }

    @Test
    func api_mode_uses_provided_apiKey() throws {
        let resolved = try KiloBearerTokenResolver.resolve(
            source: .api,
            apiKey: "kilo_abc",
            environment: [:])
        #expect(resolved.token == "kilo_abc")
        #expect(resolved.sourceLabel == "api")
    }

    @Test
    func api_mode_falls_back_to_KILO_API_KEY_env_var_when_apiKey_is_empty() throws {
        let resolved = try KiloBearerTokenResolver.resolve(
            source: .api,
            apiKey: nil,
            environment: ["KILO_API_KEY": "kilo_from_env"])
        #expect(resolved.token == "kilo_from_env")
        #expect(resolved.sourceLabel == "api")
    }

    @Test
    func api_mode_throws_missingCredentials_when_nothing_available() {
        #expect(throws: KiloUsageError.missingCredentials) {
            try KiloBearerTokenResolver.resolve(
                source: .api,
                apiKey: nil,
                environment: [:])
        }
    }

    @Test
    func cli_mode_reads_token_from_auth_json() throws {
        let home = try self.writeAuthFile(#"{ "kilo": { "access": "cli-token" } }"#)
        defer { try? FileManager.default.removeItem(at: home) }

        let resolved = try KiloBearerTokenResolver.resolve(
            source: .cli,
            apiKey: nil,
            environment: ["HOME": home.path])
        #expect(resolved.token == "cli-token")
        #expect(resolved.sourceLabel == "cli")
    }

    @Test
    func cli_mode_throws_cliSessionMissing_when_auth_json_missing() {
        let nonexistentHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("kilo-no-such-home-\(UUID().uuidString)", isDirectory: true)
        #expect(throws: (any Error).self) {
            try KiloBearerTokenResolver.resolve(
                source: .cli,
                apiKey: nil,
                environment: ["HOME": nonexistentHome.path])
        }
    }

    @Test
    func cli_mode_throws_cliSessionInvalid_for_malformed_JSON() throws {
        let home = try self.writeAuthFile(#"{ "kilo": { } }"#)
        defer { try? FileManager.default.removeItem(at: home) }

        #expect(throws: (any Error).self) {
            try KiloBearerTokenResolver.resolve(
                source: .cli,
                apiKey: nil,
                environment: ["HOME": home.path])
        }
    }

    @Test
    func auto_mode_prefers_API_key_when_available() throws {
        let home = try self.writeAuthFile(#"{ "kilo": { "access": "cli-token" } }"#)
        defer { try? FileManager.default.removeItem(at: home) }

        let resolved = try KiloBearerTokenResolver.resolve(
            source: .auto,
            apiKey: "kilo_api",
            environment: ["HOME": home.path])
        #expect(resolved.token == "kilo_api")
        #expect(resolved.sourceLabel == "api")
    }

    @Test
    func auto_mode_falls_back_to_CLI_when_API_key_missing() throws {
        let home = try self.writeAuthFile(#"{ "kilo": { "access": "cli-fallback" } }"#)
        defer { try? FileManager.default.removeItem(at: home) }

        let resolved = try KiloBearerTokenResolver.resolve(
            source: .auto,
            apiKey: nil,
            environment: ["HOME": home.path])
        #expect(resolved.token == "cli-fallback")
        #expect(resolved.sourceLabel == "cli")
    }

    @Test
    func auto_mode_surfaces_CLI_error_when_neither_path_available() {
        let nonexistentHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("kilo-no-such-home-\(UUID().uuidString)", isDirectory: true)
        #expect(throws: (any Error).self) {
            try KiloBearerTokenResolver.resolve(
                source: .auto,
                apiKey: nil,
                environment: ["HOME": nonexistentHome.path])
        }
    }
}
