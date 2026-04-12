import Foundation
@testable import ProcessProgress
import Testing

@Suite("Command runner")
struct CommandRunnerTests {
    @Test("collects stdout stderr exit code and final partial line")
    func collectsOutputAndExitCode() throws {
        let runner = CommandRunner(outputWriter: CommandOutputWriter { _, _ in })
        let streams = LockIsolated<[CommandOutputStream]>([])

        let output = try runner.run("printf 'out\\npartial'; printf 'err\\n' >&2; exit 7") { chunk in
            streams.withLock { $0.append(chunk.stream) }
        }
        let observedStreams = streams.withLock { $0 }

        #expect(output.exitCode == 7)
        #expect(output.lineRecords.contains { $0.textHash == LineHash.hash("out") })
        #expect(output.lineRecords.contains { $0.textHash == LineHash.hash("partial") })
        #expect(output.lineRecords.contains { $0.textHash == LineHash.hash("err") })
        #expect(observedStreams.contains(.standardOutput))
        #expect(observedStreams.contains(.standardError))
    }

    @Test("handles many output lines without writing through the standard writer", .timeLimit(.minutes(1)))
    func handlesManyOutputLines() throws {
        let lineCount = 50_000
        let runner = CommandRunner(outputWriter: CommandOutputWriter { _, _ in })

        let output = try runner.run("i=1; while [ \"$i\" -le \(lineCount) ]; do printf 'line %s\\n' \"$i\"; i=$((i + 1)); done") { _ in }

        #expect(output.exitCode == 0)
        #expect(output.lineRecords.count == lineCount)
    }

    @Test("drains large stdout and stderr streams without blocking", .timeLimit(.minutes(1)))
    func drainsLargeStdoutAndStderrStreams() throws {
        let lineCount = 20_000
        let runner = CommandRunner(outputWriter: CommandOutputWriter { _, _ in })
        let streamCounts = LockIsolated<[CommandOutputStream: Int]>([:])

        let command = """
        i=1; while [ "$i" -le \(lineCount) ]; do \
        printf 'stdout %s\\n' "$i"; \
        printf 'stderr %s\\n' "$i" >&2; \
        i=$((i + 1)); \
        done
        """
        let output = try runner.run(command) { chunk in
            streamCounts.withLock {
                $0[chunk.stream, default: 0] += chunk.lineRecords.count
            }
        }
        let observedCounts = streamCounts.withLock { $0 }

        #expect(output.exitCode == 0)
        #expect(output.lineRecords.count == lineCount * 2)
        #expect(observedCounts[.standardOutput] == lineCount)
        #expect(observedCounts[.standardError] == lineCount)
    }
}
