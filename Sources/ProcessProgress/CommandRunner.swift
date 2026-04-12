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

/// Runs shell commands and records hashed output lines with timeline offsets.
public struct CommandRunner: Sendable {
    private let outputWriter: CommandOutputWriter

    /// Creates a command runner that passes output through to standard output and standard error.
    public init() {
        self.outputWriter = .standard
    }

    init(outputWriter: CommandOutputWriter) {
        self.outputWriter = outputWriter
    }

    /// Runs a shell command.
    ///
    /// Without `outputHandler`, stdout and stderr bytes are passed through unchanged.
    ///
    /// - Parameters:
    ///   - command: The shell command to run.
    ///   - outputHandler: Optional handler for raw output chunks.
    /// - Returns: Collected line records, total duration, and the command exit code.
    /// - Throws: Any error thrown while launching the process.
    public func run(_ command: String, outputHandler: CommandOutputHandler? = nil) throws -> CommandOutput {
        let process = makeProcess(command: command)
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let startTime = Date()
        let collectedLines = LockIsolated<[LineRecord]>([])
        let stdoutLineBuffer = LockIsolated(OutputLineBuffer())
        let stderrLineBuffer = LockIsolated(OutputLineBuffer())

        let handleOutput: @Sendable (Data, CommandOutputStream) -> Void = { data, stream in
            let offsetSeconds = Date().timeIntervalSince(startTime)
            let buffer = stream == .standardError ? stderrLineBuffer : stdoutLineBuffer
            let update = buffer.withLock { $0.append(data, offsetSeconds: offsetSeconds) }

            if !update.lineRecords.isEmpty {
                collectedLines.withLock { $0.append(contentsOf: update.lineRecords) }
            }

            if let outputHandler {
                outputHandler(CommandOutputChunk(
                    rawOutput: data,
                    lineRecords: update.lineRecords,
                    stream: stream,
                    containsPartialLine: update.containsPartialLine
                ))
            } else {
                outputWriter.write(data, to: stream)
            }
        }

        let drainGroup = DispatchGroup()
        drain(stdoutPipe, stream: .standardOutput, group: drainGroup, handler: handleOutput)
        drain(stderrPipe, stream: .standardError, group: drainGroup, handler: handleOutput)

        try process.run()
        process.waitUntilExit()
        drainGroup.wait()

        let totalDuration = Date().timeIntervalSince(startTime)
        flushFinalLines(
            stdoutLineBuffer: stdoutLineBuffer,
            stderrLineBuffer: stderrLineBuffer,
            offsetSeconds: totalDuration,
            into: collectedLines
        )

        return CommandOutput(
            lineRecords: collectedLines.withLock { $0 },
            totalDuration: totalDuration,
            exitCode: process.terminationStatus
        )
    }

    private func makeProcess(command: String) -> Process {
        let process = Process()
        let shellPath = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/sh"
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-c", command]
        return process
    }

    private func drain(
        _ pipe: Pipe,
        stream: CommandOutputStream,
        group: DispatchGroup,
        handler: @escaping @Sendable (Data, CommandOutputStream) -> Void
    ) {
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }

            while true {
                let data = pipe.fileHandleForReading.availableData
                guard !data.isEmpty else { break }
                handler(data, stream)
            }
        }
    }

    private func flushFinalLines(
        stdoutLineBuffer: LockIsolated<OutputLineBuffer>,
        stderrLineBuffer: LockIsolated<OutputLineBuffer>,
        offsetSeconds: Double,
        into collectedLines: LockIsolated<[LineRecord]>
    ) {
        let finalStdoutRecords = stdoutLineBuffer.withLock { $0.flushFinalLine(offsetSeconds: offsetSeconds) }
        let finalStderrRecords = stderrLineBuffer.withLock { $0.flushFinalLine(offsetSeconds: offsetSeconds) }
        guard !finalStdoutRecords.isEmpty || !finalStderrRecords.isEmpty else { return }

        collectedLines.withLock {
            $0.append(contentsOf: finalStdoutRecords)
            $0.append(contentsOf: finalStderrRecords)
        }
    }
}

struct CommandOutputWriter: Sendable {
    let write: @Sendable (Data, CommandOutputStream) -> Void

    static let standard = CommandOutputWriter { data, stream in
        let handle = stream == .standardError ? FileHandle.standardError : FileHandle.standardOutput
        handle.write(data)
    }

    func write(_ data: Data, to stream: CommandOutputStream) {
        write(data, stream)
    }
}
