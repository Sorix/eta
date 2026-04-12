import ArgumentParser
import Foundation
@testable import EtaCLI
@testable import ProcessProgress
import Testing

struct InvalidArgumentsCase: Sendable {
    let arguments: [String]
}

@Suite("ETA validation and clear modes")
struct ETAValidationTests {
    @Test("invalid mode combinations and run counts throw", arguments: [
        InvalidArgumentsCase(arguments: []),
        InvalidArgumentsCase(arguments: ["--clear", "echo hi", "echo hi"]),
        InvalidArgumentsCase(arguments: ["--clear-all", "echo hi"]),
        InvalidArgumentsCase(arguments: ["--clear", "one", "--clear-all"]),
        InvalidArgumentsCase(arguments: ["--runs", "0", "echo hi"]),
        InvalidArgumentsCase(arguments: ["--runs", "-1", "echo hi"]),
    ])
    func invalidArgumentsThrow(_ testCase: InvalidArgumentsCase) {
        var didThrow = false

        do {
            _ = try ETA.parse(testCase.arguments)
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }

    @Test("valid clear mode calls history clear")
    func validClearModeCallsHistoryClear() throws {
        let store = FakeHistoryStore()
        let eta = try ETA.parse(["--clear", "swift build"])

        try eta.run(historyStore: store, commandKeyResolver: FakeCommandKeyResolver())

        #expect(store.clearedCommands == ["resolved:swift build"])
        #expect(store.clearAllCount == 0)
    }

    @Test("valid clear-all mode calls history clearAll")
    func validClearAllModeCallsHistoryClearAll() throws {
        let store = FakeHistoryStore()
        let eta = try ETA.parse(["--clear-all"])

        try eta.run(historyStore: store)

        #expect(store.clearedCommands.isEmpty)
        #expect(store.clearAllCount == 1)
    }

    @Test("ETA_CACHE_DIR selects explicit history directory")
    func etaCacheDirSelectsExplicitHistoryDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("eta-cli-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ETA.makeHistoryStore(environment: ["ETA_CACHE_DIR": directory.path])
        try store.save(CommandHistory(runs: [
            CommandRun(date: Date(), totalDuration: 1, lineRecords: [makeLine("Done")])
        ]), for: "command")

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files.count == 1)
    }

    private struct FakeCommandKeyResolver: CommandKeyResolving {
        func resolvedKey(for command: String) -> String {
            "resolved:\(command)"
        }
    }
}
