import Testing
@testable import CodexBarCore

struct GeminiSourceLabelTests {
    @Test
    func Gemini_source_label_reflects_OAuth_backed_API_requests() {
        #expect(GeminiStatusFetchStrategy.sourceLabel == "oauth-api")
    }
}
