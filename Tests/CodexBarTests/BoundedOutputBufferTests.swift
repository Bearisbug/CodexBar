import Foundation
import Testing
@testable import CodexBarCore

struct BoundedOutputBufferTests {
    @Test
    func output_buffer_rejects_data_beyond_its_byte_limit() {
        var buffer = BoundedOutputBuffer(maxBytes: 4)

        let accepted = buffer.append(Data("abcd".utf8))
        let rejected = buffer.append(Data("e".utf8))

        #expect(accepted)
        #expect(!rejected)
        #expect(buffer.data == Data("abcd".utf8))
    }

    @Test
    func line_buffer_rejects_an_unterminated_line_beyond_its_byte_limit() {
        let buffer = BoundedLineBuffer(maxBytes: 4)

        let first = buffer.appendAndDrainLines(Data("abcd".utf8))
        let overflow = buffer.appendAndDrainLines(Data("e".utf8))

        #expect(first.lines.isEmpty)
        #expect(!first.didExceedLimit)
        #expect(overflow.lines.isEmpty)
        #expect(overflow.didExceedLimit)
    }

    @Test
    func line_buffer_frees_completed_lines_before_accepting_more_output() {
        let buffer = BoundedLineBuffer(maxBytes: 4)

        let first = buffer.appendAndDrainLines(Data("a\n".utf8))
        let second = buffer.appendAndDrainLines(Data("bcde".utf8))

        #expect(first.lines == [Data("a".utf8)])
        #expect(!first.didExceedLimit)
        #expect(!second.didExceedLimit)
    }

    @Test
    func line_buffer_drains_a_completed_line_before_limiting_the_same_chunk_tail() {
        let buffer = BoundedLineBuffer(maxBytes: 4)

        let partial = buffer.appendAndDrainLines(Data("abc".utf8))
        let completed = buffer.appendAndDrainLines(Data("d\nxy".utf8))

        #expect(!partial.didExceedLimit)
        #expect(completed.lines == [Data("abcd".utf8)])
        #expect(!completed.didExceedLimit)
    }

    @Test
    func line_buffer_rejects_an_oversized_line_even_when_newline_arrives() {
        let buffer = BoundedLineBuffer(maxBytes: 4)

        _ = buffer.appendAndDrainLines(Data("abc".utf8))
        let overflow = buffer.appendAndDrainLines(Data("de\n".utf8))

        #expect(overflow.lines.isEmpty)
        #expect(overflow.didExceedLimit)
    }
}
