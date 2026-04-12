import ArgumentParser
import Foundation
import ProcessProgress

typealias DateProvider = @Sendable () -> Date
typealias RendererFactory = @Sendable (BarColor, ProgressBarStyle) -> any ProgressRendering
typealias RenderLoopFactory = @Sendable (ProgressRenderLoopConfiguration) -> any ProgressRenderLooping
typealias SignalTrapFactory = @Sendable (@escaping @Sendable () -> Void) -> any SignalTrapping

struct ProgressRenderLoopConfiguration: Sendable {
    let renderer: any ProgressRendering
    let estimator: TimelineProgressEstimator
    let startTime: Date
    let dateProvider: DateProvider
}

protocol HistoryStoring {
    func load(for command: String) throws -> CommandHistory?
    func save(
        _ history: CommandHistory,
        for command: String,
        maximumRunCount: Int,
        staleAfterDays: Int
    ) throws
    func clear(for command: String) throws
    func clearAll() throws
}

extension HistoryStore: HistoryStoring {}

protocol CommandRunning {
    func run(_ command: String, outputHandler: CommandOutputHandler?) throws -> CommandOutput
}

extension CommandRunner: CommandRunning {}

protocol ProgressRendering: AnyObject, Sendable {
    var isEnabled: Bool { get }

    func update(progress: ProgressFill, remainingTime: Double)
    func forceUpdate(progress: ProgressFill, remainingTime: Double)
    func writeOutputAndRedraw(
        rawOutput: Data,
        stream: CommandOutputStream,
        progress: ProgressFill,
        remainingTime: Double,
        containsPartialLine: Bool
    )
    func cleanup()
    func finish(elapsed: Double, expectedDuration: Double)
}

protocol ProgressRenderLooping: Sendable {
    func cancel()
}

protocol SignalTrapping: Sendable {
    func cancel()
}

/// Options needed to run one wrapped command from the CLI.
struct CommandRunRequest: Sendable {
    let command: String
    let commandKey: String
    let maximumRunCount: Int
    let quiet: Bool
    let color: BarColor
    let progressBarStyle: ProgressBarStyle
}

/// Coordinates history, command execution, progress estimation, and terminal rendering.
struct CommandRunCoordinator {
    private let historyStore: any HistoryStoring
    private let commandRunner: any CommandRunning
    private let rendererFactory: RendererFactory
    private let renderLoopFactory: RenderLoopFactory
    private let signalTrapFactory: SignalTrapFactory
    private let dateProvider: DateProvider
    private let writeWarning: @Sendable (String) -> Void

    init(
        historyStore: any HistoryStoring,
        commandRunner: any CommandRunning = CommandRunner(),
        rendererFactory: @escaping RendererFactory = { color, style in
            ProgressRenderer(color: color, style: style)
        },
        renderLoopFactory: @escaping RenderLoopFactory = { configuration in
            ProgressRenderLoop(
                renderer: configuration.renderer,
                estimator: configuration.estimator,
                startTime: configuration.startTime,
                dateProvider: configuration.dateProvider
            )
        },
        signalTrapFactory: @escaping SignalTrapFactory = { cleanup in
            SignalTrap(cleanup: cleanup)
        },
        dateProvider: @escaping DateProvider = Date.init,
        writeWarning: @escaping @Sendable (String) -> Void
    ) {
        self.historyStore = historyStore
        self.commandRunner = commandRunner
        self.rendererFactory = rendererFactory
        self.renderLoopFactory = renderLoopFactory
        self.signalTrapFactory = signalTrapFactory
        self.dateProvider = dateProvider
        self.writeWarning = writeWarning
    }

    func run(_ request: CommandRunRequest) throws {
        let history = try historyStore.load(for: request.commandKey)
        let progressEstimator = TimelineProgressEstimator(history: history)
        let renderer = rendererFactory(request.color, request.progressBarStyle)
        let shouldRenderProgress = !request.quiet && renderer.isEnabled && progressEstimator.hasHistory
        let startTime = dateProvider()

        if shouldRenderProgress {
            let estimate = progressEstimator.estimate(elapsed: 0)
            renderer.forceUpdate(progress: estimate.progress, remainingTime: estimate.remainingTime)
        }

        let renderLoop = shouldRenderProgress ? renderLoopFactory(ProgressRenderLoopConfiguration(
            renderer: renderer,
            estimator: progressEstimator,
            startTime: startTime,
            dateProvider: dateProvider
        )) : nil
        let signalTrap = shouldRenderProgress
            ? signalTrapFactory { renderer.cleanup() }
            : nil

        var didEndRenderingLifecycle = false
        func endRenderingLifecycle(cleanupOnly: Bool) {
            guard !didEndRenderingLifecycle else { return }
            didEndRenderingLifecycle = true
            renderLoop?.cancel()
            signalTrap?.cancel()
            if cleanupOnly, shouldRenderProgress {
                renderer.cleanup()
            }
        }

        let output: CommandOutput
        do {
            output = try runCommand(
                request.command,
                renderingProgress: shouldRenderProgress,
                startTime: startTime,
                progressEstimator: progressEstimator,
                renderer: renderer
            )
        } catch {
            endRenderingLifecycle(cleanupOnly: true)
            throw error
        }

        endRenderingLifecycle(cleanupOnly: false)
        if shouldRenderProgress {
            renderer.finish(
                elapsed: output.totalDuration,
                expectedDuration: progressEstimator.expectedTotalDuration
            )
        }

        guard output.exitCode == 0 else {
            throw ExitCode(output.exitCode)
        }

        saveSuccessfulRun(output, history: history, request: request)
    }

    private func runCommand(
        _ command: String,
        renderingProgress: Bool,
        startTime: Date,
        progressEstimator: TimelineProgressEstimator,
        renderer: any ProgressRendering
    ) throws -> CommandOutput {
        guard renderingProgress else {
            return try commandRunner.run(command, outputHandler: nil)
        }

        let dateProvider = self.dateProvider
        return try commandRunner.run(command) { chunk in
            let elapsed = dateProvider().timeIntervalSince(startTime)
            var estimate = progressEstimator.estimate(elapsed: elapsed)
            for record in chunk.lineRecords {
                estimate = progressEstimator.observeCurrentLine(record, elapsed: elapsed)
            }

            renderer.writeOutputAndRedraw(
                rawOutput: chunk.rawOutput,
                stream: chunk.stream,
                progress: estimate.progress,
                remainingTime: estimate.remainingTime,
                containsPartialLine: chunk.containsPartialLine
            )
        }
    }

    private func saveSuccessfulRun(
        _ output: CommandOutput,
        history: CommandHistory?,
        request: CommandRunRequest
    ) {
        var updatedHistory = history ?? CommandHistory()
        updatedHistory.runs.append(CommandRun(
            date: dateProvider(),
            totalDuration: output.totalDuration,
            lineRecords: output.lineRecords
        ))

        do {
            try historyStore.save(
                updatedHistory,
                for: request.commandKey,
                maximumRunCount: request.maximumRunCount,
                staleAfterDays: 90
            )
        } catch {
            writeWarning("eta: warning: failed to save history: \(error.localizedDescription)")
        }
    }
}
