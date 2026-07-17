import Foundation
import Testing
@testable import CodexBarCore

struct OllamaUsageParserTests {
    @Test
    func parses_cloud_usage_from_settings_HTML() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let html = """
        <div>
          <h2 class=\"text-xl\">
            <span>Cloud Usage</span>
            <span class=\"text-xs\">free</span>
          </h2>
          <h2 id=\"header-email\">user@example.com</h2>
          <div>
            <span>Session usage</span>
            <span>0.1% used</span>
            <div class=\"local-time\" data-time=\"2026-01-30T18:00:00Z\">Resets in 3 hours</div>
          </div>
          <div>
            <span>Weekly usage</span>
            <span>0.7% used</span>
            <div class=\"local-time\" data-time=\"2026-02-02T00:00:00Z\">Resets in 2 days</div>
          </div>
        </div>
        """

        let snapshot = try OllamaUsageParser.parse(html: html, now: now)

        #expect(snapshot.planName == "free")
        #expect(snapshot.accountEmail == "user@example.com")
        #expect(snapshot.sessionUsedPercent == 0.1)
        #expect(snapshot.weeklyUsedPercent == 0.7)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let expectedSession = formatter.date(from: "2026-01-30T18:00:00Z")
        let expectedWeekly = formatter.date(from: "2026-02-02T00:00:00Z")
        #expect(snapshot.sessionResetsAt == expectedSession)
        #expect(snapshot.weeklyResetsAt == expectedWeekly)

        let usage = snapshot.toUsageSnapshot()
        #expect(usage.identity?.loginMethod == "free")
        #expect(usage.identity?.accountEmail == "user@example.com")
        #expect(usage.primary?.windowMinutes == 5 * 60)
        #expect(usage.secondary?.windowMinutes == 7 * 24 * 60)
    }

    @Test
    func missing_usage_throws_parse_failed() {
        let html = "<html><body>No usage here. login status unknown.</body></html>"

        do {
            try OllamaUsageParser.parse(html: html)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case let OllamaUsageError.parseFailed(message) = error else { return false }
                return message.contains("Missing Ollama usage data")
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func classified_parse_missing_usage_returns_typed_failure() {
        let html = "<html><body>No usage here. login status unknown.</body></html>"
        let result = OllamaUsageParser.parseClassified(html: html)

        switch result {
        case .success:
            Issue.record("Expected classified parse failure for missing usage data")
        case let .failure(failure):
            #expect(failure == .missingUsageData)
        }
    }

    @Test
    func signed_out_throws_not_logged_in() {
        let html = """
        <html>
          <body>
            <h1>Sign in to Ollama</h1>
            <form action="/auth/signin" method="post">
              <input type="email" name="email" />
              <input type="password" name="password" />
            </form>
          </body>
        </html>
        """

        do {
            try OllamaUsageParser.parse(html: html)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case OllamaUsageError.notLoggedIn = error else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func classified_parse_signed_out_returns_typed_failure() {
        let html = """
        <html>
          <body>
            <h1>Sign in to Ollama</h1>
            <form action="/auth/signin" method="post">
              <input type="email" name="email" />
              <input type="password" name="password" />
            </form>
          </body>
        </html>
        """

        let result = OllamaUsageParser.parseClassified(html: html)
        switch result {
        case .success:
            Issue.record("Expected classified parse failure for signed-out HTML")
        case let .failure(failure):
            #expect(failure == .notLoggedIn)
        }
    }

    @Test
    func generic_sign_in_text_without_auth_markers_throws_parse_failed() {
        let html = """
        <html>
          <body>
            <h2>Usage Dashboard</h2>
            <p>If you have an account, you can sign in from the homepage.</p>
            <div>No usage rows rendered.</div>
          </body>
        </html>
        """

        do {
            try OllamaUsageParser.parse(html: html)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case let OllamaUsageError.parseFailed(message) = error else { return false }
                return message.contains("Missing Ollama usage data")
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func parses_hourly_usage_as_primary_window() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let html = """
        <div>
          <span>Hourly usage</span>
          <span>2.5% used</span>
          <div class=\"local-time\" data-time=\"2026-01-30T18:00:00Z\">Resets in 3 hours</div>
          <span>Weekly usage</span>
          <span>4.2% used</span>
          <div class=\"local-time\" data-time=\"2026-02-02T00:00:00Z\">Resets in 2 days</div>
        </div>
        """

        let snapshot = try OllamaUsageParser.parse(html: html, now: now)

        #expect(snapshot.sessionUsedPercent == 2.5)
        #expect(snapshot.weeklyUsedPercent == 4.2)

        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.windowMinutes == nil)
        #expect(usage.secondary?.windowMinutes == 7 * 24 * 60)
    }

    @Test
    func weekly_usage_parser_finds_reset_timestamp_in_long_usage_block() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let filler = String(repeating: "<span class=\"grid-cell\"></span>", count: 40)
        let html = """
        <div>
          <span>Session usage</span>
          <span>0.1% used</span>
          <span>Weekly usage</span>
          <span>0.7% used</span>
          \(filler)
          <div class=\"local-time\" data-time=\"2026-02-02T00:00:00Z\">Resets in 2 days</div>
        </div>
        """

        let snapshot = try OllamaUsageParser.parse(html: html, now: now)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let expectedWeekly = formatter.date(from: "2026-02-02T00:00:00Z")
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.resetsAt == nil)
        #expect(usage.secondary?.resetsAt == expectedWeekly)
    }

    @Test
    func parses_usage_when_used_is_capitalized() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let html = """
        <div>
          <span>Session usage</span>
          <span>1.2% Used</span>
          <div class=\"local-time\" data-time=\"2026-01-30T18:00:00Z\">Resets in 3 hours</div>
          <span>Weekly usage</span>
          <span>3.4% USED</span>
          <div class=\"local-time\" data-time=\"2026-02-02T00:00:00Z\">Resets in 2 days</div>
        </div>
        """

        let snapshot = try OllamaUsageParser.parse(html: html, now: now)

        #expect(snapshot.sessionUsedPercent == 1.2)
        #expect(snapshot.weeklyUsedPercent == 3.4)
    }
}
