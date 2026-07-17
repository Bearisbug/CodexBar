import AppKit
import Testing
@testable import CodexBar

@MainActor
struct ClickToCopyOverlayTests {
    @Test
    func view_stores_the_latest_copyText() {
        let view = ClickToCopyView(copyText: "original")
        #expect(view.copyText == "original")
        view.copyText = "updated"
        #expect(view.copyText == "updated")
    }

    @Test
    func pasteboard_copy_waits_for_deferred_scheduler() {
        var pendingAction: (() -> Void)?
        var copiedText: String?
        var completed = false

        MenuPasteboardCopy.perform(
            "copy me",
            scheduler: { pendingAction = $0 },
            writer: { copiedText = $0 },
            completion: { completed = true })

        #expect(copiedText == nil)
        #expect(!completed)
        pendingAction?()
        #expect(copiedText == "copy me")
        #expect(completed)
    }

    @Test
    func mouseDown_forwards_the_latest_copyText() {
        var copiedText: String?
        let view = ClickToCopyView(copyText: "original") { copiedText = $0 }
        view.copyText = "updated"

        view.mouseDown(with: NSEvent())

        #expect(copiedText == "updated")
    }

    @Test
    func accepts_first_mouse_so_error_text_overlay_is_clickable_on_first_focus() {
        let view = ClickToCopyView(copyText: "x")
        #expect(view.acceptsFirstMouse(for: nil) == true)
    }
}
