import Foundation

public struct CommandOutput: Sendable {
    public let lines: [LineRecord]
    public let totalDuration: Double
    public let exitCode: Int32

    public init(lines: [LineRecord], totalDuration: Double, exitCode: Int32) {
        self.lines = lines
        self.totalDuration = totalDuration
        self.exitCode = exitCode
    }
}

/// Callback for each line of output. Parameters: (line text, offset seconds, is stderr)
/// The callback is responsible for writing the line to the terminal (if desired).
public typealias LineCallback = @Sendable (String, Double, Bool) -> Void

public struct CommandRunner: Sendable {
    public init() {}

    /// Run a shell command, calling `onLine` for each line of output.
    /// stdout lines are passed through to stdout, stderr lines to stderr.
    /// Returns collected lines with timestamps plus the exit code.
    public func run(command: String, onLine: LineCallback? = nil) throws -> CommandOutput {
        let process = Process()
        let shellPath = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/sh"
        process.executableURL = URL(fileURLWithPath: shellPath)
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
                    textHash: LineHash.hash(line),
                    normalizedHash: LineHash.normalizedHash(line),
                    offsetSeconds: offset
                )
                collectedLines.withLock { $0.append(record) }

                if let cb = onLineCopy {
                    // Callback handles output (clear bar → write line → redraw bar)
                    cb(line, offset, isStderr)
                } else {
                    // No callback — write directly
                    if isStderr {
                        FileHandle.standardError.write(Data((line + "\n").utf8))
                    } else {
                        FileHandle.standardOutput.write(Data((line + "\n").utf8))
                    }
                }
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
