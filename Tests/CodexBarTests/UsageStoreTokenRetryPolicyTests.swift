import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct UsageStoreTokenRetryPolicyTests {
    @Test
    func timed_out_token_scans_keep_the_fetch_TTL_while_fast_failures_retry_early() {
        #expect(!UsageStore.tokenFetchFailureAllowsEarlyRetry(CostUsageError.timedOut(seconds: 600)))
        #expect(UsageStore.tokenFetchFailureAllowsEarlyRetry(CocoaError(.fileReadNoSuchFile)))
    }
}
