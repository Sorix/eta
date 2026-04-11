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

/// A raw output chunk plus any complete line records observed in that chunk.
public struct CommandOutputChunk: Sendable {
    public let data: Data
    public let records: [LineRecord]
    public let isStderr: Bool
    public let hasOpenLine: Bool

    public init(data: Data, records: [LineRecord], isStderr: Bool, hasOpenLine: Bool) {
        self.data = data
        self.records = records
        self.isStderr = isStderr
        self.hasOpenLine = hasOpenLine
    }
}

/// Callback for raw command output. The callback is responsible for writing
/// `chunk.data` unchanged when custom rendering is needed.
public typealias OutputCallback = @Sendable (CommandOutputChunk) -> Void

public struct CommandRunner: Sendable {
    public init() {}

    /// Run a shell command, calling `onOutput` for each raw output chunk.
    /// Without a callback, stdout/stderr bytes are passed through unchanged.
    /// Returns collected lines with timestamps plus the exit code.
    public func run(command: String, onOutput: OutputCallback? = nil) throws -> CommandOutput {
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
        let stdoutLineBuffer = LockIsolated(StreamLineBuffer())
        let stderrLineBuffer = LockIsolated(StreamLineBuffer())
        let onOutputCopy = onOutput

        let handleData: @Sendable (Data, Bool) -> Void = { data, isStderr in
            let buffer = isStderr ? stderrLineBuffer : stdoutLineBuffer
            let update = buffer.withLock { $0.append(data, startTime: startTime) }

            if !update.records.isEmpty {
                collectedLines.withLock { $0.append(contentsOf: update.records) }
            }

            if let callback = onOutputCopy {
                callback(CommandOutputChunk(
                    data: data,
                    records: update.records,
                    isStderr: isStderr,
                    hasOpenLine: update.hasOpenLine
                ))
            } else {
                Self.writeOutput(data, isStderr: isStderr)
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

        let finalStdoutRecords = stdoutLineBuffer.withLock { $0.flushFinalLine(startTime: startTime) }
        let finalStderrRecords = stderrLineBuffer.withLock { $0.flushFinalLine(startTime: startTime) }
        if !finalStdoutRecords.isEmpty || !finalStderrRecords.isEmpty {
            collectedLines.withLock {
                $0.append(contentsOf: finalStdoutRecords)
                $0.append(contentsOf: finalStderrRecords)
            }
        }

        let totalDuration = Date().timeIntervalSince(startTime)

        return CommandOutput(
            lines: collectedLines.withLock { $0 },
            totalDuration: totalDuration,
            exitCode: process.terminationStatus
        )
    }

    // MARK: - Line Normalization

    /// Collapse numeric runs and whitespace for fuzzy line matching.
    static func normalize(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var lastWasSpace = false
        var lastWasDigit = false
        for ch in text {
            if ch.isNumber {
                if !lastWasDigit {
                    result.append("N")
                }
                lastWasSpace = false
                lastWasDigit = true
                continue
            }
            if ch.isWhitespace {
                if !lastWasSpace {
                    result.append(" ")
                    lastWasSpace = true
                }
                lastWasDigit = false
            } else {
                result.append(ch)
                lastWasSpace = false
                lastWasDigit = false
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func writeOutput(_ data: Data, isStderr: Bool) {
        let handle = isStderr ? FileHandle.standardError : FileHandle.standardOutput
        handle.write(data)
    }
}

private struct StreamLineBuffer: Sendable {
    struct Update: Sendable {
        let records: [LineRecord]
        let hasOpenLine: Bool
    }

    private var pending = Data()

    mutating func append(_ data: Data, startTime: Date) -> Update {
        var records: [LineRecord] = []

        for byte in data {
            if byte == 0x0A {
                if let record = Self.makeRecord(from: pending, startTime: startTime) {
                    records.append(record)
                }
                pending.removeAll(keepingCapacity: true)
            } else {
                pending.append(byte)
            }
        }

        return Update(records: records, hasOpenLine: !pending.isEmpty)
    }

    mutating func flushFinalLine(startTime: Date) -> [LineRecord] {
        defer { pending.removeAll(keepingCapacity: false) }
        guard let record = Self.makeRecord(from: pending, startTime: startTime) else {
            return []
        }
        return [record]
    }

    private static func makeRecord(from lineData: Data, startTime: Date) -> LineRecord? {
        guard !lineData.isEmpty,
              let line = String(data: lineData, encoding: .utf8),
              !line.isEmpty else {
            return nil
        }

        let offset = Date().timeIntervalSince(startTime)
        return LineRecord(
            textHash: LineHash.hash(line),
            normalizedHash: LineHash.normalizedHash(line),
            offsetSeconds: offset
        )
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
