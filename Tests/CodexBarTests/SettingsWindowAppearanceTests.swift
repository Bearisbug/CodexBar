import AppKit
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct SettingsWindowAppearanceTests {
    @Test
    func settings_sidebar_uses_a_fixed_noncollapsible_width() {
        #expect(SettingsPane.sidebarWidth == 260)
        #expect(SettingsPane.windowMinWidth > SettingsPane.sidebarWidth)
        #expect(SettingsPane.detailMaxWidth > SettingsPane.windowMinWidth - SettingsPane.sidebarWidth)
    }

    @Test
    func settings_window_sizing_repairs_collapsed_saved_frames() {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 160, width: 180, height: 140),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        let originalMaxY = window.frame.maxY

        SettingsWindowSizing.enforceMinimumSize(window)

        #expect(window.minSize.width == SettingsPane.windowMinWidth)
        #expect(window.minSize.height >= SettingsPane.windowMinHeight)
        #expect(window.frame.width >= window.minSize.width)
        #expect(window.frame.height >= window.minSize.height)
        #expect(abs(window.frame.maxY - originalMaxY) < 1)
    }

    @Test
    func settings_window_sizing_leaves_valid_frames_alone() {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 160, width: SettingsPane.windowWidth, height: SettingsPane.windowHeight),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        let originalFrame = window.frame

        SettingsWindowSizing.enforceMinimumSize(window)

        #expect(window.frame == originalFrame)
        #expect(window.minSize.width == SettingsPane.windowMinWidth)
        #expect(window.minSize.height >= SettingsPane.windowMinHeight)
    }

    @Test
    func settings_window_sizing_does_not_mutate_content_split_views() {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 160, width: 180, height: 140),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        let splitView = NSSplitView(
            frame: NSRect(x: 0, y: 0, width: SettingsPane.windowWidth, height: SettingsPane.windowHeight))
        splitView.isVertical = true
        let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: SettingsPane.windowHeight))
        let detail = NSView(
            frame: NSRect(x: 0, y: 0, width: SettingsPane.windowWidth, height: SettingsPane.windowHeight))
        splitView.addSubview(sidebar)
        splitView.addSubview(detail)
        window.contentView = splitView

        SettingsWindowSizing.enforceMinimumSize(window)

        #expect(window.frame.width >= window.minSize.width)
        #expect(sidebar.frame.width == 0)
    }

    @Test
    func bridge_pulses_exact_effective_appearance_then_restores_inheritance() {
        let application = NSApplication.shared
        let effectiveAppearance = application.effectiveAppearance
        let staleSource = NSView()
        staleSource.appearance = NSAppearance(named: .aqua)
        let resetCapture = ResetCapture()
        let bridge = SettingsWindowAppearanceView { resetCapture.actions.append($0) }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.appearanceSource = staleSource
        window.contentView = bridge

        let pulseMatchesEffectiveAppearance = window.appearance === effectiveAppearance
        let sourceIsApplication = (window.appearanceSource as AnyObject?) === application
        #expect(pulseMatchesEffectiveAppearance)
        #expect(sourceIsApplication)
        #expect(resetCapture.actions.count == 1)

        resetCapture.actions[0]()

        #expect(window.appearance == nil)
        #expect(window.viewsNeedDisplay)
    }

    @Test
    func bridge_updates_window_title_without_pulsing_appearance_on_pane_changes() {
        let resetCapture = ResetCapture()
        let bridge = SettingsWindowAppearanceView { resetCapture.actions.append($0) }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        window.contentView = bridge
        resetCapture.actions.removeAll()

        bridge.refreshWindowAppearance(for: .light, windowTitle: "Display")
        #expect(resetCapture.actions.count == 1)

        bridge.refreshWindowAppearance(for: .light, windowTitle: "General")

        #expect(window.title == "General")
        #expect(resetCapture.actions.count == 1)
    }

    @Test
    func settings_window_style_remains_resizable() {
        let bridge = SettingsWindowAppearanceView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)

        window.contentView = bridge

        #expect(window.styleMask.contains(.resizable))
    }

    @Test
    func settings_window_extends_content_behind_the_titlebar_for_the_edge_to_edge_sidebar() {
        let bridge = SettingsWindowAppearanceView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)

        window.contentView = bridge

        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.titlebarAppearsTransparent)
    }

    @Test
    func repeated_theme_updates_cannot_leave_an_explicit_appearance() {
        let resetCapture = ResetCapture()
        let bridge = SettingsWindowAppearanceView { resetCapture.actions.append($0) }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        window.contentView = bridge

        bridge.refreshWindowAppearance(for: .light)
        bridge.refreshWindowAppearance(for: .light)
        bridge.refreshWindowAppearance(for: .dark)
        #expect(resetCapture.actions.count == 3)
        for action in resetCapture.actions {
            action()
        }

        let sourceIsApplication = (window.appearanceSource as AnyObject?) === NSApplication.shared
        #expect(window.appearance == nil)
        #expect(sourceIsApplication)
    }
}

@MainActor
private final class ResetCapture {
    var actions: [SettingsWindowAppearance.ResetAction] = []
}
