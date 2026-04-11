import Foundation
import CryptoKit

struct HistoryStore: Sendable {
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".eta/history")
    }

    // MARK: - Fingerprinting

    static func fingerprint(for command: String) -> String {
        let digest = SHA256.hash(data: Data(command.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Load / Save

    func load(command: String) throws -> CommandHistory? {
        let file = filePath(for: command)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        return try JSONDecoder.withISO8601.decode(CommandHistory.self, from: data)
    }

    static let maxLinesPerRun = 1000

    func save(_ history: CommandHistory, maxRuns: Int = 10) throws {
        var pruned = history
        if pruned.runs.count > maxRuns {
            pruned.runs = Array(pruned.runs.suffix(maxRuns))
        }
        pruned.runs = pruned.runs.map { run in
            Run(date: run.date, totalDuration: run.totalDuration,
                lines: Self.downsample(run.lines, max: Self.maxLinesPerRun))
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.withISO8601.encode(pruned)
        try data.write(to: filePath(for: history.commandString), options: .atomic)
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

    // MARK: - List / Clear

    func listAll() throws -> [CommandHistory] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        return files.compactMap { file in
            guard let data = try? Data(contentsOf: file),
                  let history = try? JSONDecoder.withISO8601.decode(CommandHistory.self, from: data)
            else { return nil }
            return history
        }
    }

    func clear(command: String) throws {
        let file = filePath(for: command)
        let fm = FileManager.default
        if fm.fileExists(atPath: file.path) {
            try fm.removeItem(at: file)
        }
    }

    func clearAll() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        try fm.removeItem(at: directory)
    }

    // MARK: - Private

    private func filePath(for command: String) -> URL {
        directory.appendingPathComponent("\(Self.fingerprint(for: command)).json")
    }
}

// MARK: - JSON Coding Helpers

private extension JSONEncoder {
    static let withISO8601: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let withISO8601: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
