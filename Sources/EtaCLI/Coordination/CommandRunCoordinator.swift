import ArgumentParser
import Foundation
import ProcessProgress

/// Runs the high-level command workflow: load history, execute, render progress, and save success.
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
        let hasHistory = progressEstimator.hasHistory
        let shouldRenderProgress = !request.quiet && renderer.isEnabled && hasHistory

        if !request.quiet && renderer.isEnabled && !hasHistory {
            renderer.writeFirstRunHeader()
        }

        let startTime = dateProvider()
        var renderingSession = RenderingSession(
            renderer: renderer,
            isActive: shouldRenderProgress,
            estimator: progressEstimator,
            startTime: startTime,
            dateProvider: dateProvider,
            renderLoopFactory: renderLoopFactory,
            signalTrapFactory: signalTrapFactory
        )

        let output: CommandOutput
        do {
            output = try runCommand(
                request.command,
                renderingProgress: renderingSession.isActive,
                startTime: startTime,
                progressEstimator: progressEstimator,
                renderer: renderer
            )
        } catch {
            renderingSession.end(cleanupOnly: true)
            throw error
        }

        guard output.exitCode == 0 else {
            renderingSession.end(cleanupOnly: true)
            throw ExitCode(output.exitCode)
        }

        renderingSession.end(cleanupOnly: false)
        renderingSession.finish(
            elapsed: output.totalDuration,
            expectedDuration: progressEstimator.expectedTotalDuration
        )

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
                remainingTime: estimate.displayRemainingTime,
                elapsedTime: elapsed,
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
