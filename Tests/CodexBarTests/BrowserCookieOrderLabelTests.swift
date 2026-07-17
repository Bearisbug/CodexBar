import SweetCookieKit
import Testing
@testable import CodexBarCore

struct BrowserCookieOrderStatusStringTests {
    #if os(macOS)
    @Test
    func codex_cookie_import_order_keeps_firefox_ahead_of_extra_chromium_browsers() {
        let order = ProviderDefaults.metadata[.codex]?.browserCookieOrder ?? Browser.defaultImportOrder
        #expect(Array(order.prefix(3)) == [.safari, .chrome, .firefox])
    }

    @Test
    func automatic_cookie_import_includes_newly_supported_chromium_browsers() {
        #expect(Browser.defaultImportOrder.contains(.comet))
        #expect(Browser.defaultImportOrder.contains(.yandex))
    }

    @Test
    func cursor_no_session_includes_browser_login_hint() {
        let order = ProviderDefaults.metadata[.cursor]?.browserCookieOrder ?? Browser.defaultImportOrder
        let message = CursorStatusProbeError.noSessionCookie.errorDescription ?? ""
        #expect(message.contains(order.loginHint))
    }

    @Test
    func cursor_no_session_shows_full_disk_access_hint_before_browser_list() throws {
        let order = ProviderDefaults.metadata[.cursor]?.browserCookieOrder ?? Browser.defaultImportOrder
        let message = try #require(CursorStatusProbeError.noSessionCookie.errorDescription)
        let fullDiskAccessRange = try #require(message.range(of: CursorStatusProbeError.safariFullDiskAccessHint))
        let browserListRange = try #require(message.range(of: order.loginHint))

        #expect(fullDiskAccessRange.lowerBound < browserListRange.lowerBound)
    }

    @Test
    func factory_no_session_includes_browser_login_hint() {
        let order = ProviderDefaults.metadata[.factory]?.browserCookieOrder ?? Browser.defaultImportOrder
        let message = FactoryStatusProbeError.noSessionCookie.errorDescription ?? ""
        #expect(message.contains(order.loginHint))
    }

    @Test
    func opencode_go_automatic_cookies_use_full_provider_browser_order() {
        let order = OpenCodeWebCookieSupport.automaticImportOrder(provider: .opencodego)
        #expect(order == ProviderDefaults.metadata[.opencodego]?.browserCookieOrder)
        #expect(order.contains(.edge))
        #expect(order.contains(.firefox))
    }

    @Test
    func opencode_automatic_cookies_only_use_chrome_and_dia() {
        let order = OpenCodeWebCookieSupport.automaticImportOrder(provider: .opencode)
        #expect(order == ProviderDefaults.metadata[.opencode]?.browserCookieOrder)
        #expect(order == ProviderBrowserCookieDefaults.opencodeCookieImportOrder)
        #expect(order == [.chrome, .dia])
    }

    @Test
    func opencode_automatic_cookies_bound_keychain_prompt_labels_to_chrome_and_dia() {
        let order = OpenCodeWebCookieSupport.automaticImportOrder(provider: .opencode)
        let labels = order.flatMap(\.safeStorageLabels).map(\.service)

        #expect(labels == ["Chrome Safe Storage", "Dia Safe Storage"])
        #expect(!order.contains(.safari))
        #expect(!order.contains(.firefox))
        #expect(!order.contains(.edge))
        #expect(!order.contains(.brave))
        #expect(!order.contains(.arc))
        #expect(!order.contains(.chromium))
    }

    @Test
    func mimo_cookie_import_order_supports_safari_firefox_and_edge() {
        let order = ProviderDefaults.metadata[.mimo]?.browserCookieOrder ?? Browser.defaultImportOrder
        #expect(order == ProviderBrowserCookieDefaults.mimoCookieImportOrder)
        #expect(order == [.safari, .chrome, .chromeBeta, .chromeCanary, .firefox, .edge])
        #expect(order.first == .safari)
        #expect(order.contains(.firefox))
        #expect(order.contains(.edge))
        #expect(!order.contains(.arc))
    }

    @Test
    func copilot_cookie_imports_default_to_chrome_only() {
        #expect(ProviderDefaults.metadata[.copilot]?.browserCookieOrder == [.chrome])
        #expect(ProviderBrowserCookieDefaults.copilotCookieImportOrder == [.chrome])
    }

    @Test
    func mistral_cookie_import_order_supports_chrome_firefox_and_safari() {
        let order = ProviderDefaults.metadata[.mistral]?.browserCookieOrder ?? Browser.defaultImportOrder
        #expect(order == ProviderBrowserCookieDefaults.mistralCookieImportOrder)
        #expect(order == [.chrome, .firefox, .safari])
        #expect(order.first == .chrome)
        #expect(order.contains(.firefox))
        #expect(!order.contains(.edge))
        #expect(!order.contains(.arc))
        #expect(MistralCookieImporter.resolvedImportOrder(nil) == order)
        #expect(MistralCookieImporter.resolvedImportOrder([]) == order)
        #expect(MistralCookieImporter.resolvedImportOrder([.firefox]) == [.firefox])
    }

    @Test
    func longcat_cookie_imports_default_to_chrome_only() {
        #expect(ProviderDefaults.metadata[.longcat]?.browserCookieOrder == [.chrome])
        #expect(ProviderBrowserCookieDefaults.longcatCookieImportOrder == [.chrome])
    }
    #endif
}
