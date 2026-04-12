import Foundation

public enum HistoryStoreError: Error, LocalizedError, Sendable {
    case invalidMaxRuns(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidMaxRuns(let value):
            return "maxRuns must be greater than 0 (got \(value))."
        }
    }
}

public struct HistoryStore: Sendable {
    private let directory: URL

    public init(appIdentifier: String) {
        self.directory = Self.cacheDirectory(for: appIdentifier)
    }

    public init(directory: URL) {
        self.directory = directory
    }

    private static func cacheDirectory(for appIdentifier: String) -> URL {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            fatalError("No user cache directory found — FileManager returned empty array for .cachesDirectory")
        }
        return caches.appendingPathComponent(appIdentifier)
    }

    // MARK: - Fingerprinting

    static func fingerprint(for command: String) -> String {
        CommandFingerprint.hash(command)
    }

    // MARK: - Load / Save

    public func load(command: String) throws -> CommandHistory? {
        let file = filePath(for: command)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CommandHistory.self, from: data)
    }

    static let maxLinesPerRun = 5000

    public func save(_ history: CommandHistory, command: String, maxRuns: Int = 10) throws {
        guard maxRuns > 0 else {
            throw HistoryStoreError.invalidMaxRuns(maxRuns)
        }

        var pruned = history
        if pruned.runs.count > maxRuns {
            pruned.runs = Array(pruned.runs.suffix(maxRuns))
        }
        pruned.runs = pruned.runs.map { run in
            Run(date: run.date, totalDuration: run.totalDuration,
                lines: Self.downsample(run.lines, max: Self.maxLinesPerRun))
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(pruned)
        try data.write(to: filePath(for: command), options: .atomic)
    }

    /// Evenly sample lines across the full run, always keeping first and last.
    static func downsample(_ lines: [LineRecord], max: Int) -> [LineRecord] {
        guard lines.count > max, max >= 2 else { return lines }
        var result = [lines[0]]
        let step = Double(lines.count - 1) / Double(max - 1)
        for i in 1..<(max - 1) {
            result.append(lines[Int((Double(i) * step).rounded())])
        }
        result.append(lines[lines.count - 1])
        return result
    }

    // MARK: - Clear

    public func clear(command: String) throws {
        let file = filePath(for: command)
        let fm = FileManager.default
        if fm.fileExists(atPath: file.path) {
            try fm.removeItem(at: file)
        }
    }

    public func clearAll() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        try fm.removeItem(at: directory)
    }

    // MARK: - Private

    private func filePath(for command: String) -> URL {
        filePath(forFingerprint: Self.fingerprint(for: command))
    }

    private func filePath(forFingerprint fingerprint: String) -> URL {
        directory.appendingPathComponent("\(fingerprint).json")
    }
}

