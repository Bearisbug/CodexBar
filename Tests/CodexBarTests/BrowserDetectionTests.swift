import Foundation
import os.lock
import Testing
@testable import CodexBarCore

#if os(macOS)
import SweetCookieKit

@Suite(.serialized)
struct BrowserDetectionTests {
    private func detection(
        homeDirectory: String,
        installedBrowsers: Set<Browser>) -> BrowserDetection
    {
        let installedAppPaths = Set(installedBrowsers.map { "/Applications/\($0.appBundleName).app" })
        return BrowserDetection(
            homeDirectory: homeDirectory,
            cacheTTL: 0,
            now: Date.init,
            fileExists: { path in
                if path.hasSuffix(".app") {
                    return installedAppPaths.contains(path)
                }
                return FileManager.default.fileExists(atPath: path)
            },
            directoryContents: { path in
                try? FileManager.default.contentsOfDirectory(atPath: path)
            },
            applicationURLs: { _ in [] },
            profileAccessIssue: { _ in nil })
    }

    private static func labelIDs(for browser: Browser) -> [String] {
        browser.safeStorageLabels.map { self.labelID(service: $0.service, account: $0.account) }
    }

    private static func labelID(service: String, account: String?) -> String {
        "\(service)|\(account ?? "")"
    }

    @Test(.disabled(
        if: ProcessInfo.processInfo.environment[BrowserCookieAccessGate.allowTestCookieAccessEnvironmentKey] == "1",
        "Default-home cookie access is explicitly enabled for this test run."))
    func default_home_detection_is_suppressed_before_profile_probes() throws {
        let probeCount = OSAllocatedUnfairLock(initialState: 0)
        let defaultHome = try #require(BrowserCookieClient.defaultHomeDirectories().first)
        let detection = BrowserDetection(
            homeDirectory: defaultHome.path,
            cacheTTL: 0,
            fileExists: { _ in
                probeCount.withLock { $0 += 1 }
                return false
            },
            directoryContents: { _ in
                probeCount.withLock { $0 += 1 }
                return nil
            })

        _ = detection.isCookieSourceAvailable(.chrome)
        #expect(probeCount.withLock { $0 } == 0)
    }

