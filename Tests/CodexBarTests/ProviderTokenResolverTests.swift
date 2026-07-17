import CodexBarCore
import Foundation
import Testing

struct ProviderTokenResolverTests {
    @Test
    func zai_resolution_uses_environment_token() {
        let env = [ZaiSettingsReader.apiTokenKey: "token"]
        let resolution = ProviderTokenResolver.zaiResolution(environment: env)
        #expect(resolution?.token == "token")
        #expect(resolution?.source == .environment)
    }

    @Test
    func copilot_resolution_trims_token() {
        let env = ["COPILOT_API_TOKEN": "  token  "]
        let resolution = ProviderTokenResolver.copilotResolution(environment: env)
        #expect(resolution?.token == "token")
    }

    @Test
    func warp_resolution_uses_environment_token() {
        let env = ["WARP_API_KEY": "wk-test-token"]
        let resolution = ProviderTokenResolver.warpResolution(environment: env)
        #expect(resolution?.token == "wk-test-token")
        #expect(resolution?.source == .environment)
    }

    @Test
    func warp_resolution_trims_token() {
        let env = ["WARP_API_KEY": "  wk-token  "]
        let resolution = ProviderTokenResolver.warpResolution(environment: env)
        #expect(resolution?.token == "wk-token")
    }

    @Test
    func warp_resolution_returns_nil_when_missing() {
        let env: [String: String] = [:]
        let resolution = ProviderTokenResolver.warpResolution(environment: env)
        #expect(resolution == nil)
    }

    @Test
    func doubao_resolution_uses_first_supported_environment_token() {
        let env = ["ARK_API_KEY": "ark-token"]
        let resolution = ProviderTokenResolver.doubaoResolution(environment: env)
        #expect(resolution?.token == "ark-token")
        #expect(resolution?.source == .environment)
    }

    @Test
    func doubao_settings_reader_trims_quoted_token() {
        let env = ["DOUBAO_API_KEY": " 'doubao-token' "]
        #expect(DoubaoSettingsReader.apiKey(environment: env) == "doubao-token")
    }

    @Test
    func kilo_resolution_prefers_environment_over_auth_file() throws {
        let fileURL = try self.makeKiloAuthFile(contents: #"{"kilo":{"access":"file-token"}}"#)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let env = [KiloSettingsReader.apiTokenKey: "env-token"]
        let resolution = ProviderTokenResolver.kiloResolution(environment: env, authFileURL: fileURL)

        #expect(resolution?.token == "env-token")
        #expect(resolution?.source == .environment)
    }

    @Test
    func kilo_resolution_falls_back_to_auth_file() throws {
        let fileURL = try self.makeKiloAuthFile(contents: #"{"kilo":{"access":"file-token"}}"#)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let resolution = ProviderTokenResolver.kiloResolution(environment: [:], authFileURL: fileURL)

        #expect(resolution?.token == "file-token")
        #expect(resolution?.source == .authFile)
    }

    @Test
    func kilo_resolution_returns_nil_for_malformed_auth_file() throws {
        let fileURL = try self.makeKiloAuthFile(contents: #"{not-json}"#)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let resolution = ProviderTokenResolver.kiloResolution(environment: [:], authFileURL: fileURL)
        #expect(resolution == nil)
    }

    private func makeKiloAuthFile(contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("auth.json", isDirectory: false)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    @Test
    func codebuff_resolution_prefers_environment_over_credentials_file() throws {
        let fileURL = try self.makeCodebuffCredentialsFile(
            contents: #"{"authToken":"file-token"}"#)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let env = [CodebuffSettingsReader.apiTokenKey: "env-token"]
        let resolution = ProviderTokenResolver.codebuffResolution(
            environment: env,
            authFileURL: fileURL)

        #expect(resolution?.token == "env-token")
        #expect(resolution?.source == .environment)
    }

    @Test
    func codebuff_resolution_falls_back_to_credentials_file() throws {
        let fileURL = try self.makeCodebuffCredentialsFile(
            contents: #"{"authToken":"file-token","fingerprintId":"fp"}"#)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let resolution = ProviderTokenResolver.codebuffResolution(
            environment: [:],
            authFileURL: fileURL)

        #expect(resolution?.token == "file-token")
        #expect(resolution?.source == .authFile)
    }

    @Test
    func codebuff_resolution_returns_nil_for_malformed_credentials_file() throws {
        let fileURL = try self.makeCodebuffCredentialsFile(contents: #"{not-json}"#)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let resolution = ProviderTokenResolver.codebuffResolution(
            environment: [:],
            authFileURL: fileURL)
        #expect(resolution == nil)
    }

    @Test
    func poe_resolution_uses_manual_api_key() {
        let env = [PoeSettingsReader.apiKeyEnvironmentKey: "manual-key"]
        let resolution = ProviderTokenResolver.poeResolution(environment: env)
        #expect(resolution?.token == "manual-key")
        #expect(resolution?.source == .environment)
    }

    private func makeCodebuffCredentialsFile(contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("credentials.json", isDirectory: false)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
