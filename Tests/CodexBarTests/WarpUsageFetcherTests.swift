import Foundation
import Testing
@testable import CodexBarCore

struct WarpUsageFetcherTests {
    @Test
    func parses_snapshot_and_aggregates_bonus_credits() throws {
        let json = """
        {
          "data": {
            "user": {
              "__typename": "UserOutput",
              "user": {
                "requestLimitInfo": {
                  "isUnlimited": false,
                  "nextRefreshTime": "2026-02-28T19:16:33.462988Z",
                  "requestLimit": 1500,
                  "requestsUsedSinceLastRefresh": 5
                },
                "bonusGrants": [
                  {
                    "requestCreditsGranted": 20,
                    "requestCreditsRemaining": 10,
                    "expiration": "2026-03-01T10:00:00Z"
                  }
                ],
                "workspaces": [
                  {
                    "bonusGrantsInfo": {
                      "grants": [
                        {
                          "requestCreditsGranted": "15",
                          "requestCreditsRemaining": "5",
                          "expiration": "2026-03-15T10:00:00Z"
                        }
                      ]
                    }
                  }
                ]
              }
            }
          }
        }
        """

        let snapshot = try WarpUsageFetcher._parseResponseForTesting(Data(json.utf8))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expectedRefresh = formatter.date(from: "2026-02-28T19:16:33.462988Z")
        let expectedExpiry = ISO8601DateFormatter().date(from: "2026-03-01T10:00:00Z")

        #expect(snapshot.requestLimit == 1500)
        #expect(snapshot.requestsUsed == 5)
        #expect(snapshot.isUnlimited == false)
        #expect(snapshot.nextRefreshTime != nil)
        #expect(abs((snapshot.nextRefreshTime?.timeIntervalSince1970 ?? 0) -
                (expectedRefresh?.timeIntervalSince1970 ?? 0))
            < 0.5)
        #expect(snapshot.bonusCreditsTotal == 35)
        #expect(snapshot.bonusCreditsRemaining == 15)
        #expect(snapshot.bonusNextExpirationRemaining == 10)
        #expect(abs((snapshot.bonusNextExpiration?.timeIntervalSince1970 ?? 0) -
                (expectedExpiry?.timeIntervalSince1970 ?? 0))
            < 0.5)
    }

    @Test
    func graph_QL_errors_throw_API_error() {
        let json = """
        {
          "errors": [
            { "message": "Unauthorized" }
          ]
        }
        """

        do {
            _ = try WarpUsageFetcher._parseResponseForTesting(Data(json.utf8))
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case let WarpUsageError.apiError(code, message) = error else { return false }
                return code == 200 && message.contains("Unauthorized")
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func null_unlimited_and_string_numerics_parse_safely() throws {
        let json = """
        {
          "data": {
            "user": {
              "__typename": "UserOutput",
              "user": {
                "requestLimitInfo": {
                  "isUnlimited": null,
                  "nextRefreshTime": "2026-02-28T19:16:33Z",
                  "requestLimit": "1500",
                  "requestsUsedSinceLastRefresh": "5"
                }
              }
            }
          }
        }
        """

        let snapshot = try WarpUsageFetcher._parseResponseForTesting(Data(json.utf8))

        #expect(snapshot.isUnlimited == false)
        #expect(snapshot.requestLimit == 1500)
        #expect(snapshot.requestsUsed == 5)
        #expect(snapshot.nextRefreshTime != nil)
    }

    @Test
    func unexpected_typename_returns_parse_error() {
        let json = """
        {
          "data": {
            "user": {
              "__typename": "AuthError"
            }
          }
        }
        """

        do {
            _ = try WarpUsageFetcher._parseResponseForTesting(Data(json.utf8))
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case let WarpUsageError.parseFailed(message) = error else { return false }
                return message.contains("Unexpected user type")
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func missing_request_limit_info_returns_parse_error() {
        let json = """
        {
          "data": {
            "user": {
              "__typename": "UserOutput",
              "user": {}
            }
          }
        }
        """

        do {
            _ = try WarpUsageFetcher._parseResponseForTesting(Data(json.utf8))
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case let WarpUsageError.parseFailed(message) = error else { return false }
                return message.contains("requestLimitInfo")
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func invalid_root_returns_parse_error() {
        let json = """
        [{ "data": {} }]
        """

        do {
            _ = try WarpUsageFetcher._parseResponseForTesting(Data(json.utf8))
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case let WarpUsageError.parseFailed(message) = error else { return false }
                return message == "Root JSON is not an object."
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func to_usage_snapshot_omits_secondary_when_no_bonus_credits() {
        let source = WarpUsageSnapshot(
            requestLimit: 100,
            requestsUsed: 10,
            nextRefreshTime: Date().addingTimeInterval(3600),
            isUnlimited: false,
            updatedAt: Date(),
            bonusCreditsRemaining: 0,
            bonusCreditsTotal: 0,
            bonusNextExpiration: nil,
            bonusNextExpirationRemaining: 0)

        let snapshot = source.toUsageSnapshot()
        #expect(snapshot.secondary == nil)
    }

    @Test
    func to_usage_snapshot_keeps_bonus_window_when_bonus_exists() throws {
        let source = WarpUsageSnapshot(
            requestLimit: 100,
            requestsUsed: 10,
            nextRefreshTime: Date().addingTimeInterval(3600),
            isUnlimited: false,
            updatedAt: Date(),
            bonusCreditsRemaining: 0,
            bonusCreditsTotal: 20,
            bonusNextExpiration: nil,
            bonusNextExpirationRemaining: 0)

        let snapshot = source.toUsageSnapshot()
        let secondary = try #require(snapshot.secondary)
        #expect(secondary.usedPercent == 100)
    }

    @Test
    func to_usage_snapshot_unlimited_primary_does_not_show_reset_date() throws {
        let source = WarpUsageSnapshot(
            requestLimit: 0,
            requestsUsed: 0,
            nextRefreshTime: Date().addingTimeInterval(3600),
            isUnlimited: true,
            updatedAt: Date(),
            bonusCreditsRemaining: 0,
            bonusCreditsTotal: 0,
            bonusNextExpiration: nil,
            bonusNextExpirationRemaining: 0)

        let snapshot = source.toUsageSnapshot()
        let primary = try #require(snapshot.primary)
        #expect(primary.resetsAt == nil)
        #expect(primary.resetDescription == "Unlimited")
    }

    @Test
    func api_error_summary_includes_plain_text_bodies() {
        // Regression: Warp edge returns 429 with a non-JSON body ("Rate exceeded.") when User-Agent is missing/wrong.
        let summary = WarpUsageFetcher._apiErrorSummaryForTesting(
            statusCode: 429,
            data: Data("Rate exceeded.".utf8))
        #expect(summary.contains("Rate exceeded."))
    }
}
