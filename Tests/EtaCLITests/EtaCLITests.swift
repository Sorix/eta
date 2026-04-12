import Foundation
import ArgumentParser
@testable import EtaCLI
@testable import ProcessProgress
import Testing

private enum FakeError: Error {
    case saveFailed
}

private func makeLine(_ text: String, offset: Double = 0) -> LineRecord {
    LineRecord(
        textHash: LineHash.hash(text),
        normalizedHash: LineHash.normalizedHash(text),
        offsetSeconds: offset
    )
}

private func makeHistory() -> CommandHistory {
    CommandHistory(runs: [
        CommandRun(date: Date(timeIntervalSince1970: 1), totalDuration: 10, lineRecords: [
            makeLine("Configure", offset: 1),
            makeLine("Compile", offset: 5),
            makeLine("Done", offset: 10),
        ])
    ])
}

private final class WarningBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.withLock {
            values.append(value)
        }
    }

    var all: [String] {
        lock.withLock { values }
    }
}

private final class FakeHistoryStore: HistoryStoring, @unchecked Sendable {
    var loadedHistory: CommandHistory?
    var saveError: Error?
    var loadCommands: [String] = []
    var saved: [(history: CommandHistory, command: String, maximumRunCount: Int, staleAfterDays: Int)] = []
    var clearedCommands: [String] = []
    var clearAllCount = 0

    func load(for command: String) throws -> CommandHistory? {
        loadCommands.append(command)
        return loadedHistory
    }

    func save(
        _ history: CommandHistory,
        for command: String,
        maximumRunCount: Int,
        staleAfterDays: Int
    ) throws {
        if let saveError {
            throw saveError
        }
        saved.append((history, command, maximumRunCount, staleAfterDays))
    }

    func clear(for command: String) throws {
        clearedCommands.append(command)
    }

    func clearAll() throws {
        clearAllCount += 1
    }
}

private final class FakeCommandRunner: CommandRunning, @unchecked Sendable {
    var output = CommandOutput(lineRecords: [], totalDuration: 1, exitCode: 0)
    var runCommands: [String] = []
    var receivedOutputHandler = false
    var chunks: [CommandOutputChunk] = []

    func run(_ command: String, outputHandler: CommandOutputHandler?) throws -> CommandOutput {
        runCommands.append(command)
        receivedOutputHandler = outputHandler != nil
        for chunk in chunks {
            outputHandler?(chunk)
        }
        return output
    }
}

private final class FakeRenderer: ProgressRendering, @unchecked Sendable {
    var isEnabled: Bool
    var events: [String] = []

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    func update(progress: ProgressFill, remainingTime: Double) {
        events.append("update")
    }

    func forceUpdate(progress: ProgressFill, remainingTime: Double) {
        events.append("forceUpdate")
    }

    func writeOutputAndRedraw(
        rawOutput: Data,
        stream: CommandOutputStream,
        progress: ProgressFill,
        remainingTime: Double,
        containsPartialLine: Bool
    ) {
        events.append("writeOutputAndRedraw")
    }

    func cleanup() {
        events.append("cleanup")
    }

    func finish(elapsed: Double, expectedDuration: Double) {
        events.append("finish")
    }
}

private final class FakeRenderLoop: ProgressRenderLooping, @unchecked Sendable {
    var cancelCount = 0

    func cancel() {
        cancelCount += 1
    }
}

private final class FakeSignalTrap: SignalTrapping, @unchecked Sendable {
    var cancelCount = 0
    var cleanup: (@Sendable () -> Void)?

    func cancel() {
        cancelCount += 1
    }
}

private final class CoordinatorHarness: @unchecked Sendable {
    let historyStore = FakeHistoryStore()
    let commandRunner = FakeCommandRunner()
    let renderer = FakeRenderer()
    let renderLoop = FakeRenderLoop()
    let signalTrap = FakeSignalTrap()
    let warnings = WarningBox()
    var capturedColor: BarColor?
    var capturedStyle: ProgressBarStyle?
    var renderLoopCreateCount = 0
    var signalTrapCreateCount = 0

    var coordinator: CommandRunCoordinator {
        CommandRunCoordinator(
            historyStore: historyStore,
            commandRunner: commandRunner,
            rendererFactory: { [self] color, style in
                self.capturedColor = color
                self.capturedStyle = style
                return self.renderer
            },
            renderLoopFactory: { [self] _ in
                self.renderLoopCreateCount += 1
                return self.renderLoop
            },
            signalTrapFactory: { [self] cleanup in
                self.signalTrapCreateCount += 1
                self.signalTrap.cleanup = cleanup
                return self.signalTrap
            },
            dateProvider: { Date(timeIntervalSince1970: 100) },
            writeWarning: { [self] in self.warnings.append($0) }
        )
    }

    func request(
        command: String = "swift build",
        commandKey: String = "alias",
        maximumRunCount: Int = 7,
        quiet: Bool = false,
        color: BarColor = .cyan,
        progressBarStyle: ProgressBarStyle = .layered
    ) -> CommandRunRequest {
        CommandRunRequest(
            command: command,
            commandKey: commandKey,
            maximumRunCount: maximumRunCount,
            quiet: quiet,
            color: color,
            progressBarStyle: progressBarStyle
        )
    }
}

