import Foundation
@testable import ProcessProgress
import Testing

private func makeLine(_ text: String, offset: Double = 0) -> LineRecord {
    LineRecord(
        textHash: LineHash.hash(text),
        normalizedHash: LineHash.normalizedHash(text),
        offsetSeconds: offset
    )
}

private func makeTemporaryDirectory(_ name: String = #function) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("eta-process-tests-\(UUID().uuidString)-\(name)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@Suite("Line normalization and hashing")
struct LineNormalizationAndHashingTests {
    @Test("normalizes digit and whitespace runs")
    func normalizesDigitAndWhitespaceRuns() {
        #expect(LineNormalizer.normalized("[3/100]   Compiling  Foo.swift") == "[N/N] Compiling Foo.swift")
        #expect(LineNormalizer.normalized("  Step  5  of  20  ") == "Step N of N")
        #expect(LineNormalizer.normalized("Downloaded\t128\nMB") == "Downloaded N MB")
    }

    @Test("line hashes are deterministic fixed-width hex and do not retain raw text")
    func lineHashesAreDeterministic() {
        let text = "secret build output 123"
        let hash = LineHash.hash(text)
        let normalizedHash = LineHash.normalizedHash(text)

        #expect(hash == LineHash.hash(text))
        #expect(normalizedHash == LineHash.normalizedHash(text))
        #expect(hash.count == 32)
        #expect(normalizedHash.count == 32)
        #expect(hash != text)
        #expect(normalizedHash != text)
        #expect(hash.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("command fingerprints are deterministic SHA-256 hex")
    func commandFingerprintsAreDeterministic() {
        let command = "swift build 2>&1 | xcbeautify --is-ci"
        let fingerprint = CommandFingerprint.hash(command)

        #expect(fingerprint == CommandFingerprint.hash(command))
        #expect(fingerprint.count == 64)
        #expect(fingerprint != command)
        #expect(fingerprint.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }
}

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
}

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

@Suite("Line matching")
struct LineMatcherTests {
    @Test("matches exact hashes first and then normalized fallback")
    func matchesExactThenNormalized() {
        let lines = [
            makeLine("[1/3] Compiling Foo.swift", offset: 1),
            makeLine("[2/3] Compiling Bar.swift", offset: 2),
            makeLine("[3/3] Linking", offset: 3),
        ]
        let matcher = LineMatcher(runs: [
            CommandRun(date: Date(), totalDuration: 3, lineRecords: lines)
        ])

        #expect(matcher.match(text: "[2/3] Compiling Bar.swift") == 1)
        #expect(matcher.match(text: "[9/99] Compiling Bar.swift") == 1)
    }

    @Test("repeated lines only match later reference indices")
    func repeatedLinesMatchAfterPreviousIndex() {
        let lines = [
            makeLine("Compiling Shared.swift", offset: 1),
            makeLine("Compiling Shared.swift", offset: 2),
            makeLine("Done", offset: 3),
        ]
        let matcher = LineMatcher(runs: [
            CommandRun(date: Date(), totalDuration: 3, lineRecords: lines)
        ])

        let first = matcher.match(text: "Compiling Shared.swift")
        let second = matcher.match(text: "Compiling Shared.swift", after: first ?? -1)

        #expect(first == 0)
        #expect(second == 1)
        #expect(matcher.match(text: "Compiling Shared.swift", after: 1) == nil)
    }
}

@Suite("Timeline progress estimator")
struct TimelineProgressEstimatorTests {
    @Test("returns empty estimate without history")
    func returnsEmptyEstimateWithoutHistory() {
        let estimator = TimelineProgressEstimator(history: nil)
        let estimate = estimator.estimate(elapsed: 10)

        #expect(!estimator.hasHistory)
        #expect(estimator.expectedTotalDuration == 0)
        #expect(estimate.progress == ProgressFill(confirmed: 0, predicted: 0))
        #expect(estimate.remainingTime == 0)
    }

    @Test("weights recent runs more heavily")
    func weightsRecentRunsMoreHeavily() {
        let oldRun = CommandRun(date: Date(), totalDuration: 100, lineRecords: [makeLine("old", offset: 100)])
        let newRun = CommandRun(date: Date(), totalDuration: 10, lineRecords: [makeLine("new", offset: 10)])
        let estimator = TimelineProgressEstimator(runs: [oldRun, newRun])

        let expected = (10.0 + 100.0 * 0.7) / 1.7
        #expect(abs(estimator.expectedTotalDuration - expected) < 0.000_001)
    }

    @Test("advances confirmed progress from matched lines and clamps prediction")
    func advancesConfirmedProgressAndClampsPrediction() {
        let referenceLines = [
            makeLine("Configure", offset: 2),
            makeLine("Compile", offset: 5),
            makeLine("Done", offset: 10),
        ]
        let estimator = TimelineProgressEstimator(runs: [
            CommandRun(date: Date(), totalDuration: 10, lineRecords: referenceLines)
        ])

        let compileEstimate = estimator.observeCurrentLine(makeLine("Compile", offset: 1), elapsed: 1)
        #expect(compileEstimate.progress.confirmed == 0.5)
        #expect(compileEstimate.progress.predicted >= compileEstimate.progress.confirmed)

        let laterEstimate = estimator.estimate(elapsed: 100)
        #expect(laterEstimate.progress.predicted == 1)

        estimator.resetCurrentLog()
        let resetEstimate = estimator.estimate(elapsed: 0)
        #expect(resetEstimate.progress.confirmed == 0)
    }

    @Test("append-only current log cache resets when a shorter log is supplied")
    func currentLogCacheResetsForShorterLog() {
        let referenceLines = [
            makeLine("Step 1", offset: 1),
            makeLine("Step 2", offset: 2),
        ]
        let estimator = TimelineProgressEstimator(runs: [
            CommandRun(date: Date(), totalDuration: 2, lineRecords: referenceLines)
        ])

        _ = estimator.estimate(currentLog: referenceLines, elapsed: 2)
        let resetEstimate = estimator.estimate(currentLog: [referenceLines[0]], elapsed: 1)

        #expect(resetEstimate.progress.confirmed == 0.5)
    }
}

@Suite("History store")
struct HistoryStoreTests {
    @Test("saves loads and prunes newest runs")
    func savesLoadsAndPrunesNewestRuns() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directory: directory)
        let runs = (0..<5).map { index in
            CommandRun(date: Date(timeIntervalSince1970: Double(index)), totalDuration: Double(index), lineRecords: [
                makeLine("line \(index)", offset: Double(index))
            ])
        }

        try store.save(CommandHistory(runs: runs), for: "command", maximumRunCount: 2)
        let loaded = try #require(try store.load(for: "command"))

        #expect(loaded.runs.count == 2)
        #expect(loaded.runs.map(\.totalDuration) == [3, 4])
    }

    @Test("throws for invalid maximum run count")
    func throwsForInvalidMaximumRunCount() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directory: directory)
        var didThrow = false

        do {
            try store.save(CommandHistory(), for: "command", maximumRunCount: 0)
        } catch HistoryStoreError.invalidMaximumRunCount(0) {
            didThrow = true
        }

        #expect(didThrow)
    }

    @Test("prunes stale JSON files after save")
    func prunesStaleJSONFilesAfterSave() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let stale = directory.appendingPathComponent("stale.json")
        try Data("{}".utf8).write(to: stale)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3 * 86_400)],
            ofItemAtPath: stale.path
        )

        let store = HistoryStore(directory: directory)
        try store.save(CommandHistory(runs: [
            CommandRun(date: Date(), totalDuration: 1, lineRecords: [makeLine("line")])
        ]), for: "command", maximumRunCount: 10, staleAfterDays: 1)

        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }

    @Test("downsamples to maximum lines and preserves first and last")
    func downsamplesToMaximumLinesAndPreservesEnds() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let lineCount = HistoryStore.maxLinesPerRun + 1_234
        let lines = (0..<lineCount).map { makeLine("line \($0)", offset: Double($0)) }
        let store = HistoryStore(directory: directory)

        try store.save(CommandHistory(runs: [
            CommandRun(date: Date(), totalDuration: 1, lineRecords: lines)
        ]), for: "command")

        let loaded = try #require(try store.load(for: "command"))
        let savedLines = try #require(loaded.runs.first?.lineRecords)

        #expect(savedLines.count == HistoryStore.maxLinesPerRun)
        #expect(savedLines.first?.offsetSeconds == 0)
        #expect(savedLines.last?.offsetSeconds == Double(lineCount - 1))
    }
}
