import Foundation

/// A successful command execution stored in history.
public struct CommandRun: Codable, Sendable {
    /// The date when the command finished successfully.
    public let date: Date

    /// Total wall-clock duration in seconds.
    public let totalDuration: Double

    /// Hashed output lines observed during the run.
    public let lineRecords: [LineRecord]

    private enum CodingKeys: String, CodingKey {
        case date
        case totalDuration
        case lineRecords = "lines"
    }

    /// Creates a command run from a completion date, duration, and observed lines.
    ///
    /// - Parameters:
    ///   - date: The date when the command finished successfully.
    ///   - totalDuration: Total wall-clock duration in seconds.
    ///   - lineRecords: Hashed output lines observed during the run.
    public init(date: Date, totalDuration: Double, lineRecords: [LineRecord]) {
        self.date = date
        self.totalDuration = totalDuration
        self.lineRecords = lineRecords
    }
}

/// Stored execution history for one command key.
public struct CommandHistory: Codable, Sendable {
    /// Successful runs ordered from oldest to newest.
    public var runs: [CommandRun]

    /// Creates command history with an optional list of successful runs.
    ///
    /// - Parameter runs: Successful runs ordered from oldest to newest.
    public init(runs: [CommandRun] = []) {
        self.runs = runs
    }
}
