import ArgumentParser
import Foundation

@main
struct ETA: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "eta",
        abstract: "Learn how long your commands take and show a live progress bar."
    )

    @Option(name: .long, help: "Custom name for the command (instead of the command string itself).")
    var name: String?

    @Flag(name: .long, help: "List all learned commands and run counts.")
    var list = false

    @Option(name: .long, help: "Clear history for a specific command.")
    var clear: String?

    @Flag(name: .long, help: "Clear history for all commands.")
    var clearAll = false

    @Option(name: .long, help: "Show timing breakdown per line for a command.")
    var stats: String?

    @Flag(name: .long, help: "No progress bar, pure pass-through.")
    var quiet = false

    @Option(name: .long, help: "Number of recent runs to use for averaging (default: 10).")
    var runs: Int?

    @Argument(help: "The command to run.")
    var command: String?

    mutating func validate() throws {
        let modeFlags = [list, clear != nil, clearAll, stats != nil, command != nil]
        let activeCount = modeFlags.filter { $0 }.count

        if activeCount == 0 {
            throw ValidationError("Provide a command to run, or use --list, --clear, --stats.")
        }
        if activeCount > 1 {
            throw ValidationError("Use only one mode at a time (command, --list, --clear, --stats).")
        }
    }

    func run() throws {
        let store = HistoryStore()

        if list {
            try runList(store: store)
        } else if let clear {
            try store.clear(command: clear)
            printStderr("Cleared history for '\(clear)'.")
        } else if clearAll {
            try store.clearAll()
            printStderr("Cleared all history.")
        } else if let stats {
            try runStats(store: store, command: stats)
        } else if let command {
            try runCommand(store: store, command: command)
        }
    }

    // MARK: - Run Command

    private func runCommand(store: HistoryStore, command: String) throws {
        let key = name ?? command
        let history = try store.load(command: key)
        let calculator = ETACalculator(history: history)
        let renderer = ProgressRenderer()
        let maxRuns = runs ?? 10

        let lastMatchedIndex = LockIsolated<Int>(-1)
        let startTime = Date()

        let runner = CommandRunner()
        let output = try runner.run(command: command) { line, offset, _ in
            guard !quiet else { return }

            if calculator.hasHistory {
                if let idx = calculator.matchLine(line) {
                    lastMatchedIndex.withLock { $0 = max($0, idx) }
                }
                let idx = lastMatchedIndex.withLock { $0 }
                let progress = idx >= 0 ? calculator.progress(forMatchedIndex: idx) : 0
                let elapsed = Date().timeIntervalSince(startTime)
                let eta = calculator.eta(elapsed: elapsed)
                let runCount = history?.runs.count ?? 0

                renderer.clearBar()
                renderer.forceUpdate(
                    progress: progress, elapsed: elapsed, eta: eta,
                    runCount: runCount, isLearning: false
                )
            } else {
                let elapsed = Date().timeIntervalSince(startTime)
                renderer.clearBar()
                renderer.forceUpdate(
                    progress: 0, elapsed: elapsed, eta: 0,
                    runCount: 0, isLearning: true
                )
            }
        }

        // Finish progress bar
        if !quiet {
            renderer.finish(
                elapsed: output.totalDuration,
                expected: calculator.expectedTotal,
                hasHistory: calculator.hasHistory
            )
        }

        // Save run
        var hist = history ?? CommandHistory(commandString: key, runs: [])
        hist.commandString = key
        if name != nil { hist.customName = name }
        hist.runs.append(Run(
            date: Date(),
            totalDuration: output.totalDuration,
            complete: output.exitCode == 0,
            lines: output.lines
        ))
        try store.save(hist, maxRuns: maxRuns)

        // Propagate exit code
        if output.exitCode != 0 {
            throw ExitCode(output.exitCode)
        }
    }

    // MARK: - List

    private func runList(store: HistoryStore) throws {
        let histories = try store.listAll()
        guard !histories.isEmpty else {
            printStderr("No learned commands yet.")
            return
        }

        printStderr("\("COMMAND".padding(toLength: 40, withPad: " ", startingAt: 0))  \("RUNS".padding(toLength: 5, withPad: " ", startingAt: 0))  AVG TIME")
        printStderr(String(repeating: "─", count: 60))

        for hist in histories {
            let label = hist.customName ?? hist.commandString
            let truncated = label.count > 38 ? String(label.prefix(37)) + "…" : label
            let avgDuration = hist.runs.isEmpty ? 0 :
                hist.runs.map(\.totalDuration).reduce(0, +) / Double(hist.runs.count)
            let col1 = truncated.padding(toLength: 40, withPad: " ", startingAt: 0)
            let col2 = String(hist.runs.count).padding(toLength: 5, withPad: " ", startingAt: 0)
            printStderr("\(col1)  \(col2)  \(formatTime(avgDuration))")
        }
    }

    // MARK: - Stats

    private func runStats(store: HistoryStore, command: String) throws {
        guard let history = try store.load(command: command) else {
            printStderr("No history for '\(command)'.")
            throw ExitCode.failure
        }

        guard let lastRun = history.runs.last else {
            printStderr("No runs recorded.")
            throw ExitCode.failure
        }

        printStderr("Stats for '\(history.customName ?? command)' (\(history.runs.count) runs)")
        printStderr(String(format: "Last run: %.1fs (%@)", lastRun.totalDuration, lastRun.complete ? "complete" : "incomplete"))
        printStderr("")
        printStderr("\("OFFSET".padding(toLength: 8, withPad: " ", startingAt: 0))  LINE")
        printStderr(String(repeating: "─", count: 60))

        for line in lastRun.lines {
            let offset = String(format: "%7.1fs", line.offsetSeconds)
            printStderr("\(offset)  \(line.text)")
        }
    }

    // MARK: - Helpers

    private func printStderr(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private func formatTime(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            let m = Int(seconds) / 60
            let s = seconds - Double(m * 60)
            return String(format: "%dm%04.1fs", m, s)
        }
    }
}
