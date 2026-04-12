import Foundation
@testable import EtaCLI
@testable import ProcessProgress

enum FakeError: Error {
    case runFailed
    case saveFailed
}

func makeLine(_ text: String, offset: Double = 0) -> LineRecord {
    LineRecord(
        textHash: LineHash.hash(text),
        normalizedHash: LineHash.normalizedHash(text),
        offsetSeconds: offset
    )
}

func makeHistory() -> CommandHistory {
    CommandHistory(runs: [
        CommandRun(date: Date(timeIntervalSince1970: 1), totalDuration: 10, lineRecords: [
            makeLine("Configure", offset: 1),
            makeLine("Compile", offset: 5),
            makeLine("Done", offset: 10),
        ])
    ])
}

final class WarningBox: @unchecked Sendable {
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

final class FakeHistoryStore: HistoryStoring, @unchecked Sendable {
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

final class FakeCommandRunner: CommandRunning, @unchecked Sendable {
    var output = CommandOutput(lineRecords: [], totalDuration: 1, exitCode: 0)
    var error: Error?
    var runCommands: [String] = []
    var receivedOutputHandler = false
    var chunks: [CommandOutputChunk] = []

    func run(_ command: String, outputHandler: CommandOutputHandler?) throws -> CommandOutput {
        runCommands.append(command)
        receivedOutputHandler = outputHandler != nil
        if let error {
            throw error
        }
        for chunk in chunks {
            outputHandler?(chunk)
        }
        return output
    }
}

final class FakeRenderer: ProgressRendering, @unchecked Sendable {
    var isEnabled: Bool
    var events: [String] = []
    var remainingTimes: [Double?] = []
    var elapsedTimes: [Double] = []

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    func update(progress: ProgressFill, remainingTime: Double?, elapsedTime: Double) {
        events.append("update")
        remainingTimes.append(remainingTime)
        elapsedTimes.append(elapsedTime)
    }

    func forceUpdate(progress: ProgressFill, remainingTime: Double?, elapsedTime: Double) {
        events.append("forceUpdate")
        remainingTimes.append(remainingTime)
        elapsedTimes.append(elapsedTime)
    }

    func writeOutputAndRedraw(
        rawOutput: Data,
        stream: CommandOutputStream,
        progress: ProgressFill,
        remainingTime: Double?,
        elapsedTime: Double,
        containsPartialLine: Bool
    ) {
        events.append("writeOutputAndRedraw")
        remainingTimes.append(remainingTime)
        elapsedTimes.append(elapsedTime)
    }

    func cleanup() {
        events.append("cleanup")
    }

    func finish(elapsed: Double, expectedDuration: Double) {
        events.append("finish")
    }
}

final class FakeRenderLoop: ProgressRenderLooping, @unchecked Sendable {
    var cancelCount = 0

    func cancel() {
        cancelCount += 1
    }
}

final class FakeSignalTrap: SignalTrapping, @unchecked Sendable {
    var cancelCount = 0
    var cleanup: (@Sendable () -> Void)?

    func cancel() {
        cancelCount += 1
    }
}

final class CoordinatorHarness: @unchecked Sendable {
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
