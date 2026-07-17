import AppKit
import CoreGraphics
import Testing
@testable import CodexBar

@MainActor
struct ProviderSwitcherEventPeekGateTests {
    @Test
    func first_check_always_peeks() {
        let gate = ProviderSwitcherEventPeekGate(eventTypes: [.keyDown], counterProvider: { _ in 7 })
        #expect(gate.shouldPeek())
    }

    @Test
    func unchanged_counters_skip_the_peek() {
        let gate = ProviderSwitcherEventPeekGate(eventTypes: [.keyDown, .leftMouseDown], counterProvider: { _ in 7 })
        #expect(gate.shouldPeek())
        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(gate.shouldPeek())
        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(!gate.shouldPeek())
        #expect(!gate.shouldPeek())
    }

    @Test
    func any_advanced_counter_re_enables_the_peek() {
        var keyDownCount: UInt32 = 1
        let gate = ProviderSwitcherEventPeekGate(
            eventTypes: [.keyDown, .leftMouseDown],
            counterProvider: { type in type == .keyDown ? keyDownCount : 3 })
        #expect(gate.shouldPeek())
        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(gate.shouldPeek())
        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(!gate.shouldPeek())
        keyDownCount += 1
        #expect(gate.shouldPeek())
        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(gate.shouldPeek())
        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(!gate.shouldPeek())
    }

    @Test
    func counter_change_keeps_one_follow_up_peek_for_AppKit_queue_delivery() {
        var keyDownCount: UInt32 = 1
        let gate = ProviderSwitcherEventPeekGate(
            eventTypes: [.keyDown],
            counterProvider: { _ in keyDownCount })
        #expect(gate.shouldPeek())
        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(gate.shouldPeek())
        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(!gate.shouldPeek())

        keyDownCount += 1
        #expect(gate.shouldPeek())
        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(gate.shouldPeek())
        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(!gate.shouldPeek())
    }

    @Test
    func queued_unhandled_event_burst_keeps_peeking_until_the_queue_is_empty() throws {
        var eventCount: UInt32 = 1
        let gate = ProviderSwitcherEventPeekGate(
            eventTypes: [.keyUp],
            counterProvider: { _ in eventCount })
        #expect(gate.shouldPeek())
        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(gate.shouldPeek())
        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(!gate.shouldPeek())

        eventCount += 3
        #expect(gate.shouldPeek())
        try gate.observe(Self.keyEvent(type: .keyUp, keyCode: 124))
        #expect(gate.shouldPeek())
        try gate.observe(Self.keyEvent(type: .keyUp, keyCode: 124))
        #expect(gate.shouldPeek())
        try gate.observe(Self.keyEvent(type: .keyUp, keyCode: 124))
        #expect(gate.shouldPeek())

        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(gate.shouldPeek())
        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(!gate.shouldPeek())
    }

    @Test
    func handled_event_keeps_peeking_for_delayed_sibling_from_same_counter_snapshot() throws {
        var eventCount: UInt32 = 1
        let gate = ProviderSwitcherEventPeekGate(
            eventTypes: [.keyUp],
            counterProvider: { _ in eventCount })
        #expect(gate.shouldPeek())
        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(gate.shouldPeek())
        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(!gate.shouldPeek())

        eventCount += 2
        #expect(gate.shouldPeek())
        try gate.observe(Self.keyEvent(type: .keyUp, keyCode: 124))
        gate.observeQueueEmpty(afterFindingEvent: true)

        #expect(gate.shouldPeek())
        try gate.observe(Self.keyEvent(type: .keyUp, keyCode: 124))
        gate.observeQueueEmpty(afterFindingEvent: true)

        #expect(gate.shouldPeek())
        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(!gate.shouldPeek())
    }

    @Test
    func held_key_keeps_peeking_for_uncounted_autorepeat_events() throws {
        let gate = ProviderSwitcherEventPeekGate(eventTypes: [.keyDown, .keyUp], counterProvider: { _ in 7 })
        #expect(gate.shouldPeek())
        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(gate.shouldPeek())
        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(!gate.shouldPeek())

        try gate.observe(Self.keyEvent(type: .keyDown, keyCode: 124))
        #expect(gate.shouldPeek())
        #expect(gate.shouldPeek())

        try gate.observe(Self.keyEvent(type: .keyUp, keyCode: 124))
        #expect(gate.shouldPeek())
        gate.observeQueueEmpty(afterFindingEvent: false)
        #expect(!gate.shouldPeek())
    }

    private static func keyEvent(type: NSEvent.EventType, keyCode: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode))
    }
}
