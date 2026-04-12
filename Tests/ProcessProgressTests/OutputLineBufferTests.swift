import Foundation
@testable import ProcessProgress
import Testing

@Suite("Output line buffering")
struct OutputLineBufferTests {
    @Test("buffers split chunks and flushes final unterminated line")
    func buffersSplitChunksAndFlushesFinalLine() throws {
        var buffer = OutputLineBuffer()

        let first = buffer.append(Data("hel".utf8), offsetSeconds: 0.1)
        #expect(first.lineRecords.isEmpty)
        #expect(first.containsPartialLine)

        let second = buffer.append(Data("lo\nwor".utf8), offsetSeconds: 0.2)
        #expect(second.lineRecords.map(\.textHash) == [LineHash.hash("hello")])
        #expect(second.containsPartialLine)

        let final = buffer.flushFinalLine(offsetSeconds: 0.3)
        #expect(final.map(\.textHash) == [LineHash.hash("wor")])
    }

    @Test("ignores blank lines and strips CRLF carriage returns")
    func ignoresBlankLinesAndStripsCRLF() {
        var buffer = OutputLineBuffer()

        let update = buffer.append(Data("\n\r\nvalue\r\n".utf8), offsetSeconds: 1)

        #expect(update.lineRecords.count == 1)
        #expect(update.lineRecords.first?.textHash == LineHash.hash("value"))
        #expect(!update.containsPartialLine)
    }

    @Test("ignores invalid UTF-8 lines")
    func ignoresInvalidUTF8Lines() {
        var buffer = OutputLineBuffer()

        let update = buffer.append(Data([0xFF, 0x0A]), offsetSeconds: 1)

        #expect(update.lineRecords.isEmpty)
        #expect(!update.containsPartialLine)
    }
}
