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
        if list {
            print("TODO: list learned commands")
        } else if let clear {
            print("TODO: clear history for '\(clear)'")
        } else if clearAll {
            print("TODO: clear all history")
        } else if let stats {
            print("TODO: show stats for '\(stats)'")
        } else if let command {
            print("TODO: run '\(command)'")
        }
    }
}
