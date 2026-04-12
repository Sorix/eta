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

        try eta.run(historyStore: store)

        #expect(store.clearedCommands == [ETA.resolvedCommandKey("swift build")])
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

    @Test("resolved command key includes absolute executable path")
    func resolvedCommandKeyResolvesExecutable() {
        let cwd = FileManager.default.currentDirectoryPath

        // A bare executable found on PATH: cwd + resolved path + args
        let resolved = ETA.resolvedCommandKey("ls -la /tmp")
        #expect(resolved.hasPrefix("\(cwd)\n/"))
        #expect(resolved.hasSuffix(" -la /tmp"))

        // A path-based executable: resolved to canonical path, no cwd
        let absolute = ETA.resolvedCommandKey("/usr/bin/env FOO=1")
        #expect(absolute == "/usr/bin/env FOO=1")

        // An unresolvable bare command: cwd + original string
        let unknown = ETA.resolvedCommandKey("no_such_command_xyz --flag")
        #expect(unknown == "\(cwd)\nno_such_command_xyz --flag")
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
}
