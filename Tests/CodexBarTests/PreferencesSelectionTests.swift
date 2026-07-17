import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct PreferencesSelectionTests {
    @Test
    func pane_persistence_tokens_round_trip() {
        let panes: [SettingsPane] = [
            .general,
            .notifications,
            .menuBar,
            .menu,
            .advanced,
            .about,
            .debug,
            .provider(.claude),
        ]
        for pane in panes {
            #expect(SettingsPane(persistenceToken: pane.persistenceToken) == pane)
        }
        #expect(SettingsPane(persistenceToken: "provider:definitely-not-a-provider") == nil)
        #expect(SettingsPane(persistenceToken: "") == nil)
    }

    @Test
    func legacy_display_token_restores_the_menu_bar_pane() {
        #expect(SettingsPane(persistenceToken: "display") == .menuBar)
    }

    @Test
    func selection_restores_persisted_pane_and_saves_changes() throws {
        let suite = "PreferencesSelectionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(PreferencesSelection(userDefaults: defaults).pane == .general)

        let selection = PreferencesSelection(userDefaults: defaults)
        selection.pane = .provider(.codex)
        #expect(defaults.string(forKey: PreferencesSelection.paneDefaultsKey) == "provider:codex")
        #expect(PreferencesSelection(userDefaults: defaults).pane == .provider(.codex))
    }
}
