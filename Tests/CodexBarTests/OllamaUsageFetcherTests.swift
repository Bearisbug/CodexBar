import Foundation
import Testing
@testable import CodexBarCore
#if os(macOS)
import SweetCookieKit
#endif

struct OllamaUsageFetcherTests {
    @Test
    func session_authentication_errors_point_to_current_recovery_page() {
        #expect(OllamaUsageError.notLoggedIn.errorDescription?.contains("https://ollama.com/signin") == true)
        #expect(OllamaUsageError.invalidCredentials.errorDescription?.contains("https://ollama.com/signin") == true)
        #expect(OllamaUsageError.noSessionCookie.errorDescription?.contains("https://ollama.com/signin") == true)
    }

    @Test
    func attaches_cookie_for_ollama_hosts() {
        #expect(OllamaUsageFetcher.shouldAttachCookie(to: URL(string: "https://ollama.com/settings")))
        #expect(OllamaUsageFetcher.shouldAttachCookie(to: URL(string: "https://www.ollama.com")))
        #expect(OllamaUsageFetcher.shouldAttachCookie(to: URL(string: "https://app.ollama.com/path")))
    }

    @Test
    func rejects_non_ollama_hosts() {
        #expect(!OllamaUsageFetcher.shouldAttachCookie(to: URL(string: "https://example.com")))
        #expect(!OllamaUsageFetcher.shouldAttachCookie(to: URL(string: "https://ollama.com.evil.com")))
        #expect(!OllamaUsageFetcher.shouldAttachCookie(to: nil))
    }

    @Test
    func rejects_non_https_ollama_urls() {
        #expect(!OllamaUsageFetcher.shouldAttachCookie(to: URL(string: "http://ollama.com/settings")))
        #expect(!OllamaUsageFetcher.shouldAttachCookie(to: URL(string: "http://www.ollama.com")))
        #expect(!OllamaUsageFetcher.shouldAttachCookie(to: URL(string: "http://app.ollama.com/path")))
    }

