import Foundation

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