    @Test(.disabled(
        if: ProcessInfo.processInfo.environment[BrowserCookieAccessGate.allowTestCookieAccessEnvironmentKey] == "1",
        "Default-home cookie access is explicitly enabled for this test run."))
    func default_client_reports_structured_suppression_before_store_discovery() {
        let client = BrowserCookieClient()

        #expect(throws: BrowserCookieStoreAccessSuppressedError.self) {
            _ = try client.codexBarStores(for: .chrome)
        }
        #expect(throws: BrowserCookieStoreAccessSuppressedError.self) {
            _ = try client.codexBarRecords(
                matching: BrowserCookieQuery(domains: ["example.com"]),
                in: .safari)
        }
    }

    @Test
    func cookie_store_decision_allows_production_and_explicit_test_opt_in() {
        let defaultHomes = BrowserCookieClient.defaultHomeDirectories()
        let testProcess = "swiftpm-testing-helper"

        #expect(BrowserCookieAccessGate.cookieStoreAccessDecision(
            homeDirectories: defaultHomes,
            processName: testProcess,
            environment: [:]) == .suppressed)
        #expect(BrowserCookieAccessGate.cookieStoreAccessDecision(
            homeDirectories: defaultHomes,
            processName: testProcess,
            environment: [BrowserCookieAccessGate.allowTestCookieAccessEnvironmentKey: "1"]) == .allowed)
        #expect(BrowserCookieAccessGate.cookieStoreAccessDecision(
            homeDirectories: defaultHomes,
            processName: "CodexBar",
            environment: [:]) == .allowed)
    }

    @Test(.disabled(
        if: ProcessInfo.processInfo.environment[BrowserCookieAccessGate.allowTestCookieAccessEnvironmentKey] == "1",
        "Default-home cookie access is explicitly enabled for this test run."))
    func safari_is_installed_but_default_cookie_access_is_disabled_during_tests() {
        #expect(BrowserDetection(cacheTTL: 0).isAppInstalled(.safari) == true)
        #expect(BrowserDetection(cacheTTL: 0).isCookieSourceAvailable(.safari) == false)
    }

    @Test(.disabled(
        if: ProcessInfo.processInfo.environment[BrowserCookieAccessGate.allowTestCookieAccessEnvironmentKey] == "1",
        "Default-home cookie access is explicitly enabled for this test run."))
    func default_cookie_candidates_exclude_safari_during_tests() {
        let detection = BrowserDetection(cacheTTL: 0)
        let browsers: [Browser] = [.safari, .chrome, .firefox]
        #expect(browsers.cookieImportCandidates(using: detection).contains(.safari) == false)
    }

    @Test
    func explicit_isolated_home_keeps_safari_cookie_source_available() {
        let detection = BrowserDetection(homeDirectory: "/tmp/codexbar-browser-detection", cacheTTL: 0)
        #expect(detection.isCookieSourceAvailable(.safari))
    }

    @Test
    func cookie_client_permits_isolated_chromium_stores_during_tests() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profile = temp
            .appendingPathComponent("Library/Application Support/Google/Chrome/Default/Network")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: profile.appendingPathComponent("Cookies").path, contents: Data())
        defer { try? FileManager.default.removeItem(at: temp) }

        let client = BrowserCookieClient(configuration: .init(homeDirectories: [temp]))
        let stores = try KeychainAccessGate.withTaskOverrideForTesting(false) {
            try KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting { _, _ in .allowed } operation: {
                try ProviderInteractionContext.$current.withValue(.userInitiated) {
                    try client.codexBarStores(for: .chrome)
                }
            }
        }
        #expect(stores.count == 1)
    }

    @Test
    func filter_preserves_order() {
        BrowserCookieAccessGate.resetForTesting()

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let firefoxProfile = temp
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Firefox")
            .appendingPathComponent("Profiles")
            .appendingPathComponent("abc.default-release")
        try? FileManager.default.createDirectory(at: firefoxProfile, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: firefoxProfile.appendingPathComponent("cookies.sqlite").path,
            contents: Data())

        let detection = self.detection(homeDirectory: temp.path, installedBrowsers: [.firefox])
        let browsers: [Browser] = [.firefox, .safari, .chrome]
        // Chrome is filtered out deterministically because it lacks usable on-disk profile/cookie store data.
        #expect(browsers.cookieImportCandidates(using: detection) == [.firefox, .safari])
    }

    @Test
    func chrome_requires_profile_data() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let detection = self.detection(homeDirectory: temp.path, installedBrowsers: [.chrome])
        #expect(detection.isCookieSourceAvailable(.chrome) == false)

        let profile = temp
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Google")
            .appendingPathComponent("Chrome")
            .appendingPathComponent("Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let cookiesDir = profile.appendingPathComponent("Network")
        try FileManager.default.createDirectory(at: cookiesDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: cookiesDir.appendingPathComponent("Cookies").path, contents: Data())

        #expect(detection.isCookieSourceAvailable(.chrome) == true)
    }

    @Test
    func process_filters_chromium_candidates_despite_false_global_keychain_override() throws {
        guard ProcessInfo.processInfo.environment["CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS"] != "1" else { return }
        KeychainAccessGate.resetOverrideForTesting()
        defer { KeychainAccessGate.resetOverrideForTesting() }

        KeychainAccessGate.isDisabled = false

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let profile = temp
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Google")
            .appendingPathComponent("Chrome")
            .appendingPathComponent("Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let cookiesDir = profile.appendingPathComponent("Network")
        try FileManager.default.createDirectory(at: cookiesDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: cookiesDir.appendingPathComponent("Cookies").path, contents: Data())

        let detection = self.detection(homeDirectory: temp.path, installedBrowsers: [.chrome])
        let browsers: [Browser] = [.chrome, .safari]
        #expect(browsers.cookieImportCandidates(using: detection) == [.safari])
    }

    @Test
    func keychain_interaction_suppresses_chromium_family_during_cooldown() {
        BrowserCookieAccessGate.resetForTesting()
        defer { BrowserCookieAccessGate.resetForTesting() }

        let start = Date(timeIntervalSince1970: 1000)
        var preflightCount = 0

        KeychainAccessGate.withTaskOverrideForTesting(false) {
            ProviderInteractionContext.$current.withValue(.userInitiated) {
                KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting { _, _ in
                    preflightCount += 1
                    return .interactionRequired
                } operation: {
                    #expect(BrowserCookieAccessGate.shouldAttempt(.chrome, now: start) == false)
                }

                KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting { _, _ in
                    preflightCount += 1
                    return .allowed
                } operation: {
                    #expect(BrowserCookieAccessGate.shouldAttempt(.chrome, now: start.addingTimeInterval(60)) == false)
                    #expect(BrowserCookieAccessGate.shouldAttempt(.dia, now: start.addingTimeInterval(60)) == false)
                    #expect(
                        BrowserCookieAccessGate.shouldAttempt(
                            .chrome,
                            now: start.addingTimeInterval((60 * 60 * 6) + 1)) == true)
                }
            }
        }

        #expect(preflightCount == 2)
    }

    @Test
    func background_cookie_import_skips_chromium_before_keychain_preflight() {
        BrowserCookieAccessGate.resetForTesting()
        defer { BrowserCookieAccessGate.resetForTesting() }

        var preflightCount = 0

        KeychainAccessGate.withTaskOverrideForTesting(false) {
            KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting { _, _ in
                preflightCount += 1
                return .allowed
            } operation: {
                ProviderInteractionContext.$current.withValue(.background) {
                    #expect(BrowserCookieAccessGate.shouldAttempt(.chrome) == false)
                    #expect(BrowserCookieAccessGate.shouldAttempt(.safari) == true)
                }
            }
        }

        #expect(preflightCount == 0)
    }

    @Test
    func background_cookie_import_skips_chromium_without_probing_keychain_interaction() {
        BrowserCookieAccessGate.resetForTesting()
        defer { BrowserCookieAccessGate.resetForTesting() }

        var preflightCount = 0

        KeychainAccessGate.withTaskOverrideForTesting(false) {
            KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting { _, _ in
                preflightCount += 1
                return .interactionRequired
            } operation: {
                ProviderInteractionContext.$current.withValue(.background) {
                    #expect(BrowserCookieAccessGate.shouldAttempt(.chrome) == false)
                    #expect(BrowserCookieAccessGate.shouldAttempt(.safari) == true)
                }
            }
        }

        #expect(preflightCount == 0)
    }

    @Test
    func recorded_browser_denial_suppresses_automatic_family_and_permits_explicit_source_retry() {
        BrowserCookieAccessGate.resetForTesting()
        defer { BrowserCookieAccessGate.resetForTesting() }

        let start = Date(timeIntervalSince1970: 1500)
        var preflightCount = 0

        KeychainAccessGate.withTaskOverrideForTesting(false) {
            BrowserCookieAccessGate.recordIfNeeded(
                BrowserCookieError.accessDenied(browser: .arc, details: "denied"),
                now: start)
            KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting { _, _ in
                preflightCount += 1
                return .allowed
            } operation: {
                ProviderInteractionContext.$current.withValue(.background) {
                    #expect(BrowserCookieAccessGate.shouldAttempt(.chrome, now: start.addingTimeInterval(1)) == false)
                    #expect(BrowserCookieAccessGate.shouldAttempt(.edge, now: start.addingTimeInterval(1)) == false)
                    #expect(BrowserCookieAccessGate.shouldAttempt(.safari, now: start.addingTimeInterval(1)) == true)
                }
                BrowserCookieAccessGate.withExplicitRetry {
                    ProviderInteractionContext.$current.withValue(.userInitiated) {
                        #expect(BrowserCookieAccessGate
                            .shouldAttempt(.chrome, now: start.addingTimeInterval(2)) == false)
                        #expect(BrowserCookieAccessGate.shouldAttempt(.arc, now: start.addingTimeInterval(2)) == true)
                        #expect(BrowserCookieAccessGate.claimExplicitRetryCookieReadIfNeeded(for: .arc))
                        BrowserCookieAccessGate.recordAllowed(for: .arc)
                    }
                }
                ProviderInteractionContext.$current.withValue(.userInitiated) {
                    #expect(BrowserCookieAccessGate.shouldAttempt(.chrome, now: start.addingTimeInterval(3)) == true)
                }
            }
        }

        #expect(preflightCount == 2)
    }

    @Test
    func denied_explicit_cookie_read_closes_retry_scope() {
        BrowserCookieAccessGate.resetForTesting()
        defer { BrowserCookieAccessGate.resetForTesting() }

        let start = Date(timeIntervalSince1970: 1700)
        BrowserCookieAccessGate.recordDenied(for: .arc, now: start)

        KeychainAccessGate.withTaskOverrideForTesting(false) {
            BrowserCookieAccessGate.withExplicitRetry {
                ProviderInteractionContext.$current.withValue(.userInitiated) {
                    #expect(BrowserCookieAccessGate.shouldAttempt(.arc, now: start.addingTimeInterval(1)))
                    #expect(BrowserCookieAccessGate.claimExplicitRetryCookieReadIfNeeded(for: .arc))

                    BrowserCookieAccessGate.recordDenied(for: .arc, now: start.addingTimeInterval(2))

                    #expect(BrowserCookieAccessGate.shouldAttempt(.arc, now: start.addingTimeInterval(3)) == false)
                    #expect(BrowserCookieAccessGate.shouldAttempt(.edge, now: start.addingTimeInterval(3)) == false)
                }
            }
        }
    }

    @Test
    func chrome_keychain_preflight_queries_only_chrome_labels() {
        BrowserCookieAccessGate.resetForTesting()
        defer { BrowserCookieAccessGate.resetForTesting() }

        let chromeLabels = Self.labelIDs(for: .chrome)
        let chromeLabelSet = Set(chromeLabels)
        var queriedLabels: [String] = []

        KeychainAccessGate.withTaskOverrideForTesting(false) {
            KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting { service, account in
                let label = Self.labelID(service: service, account: account)
                queriedLabels.append(label)
                return .notFound
            } operation: {
                ProviderInteractionContext.$current.withValue(.userInitiated) {
                    #expect(BrowserCookieAccessGate.shouldAttempt(.chrome) == true)
                }
            }
        }

        #expect(queriedLabels == chromeLabels)
        #expect(queriedLabels.allSatisfy { chromeLabelSet.contains($0) })
    }

    @Test
    func dia_keychain_preflight_queries_only_dia_labels() {
        BrowserCookieAccessGate.resetForTesting()
        defer { BrowserCookieAccessGate.resetForTesting() }

        let diaLabels = Self.labelIDs(for: .dia)
        let diaLabelSet = Set(diaLabels)
        var queriedLabels: [String] = []

        KeychainAccessGate.withTaskOverrideForTesting(false) {
            KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting { service, account in
                let label = Self.labelID(service: service, account: account)
                queriedLabels.append(label)
                return .notFound
            } operation: {
                ProviderInteractionContext.$current.withValue(.userInitiated) {
                    #expect(BrowserCookieAccessGate.shouldAttempt(.dia) == true)
                }
            }
        }

        #expect(queriedLabels == diaLabels)
        #expect(queriedLabels.allSatisfy { diaLabelSet.contains($0) })
    }

    @Test
    func browser_keychain_interaction_suppresses_family_and_permits_scoped_explicit_retry() throws {
        BrowserCookieAccessGate.resetForTesting()
        defer { BrowserCookieAccessGate.resetForTesting() }

        let start = Date(timeIntervalSince1970: 2000)
        let chromeLabels = Self.labelIDs(for: .chrome)
        let diaLabels = Self.labelIDs(for: .dia)
        let firstChromeLabel = try #require(chromeLabels.first)
        let firstDiaLabel = try #require(diaLabels.first)
        let allowedLabels = Set(chromeLabels + diaLabels)
        var queriedLabels: [String] = []

        KeychainAccessGate.withTaskOverrideForTesting(false) {
            KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting { service, account in
                let label = Self.labelID(service: service, account: account)
                queriedLabels.append(label)
                if label == firstChromeLabel {
                    return .allowed
                }
                if label == firstDiaLabel {
                    return .interactionRequired
                }
                return .notFound
            } operation: {
                ProviderInteractionContext.$current.withValue(.userInitiated) {
                    #expect(BrowserCookieAccessGate.shouldAttempt(.chrome, now: start) == true)
                    #expect(BrowserCookieAccessGate.shouldAttempt(.dia, now: start.addingTimeInterval(1)) == false)
                    #expect(BrowserCookieAccessGate.shouldAttempt(.chrome, now: start.addingTimeInterval(60)) == false)
                    #expect(BrowserCookieAccessGate.shouldAttempt(.dia, now: start.addingTimeInterval(60)) == false)
                }
                BrowserCookieAccessGate.withExplicitRetry {
                    ProviderInteractionContext.$current.withValue(.userInitiated) {
                        #expect(BrowserCookieAccessGate
                            .shouldAttempt(.chrome, now: start.addingTimeInterval(61)) == false)
                        #expect(BrowserCookieAccessGate.shouldAttempt(.dia, now: start.addingTimeInterval(61)) == true)
                        #expect(BrowserCookieAccessGate
                            .shouldAttempt(.edge, now: start.addingTimeInterval(61)) == false)
                    }
                }
            }
        }

        #expect(queriedLabels == [firstChromeLabel, firstDiaLabel, firstDiaLabel])
        #expect(queriedLabels.allSatisfy { allowedLabels.contains($0) })
    }

    @Test
    func dia_requires_profile_data() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let detection = self.detection(homeDirectory: temp.path, installedBrowsers: [.dia])
        #expect(detection.isCookieSourceAvailable(.dia) == false)

        let profile = temp
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Dia")
            .appendingPathComponent("User Data")
            .appendingPathComponent("Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let cookiesDir = profile.appendingPathComponent("Network")
        try FileManager.default.createDirectory(at: cookiesDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: cookiesDir.appendingPathComponent("Cookies").path, contents: Data())

        #expect(detection.isCookieSourceAvailable(.dia) == true)
    }

    @Test
    func removed_browser_with_stale_cookies_is_not_a_candidate() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cookies = temp
            .appendingPathComponent("Library/Application Support/Dia/User Data/Default/Network/Cookies")
        try FileManager.default.createDirectory(
            at: cookies.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: cookies.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: temp) }

        let detection = self.detection(homeDirectory: temp.path, installedBrowsers: [])

        #expect(detection.hasUsableProfileData(.dia))
        #expect(!detection.isCookieSourceAvailable(.dia))
        #expect([Browser.dia].cookieImportCandidates(using: detection).isEmpty)
    }

    @Test
    func browser_uninstall_invalidates_cookie_source_immediately() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cookies = temp
            .appendingPathComponent("Library/Application Support/Google/Chrome/Default/Network/Cookies")
        try FileManager.default.createDirectory(
            at: cookies.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: cookies.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: temp) }

        let installed = OSAllocatedUnfairLock(initialState: true)
        let detection = BrowserDetection(
            homeDirectory: temp.path,
            cacheTTL: 600,
            fileExists: { path in
                if path == "/Applications/Google Chrome.app" {
                    return installed.withLock { $0 }
                }
                return FileManager.default.fileExists(atPath: path)
            },
            directoryContents: { path in
                try? FileManager.default.contentsOfDirectory(atPath: path)
            })

        #expect(detection.isCookieSourceAvailable(.chrome))
        installed.withLock { $0 = false }
        #expect(!detection.isCookieSourceAvailable(.chrome))
    }

    @Test
    func registered_browser_outside_Applications_is_a_candidate() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cookies = temp
            .appendingPathComponent("Library/Application Support/Google/Chrome/Default/Network/Cookies")
        try FileManager.default.createDirectory(
            at: cookies.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: cookies.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: temp) }

        let appURL = URL(fileURLWithPath: "/Volumes/Tools/Google Chrome.app")
        let detection = BrowserDetection(
            homeDirectory: temp.path,
            cacheTTL: 0,
            now: Date.init,
            fileExists: { path in
                path == appURL.path || FileManager.default.fileExists(atPath: path)
            },
            directoryContents: { path in
                try? FileManager.default.contentsOfDirectory(atPath: path)
            },
            applicationURLs: { appName in
                appName == Browser.chrome.appBundleName ? [appURL] : []
            },
            profileAccessIssue: { _ in nil })

        #expect(detection.isCookieSourceAvailable(.chrome))
    }

    @Test
    func interactive_source_accepts_an_installed_browser_before_its_cookie_store_exists() {
        let home = "/tmp/codexbar-fresh-browser-profile"
        let profileRoot = "\(home)/Library/Application Support/Google/Chrome"
        let applicationPath = "/Applications/Google Chrome.app"
        let freshInstall = BrowserDetection(
            homeDirectory: home,
            cacheTTL: 600,
            now: Date.init,
            fileExists: { $0 == applicationPath },
            directoryContents: { _ in nil },
            applicationURLs: { _ in [] },
            profileAccessIssue: { _ in nil })

        #expect(!freshInstall.isCookieSourceAvailable(.chrome))
        #expect(freshInstall.isInteractiveCookieSourceAvailable(.chrome))

        let inaccessibleProfile = BrowserDetection(
            homeDirectory: home,
            cacheTTL: 600,
            now: Date.init,
            fileExists: { $0 == applicationPath },
            directoryContents: { _ in nil },
            applicationURLs: { _ in [] },
            profileAccessIssue: { _ in .accessDenied })

        #expect(!inaccessibleProfile.isInteractiveCookieSourceAvailable(.chrome))

        let emptyReadableProfile = BrowserDetection(
            homeDirectory: home,
            cacheTTL: 600,
            now: Date.init,
            fileExists: { $0 == applicationPath || $0 == profileRoot },
            directoryContents: { $0 == profileRoot ? [] : nil },
            applicationURLs: { _ in [] },
            profileAccessIssue: { _ in nil })

        #expect(!emptyReadableProfile.isCookieSourceAvailable(.chrome))
        #expect(emptyReadableProfile.isInteractiveCookieSourceAvailable(.chrome))
    }

    @Test
    func interactive_source_treats_a_missing_production_profile_path_as_fresh() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let detection = BrowserDetection(
            homeDirectory: temp.path,
            cacheTTL: 0,
            fileExists: { path in
                path == "/Applications/Google Chrome.app" || FileManager.default.fileExists(atPath: path)
            },
            directoryContents: { path in
                try? FileManager.default.contentsOfDirectory(atPath: path)
            })

        #expect(detection.isInteractiveCookieSourceAvailable(.chrome))
    }

    @Test
    func stale_registered_browser_outside_Applications_is_not_a_candidate() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cookies = temp
            .appendingPathComponent("Library/Application Support/Google/Chrome/Default/Network/Cookies")
        try FileManager.default.createDirectory(
            at: cookies.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: cookies.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: temp) }

        let staleAppURL = URL(fileURLWithPath: "/Volumes/Removed/Google Chrome.app")
        let detection = BrowserDetection(
            homeDirectory: temp.path,
            cacheTTL: 0,
            now: Date.init,
            fileExists: { path in
                if path.hasSuffix("/Google Chrome.app") {
                    return false
                }
                return FileManager.default.fileExists(atPath: path)
            },
            directoryContents: { path in
                try? FileManager.default.contentsOfDirectory(atPath: path)
            },
            applicationURLs: { appName in
                appName == Browser.chrome.appBundleName ? [staleAppURL] : []
            },
            profileAccessIssue: { _ in nil })

        #expect(!detection.isCookieSourceAvailable(.chrome))
    }

    @Test
    func installed_browser_reports_denied_profile_access() {
        let home = "/tmp/codexbar-denied-browser-profile"
        let profileRoot = "\(home)/Library/Application Support/Google/Chrome"
        let detection = BrowserDetection(
            homeDirectory: home,
            cacheTTL: 0,
            now: Date.init,
            fileExists: { path in
                path == "/Applications/Google Chrome.app" || path == profileRoot
            },
            directoryContents: { _ in nil },
            applicationURLs: { _ in [] },
            profileAccessIssue: { _ in .accessDenied })

        #expect(detection.cookieSourceProfileAccessIssue(.chrome) == .accessDenied)
        #expect(!detection.isCookieSourceAvailable(.chrome))
        #expect(!detection.isInteractiveCookieSourceAvailable(.chrome))
    }

    @Test
    func firefox_requires_default_profile_dir() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let profiles = temp
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Firefox")
            .appendingPathComponent("Profiles")
        try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)

        let detection = self.detection(homeDirectory: temp.path, installedBrowsers: [.firefox])
        #expect(detection.isCookieSourceAvailable(.firefox) == false)

        let profile = profiles.appendingPathComponent("abc.default-release")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: profile.appendingPathComponent("cookies.sqlite").path, contents: Data())
        #expect(detection.isCookieSourceAvailable(.firefox) == true)
    }

    @Test
    func firefox_developer_edition_unlocks_the_shared_Firefox_cookie_store() {
        let home = "/tmp/codexbar-firefox-developer-edition"
        let profiles = "\(home)/Library/Application Support/Firefox/Profiles"
        let cookieDB = "\(profiles)/abc.default-release/cookies.sqlite"
        let detection = BrowserDetection(
            homeDirectory: home,
            cacheTTL: 0,
            now: Date.init,
            fileExists: { path in
                path == "/Applications/Firefox Developer Edition.app" ||
                    path == profiles ||
                    path == cookieDB
            },
            directoryContents: { path in
                path == profiles ? ["abc.default-release"] : nil
            },
            applicationURLs: { _ in [] },
            profileAccessIssue: { _ in nil })

        #expect(detection.isCookieSourceAvailable(.firefox))
    }

    @Test
    func zen_accepts_uppercase_default_profile_dir() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let profiles = temp
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("zen")
            .appendingPathComponent("Profiles")
        try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)

        let detection = self.detection(homeDirectory: temp.path, installedBrowsers: [.zen])
        #expect(detection.isCookieSourceAvailable(.zen) == false)

        let profile = profiles.appendingPathComponent("abc.Default (release)")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: profile.appendingPathComponent("cookies.sqlite").path, contents: Data())
        #expect(detection.isCookieSourceAvailable(.zen) == true)
    }
}

#else

struct BrowserDetectionTests {
    @Test
    func non_mac_OS_returns_no_browsers() {
        #expect(BrowserDetection(cacheTTL: 0).isCookieSourceAvailable(Browser()) == false)
    }

    @Test
    func non_mac_OS_filter_returns_empty() {
        let detection = BrowserDetection(cacheTTL: 0)
        let browsers = [Browser(), Browser()]
        #expect(browsers.cookieImportCandidates(using: detection).isEmpty == true)
    }
}

#endif
