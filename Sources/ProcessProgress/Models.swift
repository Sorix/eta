import CryptoKit
import Foundation

/// A hashed output line observed during a command run.
public struct LineRecord: Codable, Sendable {
    /// MD5 digest of the original output line.
    public let textHash: String

    /// MD5 digest of the normalized output line.
    public let normalizedHash: String

    /// Seconds from the command start until this line was observed.
    public let offsetSeconds: Double

    /// Creates a line record from precomputed hashes and a timeline offset.
    ///
    /// - Parameters:
    ///   - textHash: MD5 digest of the original output line.
    ///   - normalizedHash: MD5 digest of the normalized output line.
    ///   - offsetSeconds: Seconds from the command start until this line was observed.
    public init(textHash: String, normalizedHash: String, offsetSeconds: Double) {
        self.textHash = textHash
        self.normalizedHash = normalizedHash
        self.offsetSeconds = offsetSeconds
    }
}

/// A successful command execution stored in history.
public struct CommandRun: Codable, Sendable {
    /// The date when the command finished successfully.
    public let date: Date

    /// Total wall-clock duration in seconds.
    public let totalDuration: Double

    /// Hashed output lines observed during the run.
    public let lineRecords: [LineRecord]

    private enum CodingKeys: String, CodingKey {
        case date
        case totalDuration
        case lineRecords = "lines"
    }

    /// Creates a command run from a completion date, duration, and observed lines.
    ///
    /// - Parameters:
    ///   - date: The date when the command finished successfully.
    ///   - totalDuration: Total wall-clock duration in seconds.
    ///   - lineRecords: Hashed output lines observed during the run.
    public init(date: Date, totalDuration: Double, lineRecords: [LineRecord]) {
        self.date = date
        self.totalDuration = totalDuration
        self.lineRecords = lineRecords
    }
}

/// Stored execution history for one command key.
public struct CommandHistory: Codable, Sendable {
    /// Successful runs ordered from oldest to newest.
    public var runs: [CommandRun]

    /// Creates command history with an optional list of successful runs.
    ///
    /// - Parameter runs: Successful runs ordered from oldest to newest.
    public init(runs: [CommandRun] = []) {
        self.runs = runs
    }
}

/// Creates privacy-preserving fingerprints for command keys.
public enum CommandFingerprint {
    /// Returns the SHA-256 digest for a command key.
    ///
    /// - Parameter string: The command key to hash.
    /// - Returns: A lowercase hexadecimal SHA-256 digest.
    public static func hash(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Normalizes output lines before fuzzy matching.
public enum LineNormalizer {
    /// Returns a copy of `text` with digit runs replaced by `N` and whitespace collapsed.
    ///
    /// The fallback line matcher uses this to match progress lines whose counters or
    /// spacing change across runs, such as `[3/100] Compiling Foo.swift`.
    ///
    /// - Parameter text: The output line to normalize.
    /// - Returns: A normalized output line.
    public static func normalized(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var lastWasSpace = false
        var lastWasDigit = false

        for character in text {
            if character.isNumber {
                if !lastWasDigit {
                    result.append("N")
                }
                lastWasSpace = false
                lastWasDigit = true
                continue
            }

            if character.isWhitespace {
                if !lastWasSpace {
                    result.append(" ")
                    lastWasSpace = true
                }
                lastWasDigit = false
            } else {
                result.append(character)
                lastWasSpace = false
                lastWasDigit = false
            }
        }

        return result.trimmingCharacters(in: .whitespaces)
    }
}

/// Creates privacy-preserving hashes for output lines.
public enum LineHash {
    /// MD5 is marked `Insecure` in CryptoKit because it's vulnerable to deliberate
    /// collision attacks — but that's irrelevant here. We use it as a one-way digest
    /// to avoid storing raw command output on disk. MD5 is not reversible (output can't
    /// be turned back into the original text), and collisions only cause a slightly
    /// inaccurate ETA — no security implications. Hardware-accelerated on Apple Silicon.
    ///
    /// - Parameter string: The output line to hash.
    /// - Returns: A lowercase hexadecimal MD5 digest.
    public static func hash(_ string: String) -> String {
        md5(string)
    }

    /// Returns an MD5 digest after normalizing the output line for fuzzy matching.
    ///
    /// - Parameter string: The output line to normalize and hash.
    /// - Returns: A lowercase hexadecimal MD5 digest.
    public static func normalizedHash(_ string: String) -> String {
        md5(LineNormalizer.normalized(string))
    }

    static func md5(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
