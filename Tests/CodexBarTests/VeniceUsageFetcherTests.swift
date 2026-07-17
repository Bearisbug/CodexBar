import Foundation
import Testing
@testable import CodexBarCore

struct VeniceUsageFetcherTests {
    @Test
    func parses_DIEM_balance_response() throws {
        let json = """
        {
          "canConsume": true,
          "consumptionCurrency": "DIEM",
          "balances": {
            "diem": 90.50,
            "usd": null
          },
          "diemEpochAllocation": 100.0
        }
        """
        let snapshot = try VeniceUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        #expect(snapshot.canConsume == true)
        #expect(snapshot.consumptionCurrency == "DIEM")
        #expect(snapshot.diemBalance == 90.50)
        #expect(snapshot.usdBalance == nil)
        #expect(snapshot.diemEpochAllocation == 100.0)
    }

    @Test
    func parses_USD_balance_response() throws {
        let json = """
        {
          "canConsume": true,
          "consumptionCurrency": "USD",
          "balances": {
            "diem": null,
            "usd": 25.75
          },
          "diemEpochAllocation": null
        }
        """
        let snapshot = try VeniceUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        #expect(snapshot.canConsume == true)
        #expect(snapshot.consumptionCurrency == "USD")
        #expect(snapshot.diemBalance == nil)
        #expect(snapshot.usdBalance == 25.75)
        #expect(snapshot.diemEpochAllocation == nil)
    }

    @Test
    func parses_string_encoded_balances_and_allocation() throws {
        let json = """
        {
          "canConsume": true,
          "consumptionCurrency": "DIEM",
          "balances": {
            "diem": "90.50",
            "usd": "25.75"
          },
          "diemEpochAllocation": "100.0"
        }
        """
        let snapshot = try VeniceUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        #expect(snapshot.diemBalance == 90.50)
        #expect(snapshot.usdBalance == 25.75)
        #expect(snapshot.diemEpochAllocation == 100.0)
    }

    @Test
    func parses_both_DIEM_and_USD_present() throws {
        let json = """
        {
          "canConsume": true,
          "consumptionCurrency": "BUNDLED_CREDITS",
          "balances": {
            "diem": 50.0,
            "usd": 10.0
          },
          "diemEpochAllocation": 100.0
        }
        """
        let snapshot = try VeniceUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        #expect(snapshot.diemBalance == 50.0)
        #expect(snapshot.usdBalance == 10.0)
    }

    @Test
    func uses_DIEM_allocation_progress_for_bundled_credits_currency() throws {
        let json = """
        {
          "canConsume": true,
          "consumptionCurrency": "BUNDLED_CREDITS",
          "balances": {
            "diem": 50.0,
            "usd": 10.0
          },
          "diemEpochAllocation": 100.0
        }
        """
        let snapshot = try VeniceUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.resetDescription?.contains("DIEM 50.00 / 100.00") == true)
        #expect(usage.primary?.usedPercent == 50.0)
    }

    @Test
    func uses_USD_display_when_consumptionCurrency_is_USD_and_both_balances_exist() throws {
        let json = """
        {
          "canConsume": true,
          "consumptionCurrency": "USD",
          "balances": {
            "diem": 50.0,
            "usd": 12.34
          },
          "diemEpochAllocation": 100.0
        }
        """
        let snapshot = try VeniceUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.resetDescription == "$12.34 USD remaining")
        #expect(usage.primary?.usedPercent == 0)
    }

    @Test
    func handles_canConsume_false() throws {
        let json = """
        {
          "canConsume": false,
          "consumptionCurrency": "USD",
          "balances": {
            "diem": null,
            "usd": 100.0
          },
          "diemEpochAllocation": null
        }
        """
        let snapshot = try VeniceUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.usedPercent == 100)
        #expect(usage.primary?.resetDescription == "Balance unavailable for API calls")
    }

    @Test
    func displays_DIEM_with_epoch_allocation() throws {
        let json = """
        {
          "canConsume": true,
          "consumptionCurrency": "DIEM",
          "balances": {
            "diem": 75.0,
            "usd": null
          },
          "diemEpochAllocation": 100.0
        }
        """
        let snapshot = try VeniceUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.resetDescription?.contains("DIEM 75.00 / 100.00") == true)
        #expect(usage.primary?.usedPercent == 25.0)
    }

    @Test
    func displays_DIEM_without_allocation() throws {
        let json = """
        {
          "canConsume": true,
          "consumptionCurrency": "DIEM",
          "balances": {
            "diem": 50.0,
            "usd": null
          },
          "diemEpochAllocation": null
        }
        """
        let snapshot = try VeniceUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.resetDescription?.contains("DIEM 50.00 remaining") == true)
        #expect(usage.primary?.usedPercent == 0)
    }

    @Test
    func displays_USD_balance() throws {
        let json = """
        {
          "canConsume": true,
          "consumptionCurrency": "USD",
          "balances": {
            "diem": null,
            "usd": 15.50
          },
          "diemEpochAllocation": null
        }
        """
        let snapshot = try VeniceUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.resetDescription?.contains("$15.50") == true)
        #expect(usage.primary?.usedPercent == 0)
    }

    @Test
    func handles_zero_balances() throws {
        let json = """
        {
          "canConsume": true,
          "consumptionCurrency": "USD",
          "balances": {
            "diem": 0.0,
            "usd": 0.0
          },
          "diemEpochAllocation": null
        }
        """
        let snapshot = try VeniceUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.resetDescription == "No Venice API balance available")
        #expect(usage.primary?.usedPercent == 100)
    }

    @Test
    func handles_null_balances_with_canConsume_true() throws {
        let json = """
        {
          "canConsume": true,
          "consumptionCurrency": null,
          "balances": {
            "diem": null,
            "usd": null
          },
          "diemEpochAllocation": null
        }
        """
        let snapshot = try VeniceUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.resetDescription == "No Venice API balance available")
        #expect(usage.primary?.usedPercent == 100)
    }

    @Test
    func identity_uses_venice_provider_ID() throws {
        let json = """
        {
          "canConsume": true,
          "consumptionCurrency": "DIEM",
          "balances": {
            "diem": 90.0,
            "usd": null
          },
          "diemEpochAllocation": 100.0
        }
        """
        let snapshot = try VeniceUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.identity?.providerID == .venice)
        #expect(usage.identity?.accountEmail == nil)
        #expect(usage.identity?.accountOrganization == nil)
    }

    @Test
    func throws_on_malformed_JSON() {
        let json = "[{ \"canConsume\": true }]"
        do {
            _ = try VeniceUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case VeniceUsageError.parseFailed = error else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func throws_on_invalid_JSON() {
        let json = "{ invalid json }"
        do {
            _ = try VeniceUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case VeniceUsageError.parseFailed = error else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func clamps_used_percent_to_0_100_range() throws {
        // Negative used percent should be clamped to 0
        let json = """
        {
          "canConsume": true,
          "consumptionCurrency": "DIEM",
          "balances": {
            "diem": 150.0,
            "usd": null
          },
          "diemEpochAllocation": 100.0
        }
        """
        let snapshot = try VeniceUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.usedPercent == 0)
    }
}