    @Test
    func recognizes_current_ollama_sign_in_redirects() {
        #expect(OllamaUsageFetcher.isSignInRedirect(URL(string: "https://ollama.com/signin")))
        #expect(OllamaUsageFetcher.isSignInRedirect(URL(
            string: "https://api.workos.com/user_management/authorize?client_id=test")))
        #expect(OllamaUsageFetcher.isSignInRedirect(URL(
            string: "https://auth.workos.com/user_management/authorize?client_id=test")))
        // The real unauthenticated chain lands on the WorkOS-hosted Ollama sign-in
        // page on the `signin.ollama.com` subdomain (verified live); that terminal
        // landing must also classify as a sign-in redirect.
        #expect(OllamaUsageFetcher.isSignInRedirect(URL(
            string: "https://signin.ollama.com/?client_id=test&authorization_session_id=x")))
        #expect(!OllamaUsageFetcher.isSignInRedirect(URL(string: "https://ollama.com/settings")))
        #expect(!OllamaUsageFetcher.isSignInRedirect(URL(string: "https://api.workos.com/other")))
        #expect(!OllamaUsageFetcher.isSignInRedirect(URL(string: "http://ollama.com/signin")))
        #expect(!OllamaUsageFetcher.isSignInRedirect(URL(
            string: "http://auth.workos.com/user_management/authorize?client_id=test")))
        #expect(!OllamaUsageFetcher.isSignInRedirect(URL(
            string: "https://example.com/user_management/authorize?client_id=test")))
    }

    @Test
    func manual_mode_without_valid_header_throws_no_session_cookie() {
        do {
            _ = try OllamaUsageFetcher.resolveManualCookieHeader(
                override: nil,
                manualCookieMode: true)
            Issue.record("Expected OllamaUsageError.noSessionCookie")
        } catch OllamaUsageError.noSessionCookie {
            // expected
        } catch {
            Issue.record("Expected OllamaUsageError.noSessionCookie, got \(error)")
        }
    }

    @Test
    func auto_mode_without_header_does_not_force_manual_error() throws {
        let resolved = try OllamaUsageFetcher.resolveManualCookieHeader(
            override: nil,
            manualCookieMode: false)
        #expect(resolved == nil)
    }

    @Test
    func manual_mode_without_recognized_session_cookie_throws_no_session_cookie() {
        do {
            _ = try OllamaUsageFetcher.resolveManualCookieHeader(
                override: "analytics_session_id=noise; theme=dark",
                manualCookieMode: true)
            Issue.record("Expected OllamaUsageError.noSessionCookie")
        } catch OllamaUsageError.noSessionCookie {
            // expected
        } catch {
            Issue.record("Expected OllamaUsageError.noSessionCookie, got \(error)")
        }
    }

    @Test
    func manual_mode_with_recognized_session_cookie_accepts_header() throws {
        let resolved = try OllamaUsageFetcher.resolveManualCookieHeader(
            override: "next-auth.session-token.0=abc; theme=dark",
            manualCookieMode: true)
        #expect(resolved?.contains("next-auth.session-token.0=abc") == true)
    }

    @Test
    func manual_mode_accepts_secure_session_cookie_header() throws {
        let resolved = try OllamaUsageFetcher.resolveManualCookieHeader(
            override: "__Secure-session=abc; theme=dark",
            manualCookieMode: true)
        #expect(resolved?.contains("__Secure-session=abc") == true)
    }

    @Test
    func manual_mode_accepts_workos_session_cookie_header() throws {
        let resolved = try OllamaUsageFetcher.resolveManualCookieHeader(
            override: "wos-session=abc; theme=dark",
            manualCookieMode: true)
        #expect(resolved?.contains("wos-session=abc") == true)
    }

    @Test
    func retry_policy_retries_only_for_auth_errors() {
        #expect(OllamaUsageFetcher.shouldRetryWithNextCookieCandidate(after: OllamaUsageError.invalidCredentials))
        #expect(OllamaUsageFetcher.shouldRetryWithNextCookieCandidate(after: OllamaUsageError.notLoggedIn))
        #expect(OllamaUsageFetcher.shouldRetryWithNextCookieCandidate(
            after: OllamaUsageFetcher.RetryableParseFailure.missingUsageData))
        #expect(!OllamaUsageFetcher.shouldRetryWithNextCookieCandidate(
            after: OllamaUsageError.parseFailed("Missing Ollama usage data.")))
        #expect(!OllamaUsageFetcher.shouldRetryWithNextCookieCandidate(
            after: OllamaUsageError.parseFailed("Unexpected parser mismatch.")))
        #expect(!OllamaUsageFetcher.shouldRetryWithNextCookieCandidate(after: OllamaUsageError.networkError("timeout")))
    }

    #if os(macOS)
    @Test
    func cookie_importer_defaults_to_chrome_first() {
        #expect(OllamaCookieImporter.defaultPreferredBrowsers == [.chrome])
        #expect(OllamaCookieImporter.defaultAllowFallbackBrowsers)
    }

    @Test
    func cookie_access_errors_map_only_unambiguous_recovery_paths() {
        let safari = OllamaCookieImporter.accessError(from: BrowserCookieError.accessDenied(
            browser: .safari,
            details: "Enable Full Disk Access."))
        guard case .safariCookieAccessDenied = safari else {
            Issue.record("Expected Safari Full Disk Access error")
            return
        }

        let brave = OllamaCookieImporter.accessError(from: BrowserCookieError.accessDenied(
            browser: .brave,
            details: "macOS Keychain denied access."))
        guard case let .browserCookieDecryptionDenied(browserName) = brave else {
            Issue.record("Expected Brave Keychain denial")
            return
        }
        #expect(browserName == "Brave")

        let ambiguous = OllamaCookieImporter.accessError(from: BrowserCookieError.loadFailed(
            browser: .brave,
            details: "SQLite failed"))
        #expect(ambiguous == nil)
    }

    @Test
    func cookie_cooldown_maps_only_the_browser_that_was_denied() {
        BrowserCookieAccessGate.resetForTesting()
        defer { BrowserCookieAccessGate.resetForTesting() }
        let now = Date(timeIntervalSince1970: 1000)

        KeychainAccessGate.withTaskOverrideForTesting(false) {
            BrowserCookieAccessGate.recordDenied(for: .brave, now: now)

            let brave = OllamaCookieImporter.suppressedAccessError(
                for: .brave,
                now: now.addingTimeInterval(1))
            guard case let .browserCookieDecryptionDenied(browserName) = brave else {
                Issue.record("Expected stored Brave Keychain denial")
                return
            }
            #expect(browserName == "Brave")
            #expect(OllamaCookieImporter.suppressedAccessError(
                for: .chrome,
                now: now.addingTimeInterval(1)) == nil)
        }
    }

    @Test
    func disabled_Keychain_access_maps_to_browser_recovery_hint() {
        KeychainAccessGate.withTaskOverrideForTesting(true) {
            let error = OllamaCookieImporter.suppressedAccessError(for: .brave)
            guard case let .browserCookieDecryptionDisabled(browserName) = error else {
                Issue.record("Expected disabled Brave Keychain error")
                return
            }
            #expect(browserName == "Brave")
        }
    }

    @Test
    func manual_refresh_bypasses_browser_denial_cooldown() async {
        await BrowserCookieAccessGate.withDeniedBrowsersForTesting([.brave]) {
            KeychainAccessGate.withTaskOverrideForTesting(false) {
                BrowserCookieAccessGate.withExplicitRetry {
                    ProviderInteractionContext.$current.withValue(.userInitiated) {
                        var accessError: OllamaUsageError?
                        let shouldAttempt = OllamaCookieImporter.shouldAttemptCookieSource(
                            .brave,
                            accessError: &accessError)
                        #expect(shouldAttempt)
                        #expect(accessError == nil)
                    }
                }
            }
        }
    }

    @Test
    func cookie_selector_skips_session_like_noise_and_finds_recognized_cookie() throws {
        let first = OllamaCookieImporter.SessionInfo(
            cookies: [Self.makeCookie(name: "analytics_session_id", value: "noise")],
            sourceLabel: "Profile A")
        let second = OllamaCookieImporter.SessionInfo(
            cookies: [Self.makeCookie(name: "__Secure-next-auth.session-token", value: "auth")],
            sourceLabel: "Profile B")

        let selected = try OllamaCookieImporter.selectSessionInfo(from: [first, second])
        #expect(selected.sourceLabel == "Profile B")
    }

    @Test
    func cookie_selector_throws_when_no_recognized_session_cookie_exists() {
        let candidates = [
            OllamaCookieImporter.SessionInfo(
                cookies: [Self.makeCookie(name: "analytics_session_id", value: "noise")],
                sourceLabel: "Profile A"),
            OllamaCookieImporter.SessionInfo(
                cookies: [Self.makeCookie(name: "tracking_session", value: "noise")],
                sourceLabel: "Profile B"),
        ]

        do {
            _ = try OllamaCookieImporter.selectSessionInfo(from: candidates)
            Issue.record("Expected OllamaUsageError.noSessionCookie")
        } catch OllamaUsageError.noSessionCookie {
            // expected
        } catch {
            Issue.record("Expected OllamaUsageError.noSessionCookie, got \(error)")
        }
    }

    @Test
    func cookie_selector_accepts_chunked_next_auth_session_token_cookie() throws {
        let candidate = OllamaCookieImporter.SessionInfo(
            cookies: [Self.makeCookie(name: "next-auth.session-token.0", value: "chunk0")],
            sourceLabel: "Profile C")

        let selected = try OllamaCookieImporter.selectSessionInfo(from: [candidate])
        #expect(selected.sourceLabel == "Profile C")
    }

    @Test
    func cookie_selector_accepts_secure_session_cookie() throws {
        let candidate = OllamaCookieImporter.SessionInfo(
            cookies: [Self.makeCookie(name: "__Secure-session", value: "auth")],
            sourceLabel: "Profile D")

        let selected = try OllamaCookieImporter.selectSessionInfo(from: [candidate])
        #expect(selected.sourceLabel == "Profile D")
    }

    @Test
    func cookie_selector_accepts_workos_session_cookie() throws {
        let candidate = OllamaCookieImporter.SessionInfo(
            cookies: [Self.makeCookie(name: "wos-session", value: "auth")],
            sourceLabel: "WorkOS Profile")

        let selected = try OllamaCookieImporter.selectSessionInfo(from: [candidate])
        #expect(selected.sourceLabel == "WorkOS Profile")
    }

    @Test
    func cookie_selector_keeps_recognized_candidates_in_order() throws {
        let first = OllamaCookieImporter.SessionInfo(
            cookies: [Self.makeCookie(name: "session", value: "stale")],
            sourceLabel: "Chrome Profile A")
        let second = OllamaCookieImporter.SessionInfo(
            cookies: [Self.makeCookie(name: "next-auth.session-token.0", value: "valid")],
            sourceLabel: "Chrome Profile B")
        let noise = OllamaCookieImporter.SessionInfo(
            cookies: [Self.makeCookie(name: "analytics_session_id", value: "noise")],
            sourceLabel: "Chrome Profile C")

        let selected = try OllamaCookieImporter.selectSessionInfos(from: [first, noise, second])
        #expect(selected.map(\.sourceLabel) == ["Chrome Profile A", "Chrome Profile B"])
    }

    @Test
    func cookie_selector_does_not_fallback_when_fallback_disabled() {
        let preferred = [
            OllamaCookieImporter.SessionInfo(
                cookies: [Self.makeCookie(name: "analytics_session_id", value: "noise")],
                sourceLabel: "Chrome Profile"),
        ]
        let fallback = [
            OllamaCookieImporter.SessionInfo(
                cookies: [Self.makeCookie(name: "next-auth.session-token.0", value: "chunk0")],
                sourceLabel: "Safari Profile"),
        ]

        do {
            _ = try OllamaCookieImporter.selectSessionInfoWithFallback(
                preferredCandidates: preferred,
                allowFallbackBrowsers: false,
                loadFallbackCandidates: { fallback })
            Issue.record("Expected OllamaUsageError.noSessionCookie")
        } catch OllamaUsageError.noSessionCookie {
            // expected
        } catch {
            Issue.record("Expected OllamaUsageError.noSessionCookie, got \(error)")
        }
    }

    @Test
    func cookie_selector_falls_back_to_non_chrome_candidate_when_fallback_enabled() throws {
        let preferred = [
            OllamaCookieImporter.SessionInfo(
                cookies: [Self.makeCookie(name: "analytics_session_id", value: "noise")],
                sourceLabel: "Chrome Profile"),
        ]
        let fallback = [
            OllamaCookieImporter.SessionInfo(
                cookies: [Self.makeCookie(name: "next-auth.session-token.0", value: "chunk0")],
                sourceLabel: "Safari Profile"),
        ]

        let selected = try OllamaCookieImporter.selectSessionInfoWithFallback(
            preferredCandidates: preferred,
            allowFallbackBrowsers: true,
            loadFallbackCandidates: { fallback })
        #expect(selected.sourceLabel == "Safari Profile")
    }

    @Test
    func cookie_selector_can_fall_back_to_comet_secure_session_cookie() throws {
        let fallback = [
            OllamaCookieImporter.SessionInfo(
                cookies: [Self.makeCookie(name: "__Secure-session", value: "auth")],
                sourceLabel: "Comet Profile"),
        ]

        let selected = try OllamaCookieImporter.selectSessionInfoWithFallback(
            preferredCandidates: [],
            allowFallbackBrowsers: true,
            loadFallbackCandidates: { fallback })
        #expect(selected.sourceLabel == "Comet Profile")
    }

    private static func makeCookie(
        name: String,
        value: String,
        domain: String = "ollama.com") -> HTTPCookie
    {
        HTTPCookie(
            properties: [
                .name: name,
                .value: value,
                .domain: domain,
                .path: "/",
            ])!
    }
    #endif
}
