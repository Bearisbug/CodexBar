import Testing
@testable import CodexBar

struct UpdateChannelTests {
    @Test
    func default_channel_from_stable_version() {
        #expect(UpdateChannel.defaultChannel(for: "1.2.3") == .stable)
    }

    @Test
    func default_channel_from_prerelease_version() {
        #expect(UpdateChannel.defaultChannel(for: "1.2.3-beta.1") == .beta)
        #expect(UpdateChannel.defaultChannel(for: "1.2.3-rc.1") == .beta)
        #expect(UpdateChannel.defaultChannel(for: "1.2.3-alpha") == .beta)
    }

    @Test
    func allowed_sparkle_channels() {
        #expect(UpdateChannel.stable.allowedSparkleChannels == [""])
        #expect(UpdateChannel.beta.allowedSparkleChannels == ["", UpdateChannel.sparkleBetaChannel])
    }
}
