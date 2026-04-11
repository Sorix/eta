import Foundation

struct CommandOutput: Sendable {
    let lines: [LineRecord]
    let totalDuration: Double
    let exitCode: Int32
}

/// Callback for each line of output. Parameters: (line text, offset seconds, is stderr)
typealias LineCallback = @Sendable (String, Double, Bool) -> Void

struct CommandRunner: Sendable {

    /// Run a shell command, calling `onLine` for each line of output.
    /// stdout lines are passed through to stdout, stderr lines to stderr.
    /// Returns collected lines with timestamps plus the exit code.
    func run(command: String, onLine: LineCallback? = nil) throws -> CommandOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let startTime = Date()
        let collectedLines = LockIsolated<[LineRecord]>([])
        let onLineCopy = onLine

        let handleData: @Sendable (Data, Bool) -> Void = { data, isStderr in
            guard let text = String(data: data, encoding: .utf8) else { return }
            let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for rawLine in rawLines {
                let line = String(rawLine)
                guard !line.isEmpty else { continue }
                let offset = Date().timeIntervalSince(startTime)
                let record = LineRecord(
                    text: line,
                    normalizedText: CommandRunner.normalize(line),
                    offsetSeconds: offset
                )
                collectedLines.withLock { $0.append(record) }

                if isStderr {
                    FileHandle.standardError.write(Data((line + "\n").utf8))
                } else {
                    FileHandle.standardOutput.write(Data((line + "\n").utf8))
                }

                onLineCopy?(line, offset, isStderr)
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            handleData(data, false)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            handleData(data, true)
        }

        try process.run()
        process.waitUntilExit()

        // Drain remaining data
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingStdout.isEmpty { handleData(remainingStdout, false) }

        let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingStderr.isEmpty { handleData(remainingStderr, true) }

        let totalDuration = Date().timeIntervalSince(startTime)

        return CommandOutput(
            lines: collectedLines.withLock { $0 },
            totalDuration: totalDuration,
            exitCode: process.terminationStatus
        )
    }

    // MARK: - Line Normalization

    /// Strip digits and collapse whitespace for fuzzy line matching.
    static func normalize(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var lastWasSpace = false
        for ch in text {
            if ch.isNumber {
                if !lastWasSpace {
                    result.append("N")
                    lastWasSpace = false
                }
                continue
            }
            if ch.isWhitespace {
                if !lastWasSpace {
                    result.append(" ")
                    lastWasSpace = true
                }
            } else {
                result.append(ch)
                lastWasSpace = false
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Thread-safe wrapper

final class LockIsolated<Value: Sendable>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()

    init(_ value: Value) { _value = value }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&_value)
    }
}
