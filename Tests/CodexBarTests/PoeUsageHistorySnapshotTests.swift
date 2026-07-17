import CodexBarCore
import Foundation
import Testing

struct PoeUsageHistorySnapshotTests {
    // MARK: - summary(days:)

    @Test
    func summary_over_empty_daily_returns_zeroed_summary_with_nil_cost() {
        let snapshot = PoeUsageHistorySnapshot(
            entries: [],
            daily: [],
            updatedAt: Date())

        let summary = snapshot.summary(days: 7)

        #expect(summary.points == 0)
        #expect(summary.requests == 0)
        #expect(summary.costUSD == nil)
    }

    @Test
    func summary_over_single_day_reports_that_day_s_points_and_requests() {
        let snapshot = PoeUsageHistorySnapshot(
            entries: [],
            daily: [PoeUsageHistorySnapshot.DailyBucket(
                day: "2026-05-31",
                points: 250,
                requests: 3,
                costUSD: 0.05)],
            updatedAt: Date())

        let summary = snapshot.summary(days: 1)

        #expect(summary.points == 250)
        #expect(summary.requests == 3)
        #expect(summary.costUSD == 0.05)
    }

    @Test
    func summary_over_seven_days_uses_the_last_seven_daily_buckets() {
        let daily: [PoeUsageHistorySnapshot.DailyBucket] = (1...10).map { offset in
            PoeUsageHistorySnapshot.DailyBucket(
                day: String(format: "2026-05-%02d", offset),
                points: Double(offset * 10),
                requests: offset,
                costUSD: nil)
        }
        let snapshot = PoeUsageHistorySnapshot(
            entries: [],
            daily: daily,
            updatedAt: Date())

        // Last 7 buckets: offsets 4..10 → 40+50+60+70+80+90+100 = 490
        let summary = snapshot.summary(days: 7)

        #expect(summary.points == 490)
        #expect(summary.requests == 4 + 5 + 6 + 7 + 8 + 9 + 10)
        #expect(summary.costUSD == nil)
    }

    @Test
    func summary_clamps_zero_and_negative_day_counts_up_to_one() {
        let snapshot = PoeUsageHistorySnapshot(
            entries: [],
            daily: [
                PoeUsageHistorySnapshot.DailyBucket(day: "2026-05-29", points: 100, requests: 1, costUSD: nil),
                PoeUsageHistorySnapshot.DailyBucket(day: "2026-05-30", points: 200, requests: 2, costUSD: nil),
                PoeUsageHistorySnapshot.DailyBucket(day: "2026-05-31", points: 300, requests: 3, costUSD: nil),
            ],
            updatedAt: Date())

        #expect(snapshot.summary(days: 0).points == 300) // last bucket only
        #expect(snapshot.summary(days: 0).requests == 3)
        #expect(snapshot.summary(days: -5).points == 300) // clamped up to 1
    }

    @Test
    func summary_ignores_daily_buckets_beyond_the_requested_window() {
        let snapshot = PoeUsageHistorySnapshot(
            entries: [],
            daily: (1...30).map { offset in
                PoeUsageHistorySnapshot.DailyBucket(
                    day: String(format: "2026-04-%02d", offset),
                    points: 1,
                    requests: 1,
                    costUSD: nil)
            },
            updatedAt: Date())

        let last30 = snapshot.summary(days: 30)
        let last7 = snapshot.summary(days: 7)

        #expect(last30.points == 30)
        #expect(last7.points == 7)
    }

    @Test
    func summary_reports_nil_cost_when_every_daily_bucket_has_nil_cost() {
        let snapshot = PoeUsageHistorySnapshot(
            entries: [],
            daily: (1...3).map { offset in
                PoeUsageHistorySnapshot.DailyBucket(
                    day: "2026-05-\(28 + offset)",
                    points: 50,
                    requests: 1,
                    costUSD: nil)
            },
            updatedAt: Date())

        #expect(snapshot.summary(days: 7).costUSD == nil)
    }

