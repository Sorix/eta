import CryptoKit
import Foundation

struct LineRecord: Codable, Sendable {
    let textHash: String
    let normalizedHash: String
    let offsetSeconds: Double
}

struct Run: Codable, Sendable {
    let date: Date
    let totalDuration: Double
    let complete: Bool
    let lines: [LineRecord]
}

struct CommandHistory: Codable, Sendable {
    var commandString: String
    var customName: String?
    var runs: [Run]
}

// MARK: - Hashing

enum LineHash {
    /// MD5 is marked `Insecure` in CryptoKit because it's vulnerable to deliberate
    /// collision attacks — but that's irrelevant here. We use it as a one-way digest
    /// to avoid storing raw command output on disk. MD5 is not reversible (output can't
    /// be turned back into the original text), and collisions only cause a slightly
    /// inaccurate ETA — no security implications. Hardware-accelerated on Apple Silicon.
    static func md5(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
