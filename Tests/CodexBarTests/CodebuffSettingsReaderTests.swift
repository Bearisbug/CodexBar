import CodexBarCore
import Foundation
import Testing

struct CodebuffSettingsReaderTests {
    @Test
    func api_URL_defaults_to_www_codebuff_com() {
        let url = CodebuffSettingsReader.apiURL(environment: [:])
        #expect(url.scheme == "https")
        #expect(url.host() == "www.codebuff.com")
    }

    @Test
    func api_URL_honors_environment_override() {
        let url = CodebuffSettingsReader.apiURL(environment: [
            "CODEBUFF_API_URL": "https://staging.codebuff.com",
        ])
        #expect(url.host() == "staging.codebuff.com")
    }

    @Test
    func api_key_reads_from_CODEBUFF_API_KEY_and_trims_wrapping_whitespace() {
        let token = CodebuffSettingsReader.apiKey(environment: [
            CodebuffSettingsReader.apiTokenKey: "  cb-test-token  ",
        ])
        #expect(token == "cb-test-token")
    }

    @Test
    func api_key_strips_surrounding_quotes() {
        let token = CodebuffSettingsReader.apiKey(environment: [
            CodebuffSettingsReader.apiTokenKey: "\"cb-test-token\"",
        ])
        #expect(token == "cb-test-token")
    }

    @Test
    func api_key_returns_nil_for_empty_environment() {
        #expect(CodebuffSettingsReader.apiKey(environment: [:]) == nil)
    }

    @Test
    func auth_token_parses_credentials_json() throws {
        let contents = #"{"authToken":"file-token","fingerprintId":"fp-1","email":"a@b.com"}"#
        let url = try self.writeTempFile(named: "credentials.json", contents: contents)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let token = CodebuffSettingsReader.authToken(authFileURL: url)
        #expect(token == "file-token")
    }

    @Test
    func auth_token_parses_default_profile_credentials_json() throws {
        let contents = #"{"default":{"authToken":"default-token","fingerprintId":"fp-1","email":"a@b.com"}}"#
        let url = try self.writeTempFile(named: "credentials.json", contents: contents)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let token = CodebuffSettingsReader.authToken(authFileURL: url)
        #expect(token == "default-token")
    }

    @Test
    func auth_token_returns_nil_for_malformed_credentials_json() throws {
        let url = try self.writeTempFile(named: "credentials.json", contents: "{not-json}")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let token = CodebuffSettingsReader.authToken(authFileURL: url)
        #expect(token == nil)
    }

    @Test
    func auth_token_returns_nil_when_file_missing() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("credentials.json", isDirectory: false)
        #expect(CodebuffSettingsReader.authToken(authFileURL: url) == nil)
    }

    @Test
    func descriptor_uses_codebuff_dashboard_URL() {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .codebuff)
        #expect(descriptor.metadata.dashboardURL == "https://www.codebuff.com/usage")
        #expect(descriptor.metadata.displayName == "Codebuff")
        #expect(descriptor.metadata.cliName == "codebuff")
    }

    @Test
    func descriptor_uses_dedicated_codebuff_icon_resource() {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .codebuff)
        #expect(descriptor.branding.iconResourceName == "ProviderIcon-codebuff")
    }

    @Test
    func descriptor_supports_auto_and_API_source_modes() {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .codebuff)
        let expected: Set<ProviderSourceMode> = [.auto, .api]
        #expect(descriptor.fetchPlan.sourceModes == expected)
    }

    // MARK: - Helpers

    private func writeTempFile(named name: String, contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(name, isDirectory: false)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
