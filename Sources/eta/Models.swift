import Foundation

struct LineRecord: Codable, Sendable {
    let textHash: UInt64
    let normalizedHash: UInt64
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

// MARK: - FNV-1a 64-bit

/// Fast, deterministic, non-cryptographic hash. Stable across runs.
enum FNV1a {
    static func hash(_ string: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325  // FNV offset basis
        for byte in string.utf8 {
            h ^= UInt64(byte)
            h &*= 0x100000001b3             // FNV prime
        }
        return h
    }
}
