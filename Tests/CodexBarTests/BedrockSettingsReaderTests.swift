import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct BedrockSettingsReaderTests {
    @Test
    func default_auth_mode_is_keys() {
        #expect(BedrockSettingsReader.authMode(environment: [:]) == .keys)
    }

    @Test
    func explicit_profile_auth_mode_wins() {
        let env = ["CODEXBAR_BEDROCK_AUTH_MODE": "profile"]
        #expect(BedrockSettingsReader.authMode(environment: env) == .profile)
    }

    @Test
    func AWS_PROFILE_without_keys_implies_profile_mode() {
        let env = ["AWS_PROFILE": "work"]
        #expect(BedrockSettingsReader.authMode(environment: env) == .profile)
        #expect(BedrockSettingsReader.profile(environment: env) == "work")
    }

    @Test
    func AWS_PROFILE_alongside_static_keys_keeps_keys_mode() {
        let env = [
            "AWS_PROFILE": "work",
            "AWS_ACCESS_KEY_ID": "AKIA",
            "AWS_SECRET_ACCESS_KEY": "secret",
        ]
        #expect(BedrockSettingsReader.authMode(environment: env) == .keys)
    }

    @Test
    func hasCredentials_in_profile_mode_requires_a_profile_name() {
        let withProfile = ["CODEXBAR_BEDROCK_AUTH_MODE": "profile", "AWS_PROFILE": "work"]
        let withoutProfile = ["CODEXBAR_BEDROCK_AUTH_MODE": "profile"]
        #expect(BedrockSettingsReader.hasCredentials(environment: withProfile))
        #expect(!BedrockSettingsReader.hasCredentials(environment: withoutProfile))
    }

    @Test
    func hasCredentials_in_keys_mode_requires_both_keys() {
        let both = ["AWS_ACCESS_KEY_ID": "AKIA", "AWS_SECRET_ACCESS_KEY": "secret"]
        let onlyAccess = ["AWS_ACCESS_KEY_ID": "AKIA"]
        #expect(BedrockSettingsReader.hasCredentials(environment: both))
        #expect(!BedrockSettingsReader.hasCredentials(environment: onlyAccess))
    }
}
