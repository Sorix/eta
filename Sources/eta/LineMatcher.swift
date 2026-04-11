import Foundation

/// Matches current output lines against historical runs to determine progress.
struct LineMatcher: Sendable {
    /// Historical lines from the best reference run, in order.
    let referenceLines: [LineRecord]

    /// Exact text hash → index in referenceLines (first occurrence)
    private let exactIndex: [UInt64: Int]
    /// Normalized text hash → index in referenceLines (first occurrence)
    private let normalizedIndex: [UInt64: Int]

    init(history: CommandHistory) {
        // Use the most recent complete run as reference, fall back to most recent.
        let refRun = history.runs.last(where: { $0.complete }) ?? history.runs.last
        let lines = refRun?.lines ?? []
        self.referenceLines = lines

        var exact: [UInt64: Int] = [:]
        var normalized: [UInt64: Int] = [:]
        for (i, line) in lines.enumerated() {
            // Keep first occurrence — earlier lines are better progress anchors.
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
    func match(text: String) -> Int? {
        let textHash = FNV1a.hash(text)
        if let i = exactIndex[textHash] { return i }
        let normHash = FNV1a.hash(CommandRunner.normalize(text))
        return normalizedIndex[normHash]
    }
}
