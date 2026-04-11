import ArgumentParser
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
        let calculator = EstimateCalculator(history: history)
        let renderer = ProgressRenderer(color: color)
        let maxRuns = runs ?? 10
        let renderProgress = !quiet && renderer.isEnabled

        let startTime = Date()
        let runCount = history?.runs.count ?? 0
        let isLearning = !calculator.hasHistory

        // Background timer: redraws bar every 100ms so progress fills smoothly
        let timer: DispatchSourceTimer? = renderProgress ? {
            let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
            t.schedule(deadline: .now() + 0.1, repeating: 0.1)
            t.setEventHandler { [renderer, calculator, startTime] in
                let elapsed = Date().timeIntervalSince(startTime)
                if isLearning {
                    renderer.update(progress: 0, elapsed: elapsed, eta: 0,
                                    runCount: 0, isLearning: true)
                } else {
                    let progress = calculator.progress(elapsed: elapsed)
                    let eta = calculator.eta(elapsed: elapsed)
                    renderer.update(progress: progress, elapsed: elapsed, eta: eta,
                                    runCount: runCount, isLearning: false)
                }
            }
            t.resume()
            return t
        }() : nil

        let renderProgressFlag = renderProgress
        let runner = CommandRunner()
        let output = try runner.run(command: command) { line, offset, isStderr in
            let elapsed = Date().timeIntervalSince(startTime)

            if !renderProgressFlag {
                if isStderr {
                    FileHandle.standardError.write(Data((line + "\n").utf8))
                } else {
                    FileHandle.standardOutput.write(Data((line + "\n").utf8))
                }
                return
            }

            // Atomic: clear bar → write line → redraw bar (race-free with timer)
            if isLearning {
                renderer.writeLineAndRedraw(
                    line: line, isStderr: isStderr,
                    progress: 0, elapsed: elapsed, eta: 0,
                    runCount: 0, isLearning: true)
            } else {
                let progress = calculator.progress(elapsed: elapsed)
                let eta = calculator.eta(elapsed: elapsed)
                renderer.writeLineAndRedraw(
                    line: line, isStderr: isStderr,
                    progress: progress, elapsed: elapsed, eta: eta,
                    runCount: runCount, isLearning: false)
            }
        }

        // Stop timer and finish
        timer?.cancel()
        if renderProgress {
            renderer.finish(
                elapsed: output.totalDuration,
                expected: calculator.expectedTotal,
                hasHistory: calculator.hasHistory
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
            try store.save(hist, maxRuns: maxRuns)
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
