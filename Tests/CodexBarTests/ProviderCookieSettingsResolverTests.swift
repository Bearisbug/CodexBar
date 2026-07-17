import CodexBarCore
import Foundation
import Testing

struct ProviderCookieSettingsResolverTests {
    @Test
    func shared_cookie_settings_preserve_Alibaba_token_plan_defaults() {
        let settings = ProviderSettingsSnapshot.AlibabaTokenPlanProviderSettings()

        #expect(settings.cookieSource == .auto)
        #expect(settings.manualCookieHeader == nil)
    }

    @Test
    func provider_cookie_settings_remain_distinct_nominal_types() {
        let cursor = ProviderSettingsSnapshot.CursorProviderSettings(
            cookieSource: .auto,
            manualCookieHeader: nil)
        let factory = ProviderSettingsSnapshot.FactoryProviderSettings(
            cookieSource: .auto,
            manualCookieHeader: nil)

        #expect(Self.providerName(cursor) == "cursor")
        #expect(Self.providerName(factory) == "factory")
    }

    @Test
    func selected_cookie_account_overrides_configured_credentials() {
        let settings = ProviderCookieSettingsResolver.resolve(
            provider: .manus,
            configuredSource: .auto,
            configuredHeader: "session_id=config",
            selectedAccount: Self.account(token: "account"))

        #expect(settings.cookieSource == .manual)
        #expect(settings.manualCookieHeader == "session_id=account")
    }

    @Test
    func configured_credentials_remain_when_no_account_is_selected() {
        let settings = ProviderCookieSettingsResolver.resolve(
            provider: .cursor,
            configuredSource: .manual,
            configuredHeader: "Cookie: session=config",
            selectedAccount: nil)

        #expect(settings.cookieSource == .manual)
        #expect(settings.manualCookieHeader == "Cookie: session=config")
    }

    @Test
    func environment_token_accounts_do_not_become_cookie_credentials() {
        let settings = ProviderCookieSettingsResolver.resolve(
            provider: .zai,
            configuredSource: .off,
            configuredHeader: nil,
            selectedAccount: Self.account(token: "api-token"))

        #expect(settings.cookieSource == .off)
        #expect(settings.manualCookieHeader == nil)
    }

    @Test
    func providers_without_token_account_support_ignore_selected_account() {
        let settings = ProviderCookieSettingsResolver.resolve(
            provider: .mimo,
            configuredSource: .auto,
            configuredHeader: "configured=true",
            selectedAccount: Self.account(token: "account=true"))

        #expect(settings.cookieSource == .auto)
        #expect(settings.manualCookieHeader == "configured=true")
    }

    private static func account(token: String) -> ProviderTokenAccount {
        ProviderTokenAccount(
            id: UUID(),
            label: "Test",
            token: token,
            addedAt: 0,
            lastUsed: nil)
    }

    private static func providerName(_: ProviderSettingsSnapshot.CursorProviderSettings) -> String {
        "cursor"
    }

    private static func providerName(_: ProviderSettingsSnapshot.FactoryProviderSettings) -> String {
        "factory"
    }
}
