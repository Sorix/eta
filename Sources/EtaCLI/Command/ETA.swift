import ArgumentParser
import Foundation
import ProcessProgress

/// Command-line entry point for the `eta` executable.
public struct ETA: ParsableCommand {
    /// ArgumentParser configuration for the `eta` command.
    public static let configuration = CommandConfiguration(
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

    /// Creates the command parser with default option values.
    public init() {}

    /// Validates that exactly one command mode is selected.
    ///
    /// - Throws: `ValidationError` when flags select no mode, multiple modes, or an invalid run count.
    public mutating func validate() throws {
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

    /// Executes the selected command mode.
    ///
    /// - Throws: Errors from history operations, command execution, or non-zero wrapped command exits.
    public func run() throws {
        try run(historyStore: Self.makeHistoryStore(), commandKeyResolver: CommandKeyResolver.live)
    }

    func run(
        historyStore store: any HistoryStoring,
        commandKeyResolver: any CommandKeyResolving = CommandKeyResolver.live
    ) throws {
        if let clear {
            try store.clear(for: commandKeyResolver.resolvedKey(for: clear))
            Self.printStdout("Cleared history for '\(clear)'.")
        } else if clearAll {
            try store.clearAll()
            Self.printStdout("Cleared all history.")
        } else if let command {
            let coordinator = CommandRunCoordinator(
                historyStore: store,
                writeWarning: Self.printStderr
            )
            try coordinator.run(CommandRunRequest(
                command: command,
                commandKey: name ?? commandKeyResolver.resolvedKey(for: command),
                maximumRunCount: runs ?? 10,
                quiet: quiet,
                color: color,
                progressBarStyle: solid ? .solid : .layered
            ))
        }
    }

    static func makeHistoryStore(environment: [String: String] = ProcessInfo.processInfo.environment) -> HistoryStore {
        if let cacheDirectory = environment["ETA_CACHE_DIR"], !cacheDirectory.isEmpty {
            return HistoryStore(directory: URL(fileURLWithPath: cacheDirectory, isDirectory: true))
        }
        return HistoryStore(appIdentifier: "eta")
    }

    private static func printStdout(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    private static func printStderr(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
