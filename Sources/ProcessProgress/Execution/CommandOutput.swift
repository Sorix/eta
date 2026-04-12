import Foundation

/// The command output stream that produced a chunk of bytes.
public enum CommandOutputStream: Sendable, Equatable {
    /// Bytes written to standard output.
    case standardOutput

    /// Bytes written to standard error.
    case standardError
}

/// The result of running a shell command.
public struct CommandOutput: Sendable {
    /// Hashed output lines collected while the command ran.
    public let lineRecords: [LineRecord]

    /// Total wall-clock duration in seconds.
    public let totalDuration: Double

    /// Process termination status.
    public let exitCode: Int32

    /// Creates command output from collected line records, duration, and exit code.
    ///
    /// - Parameters:
    ///   - lineRecords: Hashed output lines collected while the command ran.
    ///   - totalDuration: Total wall-clock duration in seconds.
    ///   - exitCode: Process termination status.
    public init(lineRecords: [LineRecord], totalDuration: Double, exitCode: Int32) {
        self.lineRecords = lineRecords
        self.totalDuration = totalDuration
        self.exitCode = exitCode
    }
}

/// A raw output chunk plus any complete line records observed in that chunk.
public struct CommandOutputChunk: Sendable {
    /// Raw bytes exactly as emitted by the command.
    public let rawOutput: Data

    /// Complete line records parsed from `rawOutput`.
    public let lineRecords: [LineRecord]

    /// The output stream that produced `rawOutput`.
    public let stream: CommandOutputStream

    /// Whether the stream currently has bytes for a line without a trailing newline.
    public let containsPartialLine: Bool

    /// Creates an output chunk from raw bytes and parsed line metadata.
    ///
    /// - Parameters:
    ///   - rawOutput: Raw bytes exactly as emitted by the command.
    ///   - lineRecords: Complete line records parsed from `rawOutput`.
    ///   - stream: The output stream that produced `rawOutput`.
    ///   - containsPartialLine: Whether the stream currently has bytes for a line without a trailing newline.
    public init(
        rawOutput: Data,
        lineRecords: [LineRecord],
        stream: CommandOutputStream,
        containsPartialLine: Bool
    ) {
        self.rawOutput = rawOutput
        self.lineRecords = lineRecords
        self.stream = stream
        self.containsPartialLine = containsPartialLine
    }
}

/// Handles raw command output while a command is running.
///
/// The handler is responsible for writing `chunk.rawOutput` unchanged when custom
/// rendering is needed.
public typealias CommandOutputHandler = @Sendable (CommandOutputChunk) -> Void
