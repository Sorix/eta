import CryptoKit
import Foundation

public struct LineRecord: Codable, Sendable {
    public let textHash: String
    public let normalizedHash: String
    public let offsetSeconds: Double

    public init(textHash: String, normalizedHash: String, offsetSeconds: Double) {
        self.textHash = textHash
        self.normalizedHash = normalizedHash
        self.offsetSeconds = offsetSeconds
    }
}

public struct Run: Codable, Sendable {
    public let date: Date
    public let totalDuration: Double
    public let lines: [LineRecord]

    public init(date: Date, totalDuration: Double, lines: [LineRecord]) {
        self.date = date
        self.totalDuration = totalDuration
        self.lines = lines
    }
}

public struct CommandHistory: Codable, Sendable {
    public var runs: [Run]

    public init(runs: [Run] = []) {
        self.runs = runs
    }
}

// MARK: - Hashing

public enum CommandFingerprint {
    public static func hash(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum LineHash {
    /// MD5 is marked `Insecure` in CryptoKit because it's vulnerable to deliberate
    /// collision attacks — but that's irrelevant here. We use it as a one-way digest
    /// to avoid storing raw command output on disk. MD5 is not reversible (output can't
    /// be turned back into the original text), and collisions only cause a slightly
    /// inaccurate ETA — no security implications. Hardware-accelerated on Apple Silicon.
    public static func hash(_ string: String) -> String {
        md5(string)
    }

    public static func normalizedHash(_ string: String) -> String {
        md5(CommandRunner.normalize(string))
    }

    static func md5(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
