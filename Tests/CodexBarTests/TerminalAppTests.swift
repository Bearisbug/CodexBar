import AppKit
import Foundation
import Testing
@testable import CodexBar

@Suite("TerminalApp")
struct TerminalAppTests {
    @Test
    @MainActor
    func default_is_terminal() throws {
        let suite = "TerminalAppTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        #expect(store.terminalApp == .terminal)
    }

    @Test
    @MainActor
    func setting_terminal_app_persists_it() throws {
        let suite = "TerminalAppTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        store.terminalApp = .iTerm
        #expect(store.terminalApp == .iTerm)
        #expect(defaults.string(forKey: "terminalApp") == "iTerm")
    }

    @Test
    @MainActor
    func invalid_stored_value_falls_back_to_terminal() throws {
        let suite = "TerminalAppTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("nonexistent", forKey: "terminalApp")
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        #expect(store.terminalApp == .terminal)
    }

    @Test
    func only_two_cases_exist() {
        #expect(TerminalApp.allCases.count == 2)
    }

    @Test
    func installed_terminals_always_include_Terminal_and_detected_alternatives() {
        let iTermURL = URL(fileURLWithPath: "/Applications/iTerm.app")
        let installed = TerminalApp.installed { bundleIdentifier in
            bundleIdentifier == TerminalApp.iTerm.bundleIdentifier ? iTermURL : nil
        }

        #expect(installed == [.terminal, .iTerm])
        #expect(TerminalApp.installed { _ in nil } == [.terminal])
    }

    @Test
    func picker_options_preserve_an_unavailable_persisted_selection() {
        #expect(TerminalApp.pickerOptions(selected: .terminal) { _ in nil } == [.terminal])
        #expect(TerminalApp.pickerOptions(selected: .iTerm) { _ in nil } == [.terminal, .iTerm])
    }

    @Test
    @MainActor
    func picker_icon_has_compact_intrinsic_size() {
        let source = NSImage(size: NSSize(width: 128, height: 64))

        let icon = TerminalApp.pickerIcon(from: source)

        #expect(icon.size == NSSize(width: 16, height: 16))
    }

    @Test
    @MainActor
    func zero_size_picker_icon_remains_compact() {
        let icon = TerminalApp.pickerIcon(from: NSImage(size: .zero))

        #expect(icon.size == NSSize(width: 16, height: 16))
    }

    @Test
    func all_cases_have_unique_bundle_identifiers() {
        let ids = TerminalApp.allCases.map(\.bundleIdentifier)
        #expect(Set(ids).count == TerminalApp.allCases.count)
    }

    @Test
    func all_cases_have_non_empty_labels() {
        for app in TerminalApp.allCases {
            #expect(!app.label.isEmpty)
        }
    }

    @Test
    func round_trip_all_cases_through_raw_value() {
        for app in TerminalApp.allCases {
            #expect(TerminalApp(rawValue: app.rawValue) == app)
        }
    }

    @Test
    func escapes_commands_embedded_in_AppleScript_strings() {
        let escaped = TerminalApp.escapeForAppleScript(#"echo "C:\tmp""#)

        #expect(escaped == #"echo \"C:\\tmp\""#)
    }

    @Test
    func builds_terminal_specific_launch_scripts() {
        let command = #"echo "hello""#
        let terminalScript = TerminalApp.terminal.appleScript(command: command)
        let iTermScript = TerminalApp.iTerm.appleScript(command: command)

        #expect(terminalScript.contains(#"tell application "Terminal""#))
        #expect(terminalScript.contains(#"do script "echo \"hello\"""#))
        #expect(iTermScript.contains(#"tell application "iTerm""#))
        #expect(iTermScript.contains(#"write text "echo \"hello\"""#))
    }
}
