import ArgumentParser
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import ProcessProgress

@main
struct ETA: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "eta",
        abstract: "Learn how long your commands take and show a live progress bar."
    )

    @Option(name: .long, help: "Custom name for the command (instead of the command string itself).")
    var name: String?

    @Option(name: .long, help: "Clear history for a specific command.")
    var clear: String?

    @Flag(name: .long, help: "Clear history for all commands.")
    var clearAll = false

    @Flag(name: .long, help: "Learn execution time without showing a progress bar.")
    var quiet = false

    @Flag(name: .long, help: "Draw a single solid progress fill instead of shading predicted progress.")
    var solid = false

    @Option(name: .long, help: "Number of recent runs to use for averaging (default: 10).")
    var runs: Int?

    @Option(name: .long, help: "Progress bar color: \(BarColor.allCases.map(\.rawValue).joined(separator: ", ")) (default: green).")
    var color: BarColor = .green

    @Argument(help: "The command to run.")
    var command: String?

    mutating func validate() throws {
        let modeFlags = [clear != nil, clearAll, command != nil]
        let activeCount = modeFlags.filter { $0 }.count

        if activeCount == 0 {
            throw ValidationError("Provide a command to run, or use --clear / --clear-all.")
        }
        if activeCount > 1 {
            throw ValidationError("Use only one mode at a time (command, --clear, --clear-all).")
        }
        if let runs, runs <= 0 {
            throw ValidationError("--runs must be greater than 0.")
        }
    }

    func run() throws {
        let store = HistoryStore(appIdentifier: "eta")

        if let clear {
            try store.clear(command: clear)
            printStdout("Cleared history for '\(clear)'.")
        } else if clearAll {
            try store.clearAll()
            printStdout("Cleared all history.")
        } else if let command {
            try runCommand(store: store, command: command)
        }
    }

    // MARK: - Run Command

    private func runCommand(store: HistoryStore, command: String) throws {
        let key = name ?? command
        let history = try store.load(command: key)
        let progressEstimator = TimelineProgressEstimator(history: history)
        let renderer = ProgressRenderer(color: color, style: solid ? .solid : .layered)
        let maxRuns = runs ?? 10
        let hasHistory = progressEstimator.hasHistory
        let renderProgress = !quiet && renderer.isEnabled && hasHistory

        let startTime = Date()

        if renderProgress {
            let estimate = progressEstimator.estimate(elapsed: 0)
            renderer.forceUpdate(progress: estimate.progress,
                                 eta: estimate.eta)
        }

        // Background timer: redraws bar at 5 fps.
        let timer: DispatchSourceTimer? = renderProgress ? {
            let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
            t.schedule(deadline: .now() + 0.2, repeating: 0.2)
            t.setEventHandler { [renderer, progressEstimator, startTime] in
                let elapsed = Date().timeIntervalSince(startTime)
                let estimate = progressEstimator.estimate(elapsed: elapsed)
                renderer.update(progress: estimate.progress, eta: estimate.eta)
            }
            t.resume()
            return t
        }() : nil

        // Clean up progress bar on SIGINT/SIGTERM so the terminal isn't left dirty.
        let signalSources: [DispatchSourceSignal] = renderProgress ? {
            var sources: [DispatchSourceSignal] = []
            for sig in [SIGINT, SIGTERM] {
                signal(sig, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
                source.setEventHandler {
                    renderer.cleanup()
                    signal(sig, SIG_DFL)
                    raise(sig)
                }
                source.resume()
                sources.append(source)
            }
            return sources
        }() : []

        let runner = CommandRunner()
        let output: CommandOutput
        if renderProgress {
            output = try runner.run(command: command) { chunk in
                let elapsed = Date().timeIntervalSince(startTime)
                var estimate = progressEstimator.estimate(elapsed: elapsed)
                for record in chunk.records {
                    estimate = progressEstimator.observeCurrentLine(record, elapsed: elapsed)
                }

                renderer.writeOutputAndRedraw(
                    data: chunk.data,
                    isStderr: chunk.isStderr,
                    progress: estimate.progress,
                    eta: estimate.eta,
                    hasOpenLine: chunk.hasOpenLine
                )
            }
        } else {
            output = try runner.run(command: command)
        }

        // Stop timer, signal handlers, and finish
        timer?.cancel()
        for source in signalSources { source.cancel() }
        if !signalSources.isEmpty {
            signal(SIGINT, SIG_DFL)
            signal(SIGTERM, SIG_DFL)
        }
        if renderProgress {
            renderer.finish(
                elapsed: output.totalDuration,
                expected: progressEstimator.expectedTotal
            )
        }

        // Only save successful runs — failed runs are useless for estimation
        if output.exitCode == 0 {
            var hist = history ?? CommandHistory(command: key, runs: [])
            hist.runs.append(Run(
                date: Date(),
                totalDuration: output.totalDuration,
                lines: output.lines
            ))
            do {
                try store.save(hist, maxRuns: maxRuns)
            } catch {
                printStderr("eta: warning: failed to save history: \(error.localizedDescription)")
            }
        } else {
            throw ExitCode(output.exitCode)
        }
    }

    // MARK: - Helpers

    private func printStdout(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    private func printStderr(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
