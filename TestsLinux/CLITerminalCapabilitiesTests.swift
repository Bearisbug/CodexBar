import Foundation
import Testing
@testable import CodexBarCLI

struct CLITerminalCapabilitiesTests {
    @Test
    func detects_kitty_graphics_backend() {
        let env = ["KITTY_WINDOW_ID": "1", "TERM": "xterm-kitty"]
        #expect(CLITerminalCapabilities.detect(environment: env) == .kittyGraphics)
        #expect(CLITerminalCapabilities.supportsEnhancedCards(useColor: true, environment: env))
    }

    @Test
    func detects_ghostty_backend() {
        let env = ["GHOSTTY_RESOURCES_DIR": "/usr/share/ghostty", "TERM": "xterm-ghostty"]
        #expect(CLITerminalCapabilities.detect(environment: env) == .kittyGraphics)
    }

    @Test
    func detects_truecolor_without_graphics_env() {
        let env = ["COLORTERM": "truecolor", "TERM": "alacritty"]
        #expect(CLITerminalCapabilities.detect(environment: env) == .truecolor)
    }

    @Test
    func respects_forced_enhanced_env_override() {
        let env = ["TERM": "dumb", "CODEXBAR_CARDS_ENHANCED": "1"]
        #expect(CLITerminalCapabilities.supportsEnhancedCards(useColor: true, environment: env))
    }

    @Test
    func defaults_cards_to_standard_on_plain_ansi_terminals() {
        let env = ["TERM": "xterm-256color"]
        #expect(!CLITerminalCapabilities.supportsEnhancedCards(useColor: true, environment: env))
        #expect(!CLITerminalCapabilities.supportsEnhancedCards(useColor: false, environment: env))
    }

    @Test
    func defaults_cards_to_enhanced_on_truecolor_terminals() {
        let env = ["TERM": "xterm-256color", "COLORTERM": "truecolor"]
        #expect(CLITerminalCapabilities.supportsEnhancedCards(useColor: true, environment: env))
    }

    @Test
    func respects_forced_enhanced_opt_out() {
        let env = ["TERM": "xterm-256color", "CODEXBAR_CARDS_ENHANCED": "0"]
        #expect(!CLITerminalCapabilities.supportsEnhancedCards(useColor: true, environment: env))
    }
}
