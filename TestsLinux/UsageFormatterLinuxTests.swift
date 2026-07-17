import CodexBarCore
import Testing

@Suite(.serialized)
struct UsageFormatterLinuxTests {
    @Test
    func rate_window_formatting_uses_the_standalone_English_fallback() {
        UsageFormatter.clearLocalizationProvider()
        UsageFormatter.clearLocaleProvider()

        #expect(UsageFormatter.usageLine(remaining: 25, used: 75, showUsed: false) == "25% left")
        #expect(UsageFormatter.usageLine(remaining: 25, used: 75, showUsed: true) == "75% used")
        #expect(UsageFormatter.usageLine(remaining: 0.75, used: 99.25, showUsed: false) == "<1% left")
    }
}
