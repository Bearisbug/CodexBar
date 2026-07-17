import Foundation
import Testing
@testable import CodexBar

#if DEBUG
@Suite(.serialized)
struct MainThreadHangWatchdogTests {
    @MainActor
    @Test
    func breadcrumb_tracks_nested_activity() {
        #expect(MainThreadActivityBreadcrumb.current == nil)
        MainThreadActivityBreadcrumb.push("outer")
        MainThreadActivityBreadcrumb.push("inner")
        #expect(MainThreadActivityBreadcrumb.current == "inner")
        MainThreadActivityBreadcrumb.pop()
        #expect(MainThreadActivityBreadcrumb.current == "outer")
        MainThreadActivityBreadcrumb.pop()
        #expect(MainThreadActivityBreadcrumb.current == nil)
    }

    @Test
    func watchdog_reports_a_breadcrumb_for_a_delayed_main_thread_response() throws {
        let watchdog = MainThreadHangWatchdog(
            pingInterval: 0.01,
            hangThreshold: 0.05,
            sampleThreshold: 60,
            sampleCooldown: 3600)

        let reported = OSAllocatedBox<[(TimeInterval, [String])]>([])
        watchdog.onHangForTesting = { duration, activities in
            reported.append((duration, activities))
        }

        MainThreadActivityBreadcrumb.push("testStall")
        watchdog.traceHangForTesting(responseDelay: 0.25)
        MainThreadActivityBreadcrumb.pop()

        let report = try #require(reported.get().first)
        #expect(report.1.contains("testStall"))
        #expect(report.0 >= 0.05)
    }

    @Test
    func watchdog_polling_loop_reports_a_delayed_ping_response() {
        let pingScheduled = DispatchSemaphore(value: 0)
        let hangDetected = DispatchSemaphore(value: 0)
        let reported = DispatchSemaphore(value: 0)
        let pendingResponse = OSAllocatedBox<(@Sendable () -> Void)?>(nil)
        let watchdog = MainThreadHangWatchdog(
            pingInterval: 1,
            hangThreshold: 0.02,
            sampleThreshold: 60,
            sampleCooldown: 3600,
            schedulePing: { response in
                pendingResponse.set(response)
                pingScheduled.signal()
            })
        watchdog.onHangForTesting = { _, _ in
            reported.signal()
        }
        watchdog.onHangDetectionForTesting = {
            hangDetected.signal()
        }

        watchdog.start()
        defer { watchdog.stop() }

        #expect(pingScheduled.wait(timeout: .now() + 10) == .success)
        #expect(hangDetected.wait(timeout: .now() + 10) == .success)
        pendingResponse.get()?()
        #expect(reported.wait(timeout: .now() + 10) == .success)
    }

    @Test
    func sample_capture_cannot_inflate_reported_hang_duration() throws {
        let sampleRequested = OSAllocatedBox(false)
        let watchdog = MainThreadHangWatchdog(
            pingInterval: 0.01,
            hangThreshold: 0.03,
            sampleThreshold: 0.05,
            sampleCooldown: 3600,
            sampleCaptureOverride: {
                sampleRequested.set(true)
                Thread.sleep(forTimeInterval: 1)
                return "/tmp/codexbar-watchdog-test-sample.txt"
            })

        let reported = OSAllocatedBox<[(TimeInterval, [String])]>([])
        watchdog.onHangForTesting = { duration, activities in
            reported.append((duration, activities))
        }

        MainThreadActivityBreadcrumb.push("sampledStall")
        watchdog.traceHangForTesting(responseDelay: 0.05, waitForSampleAttempt: true)
        MainThreadActivityBreadcrumb.pop()

        let report = try #require(reported.get().first)
        #expect(sampleRequested.get())
        #expect(report.1.contains("sampledStall"))
        #expect(report.0 >= 0.03)
        #expect(report.0 < 0.75)
    }

    @Test
    func failed_sample_capture_is_attempted_once_per_hang() {
        let attempts = OSAllocatedBox(0)
        let watchdog = MainThreadHangWatchdog(
            pingInterval: 0.01,
            hangThreshold: 0.01,
            sampleThreshold: 0,
            sampleCooldown: 3600,
            sampleCaptureOverride: {
                attempts.withValue { $0 += 1 }
                return nil
            })

        watchdog.traceHangForTesting(responseDelay: 0.05, waitForSampleAttempt: true)

        #expect(attempts.get() == 1)
    }

    @Test
    func missed_sample_window_does_not_consume_cooldown() {
        let attempts = OSAllocatedBox(0)
        let watchdog = MainThreadHangWatchdog(
            pingInterval: 0.01,
            hangThreshold: 0.01,
            sampleThreshold: 0.02,
            sampleCooldown: 3600,
            sampleCaptureOverride: {
                attempts.withValue { $0 += 1 }
                return nil
            })

        watchdog.traceHangForTesting(responseDelay: 0.05, responseBeforeTrace: true)
        #expect(attempts.get() == 0)

        watchdog.traceHangForTesting(responseDelay: 0.05, waitForSampleAttempt: true)
        #expect(attempts.get() == 1)
    }

    @Test
    func cooldown_blocked_hang_samples_when_cooldown_expires() {
        let attempts = OSAllocatedBox(0)
        let watchdog = MainThreadHangWatchdog(
            pingInterval: 0.01,
            hangThreshold: 0.01,
            sampleThreshold: 0,
            sampleCooldown: 0.2,
            sampleCaptureOverride: {
                attempts.withValue { $0 += 1 }
                return nil
            })

        watchdog.traceHangForTesting(responseDelay: 0.05, waitForSampleAttempt: true)
        watchdog.traceHangForTesting(responseDelay: 1)

        #expect(attempts.get() == 2)
    }
}
#endif

private final class OSAllocatedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    func set(_ newValue: T) {
        self.lock.lock()
        self.value = newValue
        self.lock.unlock()
    }

    func get() -> T {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.value
    }
}

extension OSAllocatedBox {
    func append<Element>(_ element: Element) where T == [Element] {
        self.lock.lock()
        self.value.append(element)
        self.lock.unlock()
    }

    func withValue(_ body: (inout T) -> Void) {
        self.lock.lock()
        body(&self.value)
        self.lock.unlock()
    }
}
