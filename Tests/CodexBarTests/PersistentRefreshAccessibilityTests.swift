import AppKit
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct PersistentRefreshAccessibilityTests {
    @Test
    func disabled_refresh_row_rejects_accessibility_press() {
        var pressCount = 0
        let view = PersistentRefreshMenuView(
            title: "Refresh",
            systemImageName: "arrow.clockwise",
            shortcutText: "⌘ R",
            onClick: { pressCount += 1 })

        #expect(view.isAccessibilityEnabled())
        #expect(view.accessibilityPerformPress())
        #expect(pressCount == 1)

        view.setEnabled(false)
        #expect(!view.isAccessibilityEnabled())
        #expect(!view.accessibilityPerformPress())
        #expect(pressCount == 1)

        view.setEnabled(true)
        #expect(view.isAccessibilityEnabled())
        #expect(view.accessibilityPerformPress())
        #expect(pressCount == 2)
    }
}
