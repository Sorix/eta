import Foundation

/// Matches current output lines against historical runs to determine progress.
public struct LineMatcher: Sendable {
    /// Historical lines from the best reference run, in order.
    public let referenceLines: [LineRecord]
    /// Duration of the run that provided referenceLines.
    public let referenceTotalDuration: Double

    /// Exact text hash → index in referenceLines (first occurrence)
    private let exactIndex: [String: Int]
    /// Normalized text hash → index in referenceLines (first occurrence)
    private let normalizedIndex: [String: Int]

    public init(history: CommandHistory) {
        let refRun = history.runs.last
        let lines = refRun?.lines ?? []
        self.referenceLines = lines
        self.referenceTotalDuration = refRun?.totalDuration ?? 0

        var exact: [String: Int] = [:]
        var normalized: [String: Int] = [:]
        for (i, line) in lines.enumerated() {
            if exact[line.textHash] == nil {
                exact[line.textHash] = i
            }
            if normalized[line.normalizedHash] == nil {
                normalized[line.normalizedHash] = i
            }
        }
        self.exactIndex = exact
        self.normalizedIndex = normalized
    }

    /// Match a line against the reference. Returns the index in referenceLines, or nil.
    public func match(text: String) -> Int? {
        let textHash = LineHash.hash(text)
        if let i = exactIndex[textHash] { return i }
        let normHash = LineHash.normalizedHash(text)
        return normalizedIndex[normHash]
    }
}