    @Test
    func summary_sums_only_the_non_nil_cost_buckets_and_keeps_the_rest_invisible() throws {
        let snapshot = PoeUsageHistorySnapshot(
            entries: [],
            daily: [
                PoeUsageHistorySnapshot.DailyBucket(day: "2026-05-29", points: 100, requests: 1, costUSD: nil),
                PoeUsageHistorySnapshot.DailyBucket(day: "2026-05-30", points: 200, requests: 1, costUSD: 0.10),
                PoeUsageHistorySnapshot.DailyBucket(day: "2026-05-31", points: 300, requests: 1, costUSD: 0.20),
            ],
            updatedAt: Date())

        // Skips the nil bucket, sums 0.10 + 0.20 (allow IEEE-754 round-trip)
        let cost = try #require(snapshot.summary(days: 7).costUSD)
        #expect(abs(cost - 0.30) < 1e-9)
    }

    // MARK: - latestDay / last7Days / last30Days shortcuts

    @Test
    func latest_day_last_7_and_last_30_days_agree_with_summary_by_day_count() {
        let daily: [PoeUsageHistorySnapshot.DailyBucket] = (1...40).map { offset in
            PoeUsageHistorySnapshot.DailyBucket(
                day: String(format: "2026-04-%02d", offset),
                points: Double(offset),
                requests: 1,
                costUSD: nil)
        }
        let snapshot = PoeUsageHistorySnapshot(
            entries: [],
            daily: daily,
            updatedAt: Date())

        #expect(snapshot.latestDay == snapshot.summary(days: 1))
        #expect(snapshot.last7Days == snapshot.summary(days: 7))
        #expect(snapshot.last30Days == snapshot.summary(days: 30))
    }