@Suite("Command run coordinator")
struct CommandRunCoordinatorTests {
    @Test("successful command saves history with request settings")
    func successfulCommandSavesHistory() throws {
        let harness = CoordinatorHarness()
        harness.commandRunner.output = CommandOutput(
            lineRecords: [makeLine("Done", offset: 1)],
            totalDuration: 1,
            exitCode: 0
        )

        try harness.coordinator.run(harness.request(maximumRunCount: 3, color: .magenta, progressBarStyle: .solid))

        let saved = try #require(harness.historyStore.saved.first)
        #expect(harness.historyStore.loadCommands == ["alias"])
        #expect(saved.command == "alias")
        #expect(saved.maximumRunCount == 3)
        #expect(saved.history.runs.count == 1)
        #expect(saved.history.runs.first?.lineRecords.count == 1)
        #expect(harness.capturedColor == .magenta)
        #expect(harness.capturedStyle == .solid)
    }

    @Test("non-zero command exits without saving history")
    func nonZeroCommandDoesNotSaveHistory() {
        let harness = CoordinatorHarness()
        harness.commandRunner.output = CommandOutput(lineRecords: [makeLine("failed")], totalDuration: 1, exitCode: 42)
        var didThrow = false

        do {
            try harness.coordinator.run(harness.request())
        } catch {
            didThrow = true
        }

        #expect(didThrow)
        #expect(harness.historyStore.saved.isEmpty)
    }

    @Test("quiet mode bypasses rendering and still records history")
    func quietModeBypassesRendering() throws {
        let harness = CoordinatorHarness()
        harness.historyStore.loadedHistory = makeHistory()
        harness.commandRunner.output = CommandOutput(lineRecords: [makeLine("Done")], totalDuration: 1, exitCode: 0)

        try harness.coordinator.run(harness.request(quiet: true))

        #expect(!harness.commandRunner.receivedOutputHandler)
        #expect(harness.renderer.events.isEmpty)
        #expect(harness.renderLoopCreateCount == 0)
        #expect(harness.signalTrapCreateCount == 0)
        #expect(harness.historyStore.saved.count == 1)
    }

    @Test("no history skips progress rendering")
    func noHistorySkipsProgressRendering() throws {
        let harness = CoordinatorHarness()
        harness.commandRunner.output = CommandOutput(lineRecords: [makeLine("Done")], totalDuration: 1, exitCode: 0)

        try harness.coordinator.run(harness.request())

        #expect(!harness.commandRunner.receivedOutputHandler)
        #expect(harness.renderer.events.isEmpty)
        #expect(harness.renderLoopCreateCount == 0)
        #expect(harness.signalTrapCreateCount == 0)
    }

    @Test("existing history enables render loop and rendering lifecycle")
    func existingHistoryEnablesRenderLoop() throws {
        let harness = CoordinatorHarness()
        harness.historyStore.loadedHistory = makeHistory()
        harness.commandRunner.chunks = [
            CommandOutputChunk(
                rawOutput: Data("Compile\n".utf8),
                lineRecords: [makeLine("Compile", offset: 1)],
                stream: .standardOutput,
                containsPartialLine: false
            )
        ]
        harness.commandRunner.output = CommandOutput(lineRecords: [makeLine("Compile", offset: 1)], totalDuration: 1, exitCode: 0)

        try harness.coordinator.run(harness.request())

        #expect(harness.commandRunner.receivedOutputHandler)
        #expect(harness.renderLoopCreateCount == 1)
        #expect(harness.signalTrapCreateCount == 1)
        #expect(harness.renderLoop.cancelCount == 1)
        #expect(harness.signalTrap.cancelCount == 1)
        #expect(harness.renderer.events == ["forceUpdate", "writeOutputAndRedraw", "finish"])
    }

    @Test("save failure writes warning without failing successful command")
    func saveFailureWritesWarning() throws {
        let harness = CoordinatorHarness()
        harness.historyStore.saveError = FakeError.saveFailed
        harness.commandRunner.output = CommandOutput(lineRecords: [makeLine("Done")], totalDuration: 1, exitCode: 0)

        try harness.coordinator.run(harness.request())

        #expect(harness.warnings.all.count == 1)
        #expect(harness.warnings.all.first?.contains("failed to save history") == true)
    }
}

@Suite("ETA validation and clear modes")
struct ETAValidationTests {
    @Test("command clear and clear-all modes are mutually exclusive")
    func modesAreMutuallyExclusive() {
        var didThrow = false
        do {
            _ = try ETA.parse(["--clear", "echo hi", "echo hi"])
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }

    @Test("runs must be positive")
    func runsMustBePositive() {
        var didThrow = false
        do {
            _ = try ETA.parse(["--runs", "0", "echo hi"])
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

        #expect(store.clearedCommands == ["swift build"])
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
}
