import Foundation

struct LineRecord: Codable, Sendable {
    let text: String
    let normalizedText: String
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
