import Foundation
import Testing
@testable import CodexBarCore

struct OpenAIDashboardOffscreenHostTests {
    @Test
    func offscreen_host_frame_only_intersects_by_A_sliver() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let frame = OpenAIDashboardFetcher.offscreenHostWindowFrame(for: visibleFrame)
        let intersection = frame.intersection(visibleFrame)

        #expect(frame.size.width == visibleFrame.size.width)
        #expect(frame.size.height == visibleFrame.size.height)
        #expect(intersection.size.width <= 1.0)
        #expect(intersection.size.height <= 1.0)
        #expect(intersection.minX >= visibleFrame.maxX - 1.0)
        #expect(intersection.minY >= visibleFrame.maxY - 1.0)
    }

    @Test
    func offscreen_host_alpha_value_is_non_zero_but_tiny() {
        let alpha = OpenAIDashboardFetcher.offscreenHostAlphaValue()
        #expect(alpha > 0)
        #expect(alpha <= 0.001)
    }
}
