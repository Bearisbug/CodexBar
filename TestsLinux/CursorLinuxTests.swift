#if os(Linux)
import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

struct CursorLinuxTests {
    @Test
    func Cursor_database_path_honors_absolute_XDG_config_home() {
        let path = CursorAppAuthStore.resolveDefaultDBPath(
            home: "/home/test",
            environment: ["XDG_CONFIG_HOME": "/custom/config"])
        #expect(path == "/custom/config/Cursor/User/globalStorage/state.vscdb")
    }

    @Test
    func Cursor_database_path_falls_back_to_dot_config() {
        let path = CursorAppAuthStore.resolveDefaultDBPath(
            home: "/home/test",
            environment: [:])
        #expect(path == "/home/test/.config/Cursor/User/globalStorage/state.vscdb")
    }

    @Test
    func Cursor_database_path_rejects_relative_XDG_config_home() {
        let path = CursorAppAuthStore.resolveDefaultDBPath(
            home: "/home/test",
            environment: ["XDG_CONFIG_HOME": "relative/config"])
        #expect(path == "/home/test/.config/Cursor/User/globalStorage/state.vscdb")
    }

    @Test
    func Cursor_automatic_source_does_not_require_macOS_web_support() {
        #expect(!CodexBarCLI.sourceModeRequiresWebSupport(
            .auto,
            provider: .cursor,
            settings: ProviderSettingsSnapshot.make(
                cursor: .init(cookieSource: .auto, manualCookieHeader: nil))))
    }

    @Test
    func Cursor_descriptor_accepts_explicit_web_source() {
        #expect(CursorProviderDescriptor.descriptor.fetchPlan.sourceModes.contains(.web))
    }

    @Test
    func Cursor_manual_cookie_does_not_require_macOS_web_support() {
        #expect(!CodexBarCLI.sourceModeRequiresWebSupport(
            .web,
            provider: .cursor,
            settings: ProviderSettingsSnapshot.make(
                cursor: .init(
                    cookieSource: .manual,
                    manualCookieHeader: "WorkosCursorSessionToken=test"))))
    }

    @Test
    func disabled_Cursor_web_source_still_requires_macOS_web_support() {
        #expect(CodexBarCLI.sourceModeRequiresWebSupport(
            .web,
            provider: .cursor,
            settings: ProviderSettingsSnapshot.make(
                cursor: .init(cookieSource: .off, manualCookieHeader: nil))))
    }
}
#endif
