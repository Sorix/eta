import Foundation
@testable import ProcessProgress
import Testing

@Suite("History store")
struct HistoryStoreTests {
    @Test("returns nil when history file is missing")
    func returnsNilWhenHistoryFileIsMissing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directory: directory)

        #expect(try store.load(for: "missing") == nil)
    }

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

    @Test("stored files contain hashed command keys and line records only")
    func storedFilesContainHashesOnly() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let command = "secret command"
        let rawOutput = "secret output"
        let store = HistoryStore(directory: directory)

        try store.save(CommandHistory(runs: [
            CommandRun(date: Date(), totalDuration: 1, lineRecords: [makeLine(rawOutput)])
        ]), for: command)

        let file = try #require(try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).first)
        let json = try String(contentsOf: file, encoding: .utf8)

        #expect(file.lastPathComponent == "\(CommandFingerprint.hash(command)).json")
        #expect(!file.lastPathComponent.contains(command))
        #expect(!json.contains(command))
        #expect(!json.contains(rawOutput))
        #expect(json.contains(LineHash.hash(rawOutput)))
    }

    @Test("clears one command history and then all history")
    func clearsOneCommandHistoryAndThenAllHistory() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directory: directory)
        let history = CommandHistory(runs: [
            CommandRun(date: Date(), totalDuration: 1, lineRecords: [makeLine("line")])
        ])

        try store.save(history, for: "one")
        try store.save(history, for: "two")
        try store.clear(for: "one")

        #expect(try store.load(for: "one") == nil)
        #expect(try store.load(for: "two") != nil)

        try store.clearAll()

        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
