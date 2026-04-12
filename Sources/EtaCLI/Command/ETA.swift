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
        try run(historyStore: Self.makeHistoryStore())
    }

    func run(historyStore store: any HistoryStoring) throws {
        if let clear {
            try store.clear(for: Self.resolvedCommandKey(clear))
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
                commandKey: name ?? Self.resolvedCommandKey(command),
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

    /// Builds a stable command key that distinguishes the same executable
    /// across different projects while sharing history for the same script
    /// invoked from different directories.
    ///
    /// - **Path-based invocations** (`./test.sh`, `../build.sh`, `/usr/bin/make arg`)
    ///   are resolved via C `realpath()` to a canonical absolute path.
    ///   The script path itself identifies the work — no cwd needed.
    /// - **Bare-name invocations** (`make`, `swift build`, `cargo test`)
    ///   resolve to the same executable everywhere, so the working directory
    ///   is prepended to distinguish projects.
    /// - Shell aliases, functions, and builtins won't resolve — the working
    ///   directory is prepended as for bare names. This is correct because
    ///   `eta` runs commands via `/bin/sh -c` where interactive aliases
    ///   aren't loaded, so unresolvable names behave like bare commands.
    static func resolvedCommandKey(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        let firstSpace = trimmed.firstIndex(of: " ")
        let executable = firstSpace.map { String(trimmed[..<$0]) } ?? trimmed
        let rest = firstSpace.map { String(trimmed[$0...]) } ?? ""

        // Path-based: resolve to canonical path, no cwd needed.
        if executable.contains("/"), let resolved = realpathOrNil(executable) {
            return resolved + rest
        }

        // Bare name: prepend cwd so different projects get separate history.
        let cwd = FileManager.default.currentDirectoryPath
        if let resolved = whichPath(executable) {
            return "\(cwd)\n\(resolved)\(rest)"
        }

        // Unresolvable: treat like a bare name with cwd.
        return "\(cwd)\n\(command)"
    }

    /// Resolves a file path to its canonical absolute path via C `realpath()`.
    /// Returns `nil` when the file does not exist.
    private static func realpathOrNil(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Runs `which` to find the absolute path for a bare executable name.
    /// Returns `nil` when the executable is not found on PATH.
    private static func whichPath(_ executable: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [executable]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty else { return nil }
        return path
    }

    private static func printStdout(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    private static func printStderr(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