    @Test
    func current_day_does_not_reuse_a_stale_latest_bucket() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/London"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-23T12:00:00Z"))
        let yesterday = try #require(ISO8601DateFormatter().date(from: "2026-06-22T12:00:00Z"))
        let snapshot = PoeUsageHistorySnapshot(
            entries: [
                self.makeEntry(
                    id: "stale",
                    createdAt: yesterday,
                    model: "GPT-4o",
                    usageType: "chat",
                    points: 100,
                    costUSD: 0.10),
            ],
            daily: [
                PoeUsageHistorySnapshot.DailyBucket(
                    day: "2026-06-22",
                    points: 100,
                    requests: 1,
                    costUSD: 0.10),
            ],
            updatedAt: now)

        #expect(snapshot.latestDay.points == 100)
        #expect(snapshot.currentDay(now: now, calendar: calendar).points == 0)
        #expect(snapshot.currentDay(now: now, calendar: calendar).requests == 0)
        #expect(snapshot.currentDay(now: now, calendar: calendar).costUSD == nil)
    }

    @Test
    func current_day_filters_raw_entries_across_a_UTC_bucket_boundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-23T01:00:00Z"))
        let localToday = try #require(ISO8601DateFormatter().date(from: "2026-06-22T20:00:00Z"))
        let localYesterday = try #require(ISO8601DateFormatter().date(from: "2026-06-22T06:00:00Z"))
        let snapshot = PoeUsageHistorySnapshot(
            entries: [
                self.makeEntry(
                    id: "today",
                    createdAt: localToday,
                    model: "GPT-4o",
                    usageType: "chat",
                    points: 80,
                    costUSD: 0.08),
                self.makeEntry(
                    id: "yesterday",
                    createdAt: localYesterday,
                    model: "Claude",
                    usageType: "chat",
                    points: 20,
                    costUSD: 0.02),
            ],
            daily: [
                PoeUsageHistorySnapshot.DailyBucket(
                    day: "2026-06-22",
                    points: 100,
                    requests: 2,
                    costUSD: 0.10),
            ],
            updatedAt: now)

        let current = snapshot.currentDay(now: now, calendar: calendar)
        #expect(current.points == 80)
        #expect(current.requests == 1)
        #expect(current.costUSD == 0.08)
    }

    // MARK: - topModels / topModel

    @Test
    func top_models_is_empty_when_entries_is_empty() {
        let snapshot = PoeUsageHistorySnapshot(
            entries: [],
            daily: [],
            updatedAt: Date())

        #expect(snapshot.topModels.isEmpty)
        #expect(snapshot.topModel == nil)
    }

    @Test
    func top_models_groups_by_model_and_sums_points_and_requests() {
        let entries = [
            self.makeEntry(id: "1", model: "GPT-4o", usageType: "chat", points: 10, costUSD: 0.01),
            self.makeEntry(id: "2", model: "GPT-4o", usageType: "chat", points: 5, costUSD: 0.01),
            self.makeEntry(id: "3", model: "Claude-3.7", usageType: "chat", points: 20, costUSD: 0.02),
        ]
        let snapshot = PoeUsageHistorySnapshot(
            entries: entries,
            daily: [],
            updatedAt: Date())

        let top = snapshot.topModels

        #expect(top.count == 2)
        #expect(top[0].name == "Claude-3.7")
        #expect(top[0].points == 20)
        #expect(top[0].requests == 1)
        #expect(top[1].name == "GPT-4o")
        #expect(top[1].points == 15)
        #expect(top[1].requests == 2)
    }

    @Test
    func top_models_breaks_ties_by_name_ascending() {
        let entries = [
            self.makeEntry(id: "1", model: "Z-Model", usageType: "chat", points: 10, costUSD: nil),
            self.makeEntry(id: "2", model: "A-Model", usageType: "chat", points: 10, costUSD: nil),
            self.makeEntry(id: "3", model: "M-Model", usageType: "chat", points: 10, costUSD: nil),
        ]
        let snapshot = PoeUsageHistorySnapshot(
            entries: entries,
            daily: [],
            updatedAt: Date())

        let top = snapshot.topModels
        #expect(top.map(\.name) == ["A-Model", "M-Model", "Z-Model"])
    }

    @Test
    func top_models_falls_back_to_unknown_for_empty_or_whitespace_model_strings() {
        let entries = [
            self.makeEntry(id: "1", model: "GPT-4o", usageType: "chat", points: 5, costUSD: nil),
            self.makeEntry(id: "2", model: "", usageType: "chat", points: 5, costUSD: nil),
            self.makeEntry(id: "3", model: "   ", usageType: "chat", points: 5, costUSD: nil),
        ]
        let snapshot = PoeUsageHistorySnapshot(
            entries: entries,
            daily: [],
            updatedAt: Date())

        let top = snapshot.topModels
        let names = top.map(\.name)
        #expect(names.contains("unknown"))
        #expect(names.contains("GPT-4o"))
    }

    @Test
    func top_models_omits_cost_when_no_entry_reported_cost() {
        let entries = [
            self.makeEntry(id: "1", model: "GPT-4o", usageType: "chat", points: 5, costUSD: nil),
        ]
        let snapshot = PoeUsageHistorySnapshot(
            entries: entries,
            daily: [],
            updatedAt: Date())

        #expect(snapshot.topModels.first?.costUSD == nil)
    }

    @Test
    func top_models_sums_cost_across_entries_for_the_same_model() {
        let entries = [
            self.makeEntry(id: "1", model: "GPT-4o", usageType: "chat", points: 5, costUSD: 0.01),
            self.makeEntry(id: "2", model: "GPT-4o", usageType: "chat", points: 5, costUSD: 0.02),
        ]
        let snapshot = PoeUsageHistorySnapshot(
            entries: entries,
            daily: [],
            updatedAt: Date())

        #expect(snapshot.topModels.first?.costUSD == 0.03)
    }

    // MARK: - topUsageTypes / topUsageType

    @Test
    func top_usage_types_groups_by_usage_type_independent_of_model() {
        let entries = [
            self.makeEntry(id: "1", model: "GPT-4o", usageType: "chat", points: 5, costUSD: nil),
            self.makeEntry(id: "2", model: "Claude", usageType: "chat", points: 10, costUSD: nil),
            self.makeEntry(id: "3", model: "GPT-4o", usageType: "api", points: 8, costUSD: nil),
        ]
        let snapshot = PoeUsageHistorySnapshot(
            entries: entries,
            daily: [],
            updatedAt: Date())

        let top = snapshot.topUsageTypes
        #expect(top.map(\.name) == ["chat", "api"])
        #expect(top[0].points == 15)
        #expect(top[0].requests == 2)
    }

    @Test
    func top_usage_type_is_the_first_entry_in_top_usage_types() {
        let entries = [
            self.makeEntry(id: "1", model: "GPT-4o", usageType: "chat", points: 5, costUSD: nil),
            self.makeEntry(id: "2", model: "GPT-4o", usageType: "api", points: 10, costUSD: nil),
        ]
        let snapshot = PoeUsageHistorySnapshot(
            entries: entries,
            daily: [],
            updatedAt: Date())

        #expect(snapshot.topUsageType == "api")
        #expect(snapshot.topUsageType == snapshot.topUsageTypes.first?.name)
    }

    @Test
    func top_usage_type_is_nil_for_empty_entries() {
        let snapshot = PoeUsageHistorySnapshot(
            entries: [],
            daily: [],
            updatedAt: Date())

        #expect(snapshot.topUsageType == nil)
    }

    // MARK: - recentEntries(limit:)

    @Test
    func recent_entries_returns_up_to_the_requested_limit_newest_first() {
        let now = Date(timeIntervalSince1970: 1_717_000_000)
        let entries = (0..<5).map { offset in
            self.makeEntry(
                id: "\(offset)",
                createdAt: now.addingTimeInterval(TimeInterval(offset * 60)),
                model: "GPT-4o",
                usageType: "chat",
                points: 1,
                costUSD: nil)
        }
        // entries are passed in order they came back; init should sort
        let snapshot = PoeUsageHistorySnapshot(
            entries: entries,
            daily: [],
            updatedAt: now)

        let recent = snapshot.recentEntries(limit: 3)

        #expect(recent.count == 3)
        // Newest three (offsets 4, 3, 2) should be first
        #expect(recent[0].id == "4")
        #expect(recent[1].id == "3")
        #expect(recent[2].id == "2")
    }

    @Test
    func recent_entries_clamps_non_positive_limit_up_to_one() {
        let now = Date(timeIntervalSince1970: 1_717_000_000)
        let entries = (0..<3).map { offset in
            self.makeEntry(
                id: "\(offset)",
                createdAt: now.addingTimeInterval(TimeInterval(offset * 60)),
                model: "GPT-4o",
                usageType: "chat",
                points: 1,
                costUSD: nil)
        }
        let snapshot = PoeUsageHistorySnapshot(
            entries: entries,
            daily: [],
            updatedAt: now)

        #expect(snapshot.recentEntries(limit: 0).count == 1)
        #expect(snapshot.recentEntries(limit: -3).count == 1)
        #expect(snapshot.recentEntries(limit: 0).first?.id == "2")
    }

    @Test
    func recent_entries_returns_everything_when_limit_exceeds_entries_count() {
        let now = Date(timeIntervalSince1970: 1_717_000_000)
        let entries = [
            self.makeEntry(id: "1", createdAt: now, model: "A", usageType: "t", points: 1, costUSD: nil),
            self.makeEntry(
                id: "2",
                createdAt: now.addingTimeInterval(60),
                model: "A",
                usageType: "t",
                points: 1,
                costUSD: nil),
        ]
        let snapshot = PoeUsageHistorySnapshot(
            entries: entries,
            daily: [],
            updatedAt: now)

        let recent = snapshot.recentEntries(limit: 10)
        #expect(recent.count == 2)
    }

    // MARK: - Init sorting invariants

    @Test
    func init_sorts_entries_ascending_by_created_at_and_daily_ascending_by_day_string() {
        let now = Date(timeIntervalSince1970: 1_717_000_000)
        let entries = [
            self.makeEntry(
                id: "newer",
                createdAt: now.addingTimeInterval(120),
                model: "A",
                usageType: "t",
                points: 1,
                costUSD: nil),
            self.makeEntry(id: "older", createdAt: now, model: "A", usageType: "t", points: 1, costUSD: nil),
        ]
        let daily = [
            PoeUsageHistorySnapshot.DailyBucket(day: "2026-05-31", points: 1, requests: 1, costUSD: nil),
            PoeUsageHistorySnapshot.DailyBucket(day: "2026-05-30", points: 1, requests: 1, costUSD: nil),
        ]
        let snapshot = PoeUsageHistorySnapshot(
            entries: entries,
            daily: daily,
            updatedAt: now)

        // Public init sorts entries ASC by createdAt, daily ASC by day
        // (consumers wanting newest-first should use recentEntries(limit:))
        #expect(snapshot.entries.first?.id == "older")
        #expect(snapshot.entries.last?.id == "newer")
        #expect(snapshot.daily.first?.day == "2026-05-30")
        #expect(snapshot.daily.last?.day == "2026-05-31")
    }

    // MARK: - Helpers

    private func makeEntry(
        id: String,
        createdAt: Date = Date(timeIntervalSince1970: 1_717_000_000),
        model: String,
        usageType: String,
        points: Double,
        costUSD: Double?) -> PoeUsageHistorySnapshot.Entry
    {
        PoeUsageHistorySnapshot.Entry(
            id: id,
            createdAt: createdAt,
            model: model,
            usageType: usageType,
            points: points,
            costUSD: costUSD)
    }
}
