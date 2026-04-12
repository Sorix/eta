import Foundation

/// Errors thrown while reading or writing command history.
public enum HistoryStoreError: Error, LocalizedError, Sendable {
    /// The maximum retained run count must be greater than zero.
    case invalidMaximumRunCount(Int)

    /// A human-readable description of the history store error.
    public var errorDescription: String? {
        switch self {
        case .invalidMaximumRunCount(let value):
            return "maximumRunCount must be greater than 0 (got \(value))."
        }
    }
}

/// Loads, saves, and clears privacy-preserving command history files.
public struct HistoryStore: Sendable {
    private let directory: URL

    /// Creates a store in the user cache directory for an app identifier.
    ///
    /// - Parameter appIdentifier: The cache subdirectory name.
    public init(appIdentifier: String) {
        self.directory = Self.cacheDirectory(for: appIdentifier)
    }

    /// Creates a store rooted at a specific directory.
    ///
    /// - Parameter directory: The directory containing command history files.
    public init(directory: URL) {
        self.directory = directory
    }

    private static func cacheDirectory(for appIdentifier: String) -> URL {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            fatalError("No user cache directory found — FileManager returned empty array for .cachesDirectory")
        }
        return caches.appendingPathComponent(appIdentifier)
    }

    static func fingerprint(for command: String) -> String {
        CommandFingerprint.hash(command)
    }

    /// Loads history for a command key.
    ///
    /// - Parameter command: The command key, usually the command string or `--name` value.
    /// - Returns: Stored history, or `nil` when the command has no history.
    /// - Throws: File read or JSON decoding errors.
    public func load(for command: String) throws -> CommandHistory? {
        let file = filePath(for: command)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CommandHistory.self, from: data)
    }

    static let maxLinesPerRun = 5000

    /// Saves history for a command key.
    ///
    /// - Parameters:
    ///   - history: The history to persist.
    ///   - command: The command key, usually the command string or `--name` value.
    ///   - maximumRunCount: Maximum number of recent runs to keep.
    ///   - staleAfterDays: Age in days after which unrelated history files may be pruned.
    /// - Throws: `HistoryStoreError` for invalid arguments, or file/JSON write errors.
    public func save(
        _ history: CommandHistory,
        for command: String,
        maximumRunCount: Int = 10,
        staleAfterDays: Int = 90
    ) throws {
        guard maximumRunCount > 0 else {
            throw HistoryStoreError.invalidMaximumRunCount(maximumRunCount)
        }

        var pruned = history
        if pruned.runs.count > maximumRunCount {
            pruned.runs = Array(pruned.runs.suffix(maximumRunCount))
        }
        pruned.runs = pruned.runs.map { run in
            CommandRun(
                date: run.date,
                totalDuration: run.totalDuration,
                lineRecords: Self.downsample(run.lineRecords, maximumCount: Self.maxLinesPerRun)
            )
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(pruned)
        try data.write(to: filePath(for: command), options: .atomic)
        pruneStale(olderThanDays: staleAfterDays)
    }

    /// Remove history files not modified in the given number of days.
    private func pruneStale(olderThanDays days: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        for file in files where file.pathExtension == "json" {
            guard let modDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  modDate < cutoff else { continue }
            try? fm.removeItem(at: file)
        }
    }

    /// Evenly samples lines across the full run, always keeping the first and last line.
    static func downsample(_ lines: [LineRecord], maximumCount: Int) -> [LineRecord] {
        guard lines.count > maximumCount, maximumCount >= 2 else { return lines }
        var result = [lines[0]]
        let step = Double(lines.count - 1) / Double(maximumCount - 1)
        for index in 1..<(maximumCount - 1) {
            result.append(lines[Int((Double(index) * step).rounded())])
        }
        result.append(lines[lines.count - 1])
        return result
    }

    /// Clears history for one command key.
    ///
    /// - Parameter command: The command key to clear.
    /// - Throws: File removal errors.
    public func clear(for command: String) throws {
        let file = filePath(for: command)
        let fm = FileManager.default
        if fm.fileExists(atPath: file.path) {
            try fm.removeItem(at: file)
        }
    }

    /// Clears all stored command history.
    ///
    /// - Throws: File removal errors.
    public func clearAll() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        try fm.removeItem(at: directory)
    }

    private func filePath(for command: String) -> URL {
        filePath(forFingerprint: Self.fingerprint(for: command))
    }

    private func filePath(forFingerprint fingerprint: String) -> URL {
        directory.appendingPathComponent("\(fingerprint).json")
    }
}
