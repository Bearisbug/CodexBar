import CodexBarCore
import Foundation
import Testing

struct CopilotDeviceFlowTests {
    @Test
    func prefers_verification_uri_complete_when_available() throws {
        let response = try JSONDecoder().decode(
            CopilotDeviceFlow.DeviceCodeResponse.self,
            from: Data(
                """
                {
                  "device_code": "device-code",
                  "user_code": "ABCD-EFGH",
                  "verification_uri": "https://github.com/login/device",
                  "verification_uri_complete": "https://github.com/login/device?user_code=ABCD-EFGH",
                  "expires_in": 900,
                  "interval": 5
                }
                """.utf8))

        #expect(response.verificationURLToOpen == "https://github.com/login/device?user_code=ABCD-EFGH")
    }

    @Test
    func falls_back_to_verification_uri_when_complete_url_missing() throws {
        let response = try JSONDecoder().decode(
            CopilotDeviceFlow.DeviceCodeResponse.self,
            from: Data(
                """
                {
                  "device_code": "device-code",
                  "user_code": "ABCD-EFGH",
                  "verification_uri": "https://github.com/login/device",
                  "expires_in": 900,
                  "interval": 5
                }
                """.utf8))

        #expect(response.verificationURLToOpen == "https://github.com/login/device")
    }

    @Test
    func device_flow_uses_github_by_default() throws {
        let flow = CopilotDeviceFlow()
        let deviceCodeURL = try #require(flow.deviceCodeURL)
        let accessTokenURL = try #require(flow.accessTokenURL)

        #expect(deviceCodeURL.absoluteString == "https://github.com/login/device/code")
        #expect(accessTokenURL.absoluteString == "https://github.com/login/oauth/access_token")
    }

    @Test
    func device_flow_uses_enterprise_host() throws {
        let flow = CopilotDeviceFlow(enterpriseHost: "https://octocorp.ghe.com/login")
        let deviceCodeURL = try #require(flow.deviceCodeURL)
        let accessTokenURL = try #require(flow.accessTokenURL)

        #expect(deviceCodeURL.absoluteString == "https://octocorp.ghe.com/login/device/code")
        #expect(accessTokenURL.absoluteString == "https://octocorp.ghe.com/login/oauth/access_token")
    }

    @Test
    func device_flow_rejects_invalid_enterprise_host_without_crashing() {
        let flow = CopilotDeviceFlow(enterpriseHost: "foo bar")

        #expect(flow.deviceCodeURL == nil)
        #expect(flow.accessTokenURL == nil)
    }

    @Test
    func device_flow_preserves_enterprise_host_port() throws {
        let flow = CopilotDeviceFlow(enterpriseHost: "https://octocorp.ghe.com:8443/login")
        let deviceCodeURL = try #require(flow.deviceCodeURL)
        let accessTokenURL = try #require(flow.accessTokenURL)

        #expect(deviceCodeURL.absoluteString == "https://octocorp.ghe.com:8443/login/device/code")
        #expect(accessTokenURL.absoluteString == "https://octocorp.ghe.com:8443/login/oauth/access_token")
    }

    @Test
    func usage_url_uses_enterprise_api_host() throws {
        let defaultURL = try #require(CopilotUsageFetcher.usageURL(enterpriseHost: nil))
        let enterpriseURL = try #require(CopilotUsageFetcher.usageURL(enterpriseHost: "octocorp.ghe.com"))
        let enterprisePortURL = try #require(CopilotUsageFetcher.usageURL(enterpriseHost: "octocorp.ghe.com:8443"))

        #expect(defaultURL.absoluteString == "https://api.github.com/copilot_internal/user")
        #expect(enterpriseURL.absoluteString == "https://api.octocorp.ghe.com/copilot_internal/user")
        #expect(enterprisePortURL.absoluteString == "https://api.octocorp.ghe.com:8443/copilot_internal/user")
    }
}
