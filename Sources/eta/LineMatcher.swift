import Foundation

/// Matches current output lines against historical runs to determine progress.
struct LineMatcher: Sendable {
    /// Historical lines from the best reference run, in order.
    let referenceLines: [LineRecord]

    /// Exact text hash → index in referenceLines (first occurrence)
    private let exactIndex: [String: Int]
    /// Normalized text hash → index in referenceLines (first occurrence)
    private let normalizedIndex: [String: Int]

    init(history: CommandHistory) {
        // Use the most recent complete run as reference, fall back to most recent.
        let refRun = history.runs.last(where: { $0.complete }) ?? history.runs.last
        let lines = refRun?.lines ?? []
        self.referenceLines = lines

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
    func match(text: String) -> Int? {
        let textHash = LineHash.md5(text)
        if let i = exactIndex[textHash] { return i }
        let normHash = LineHash.md5(CommandRunner.normalize(text))
        return normalizedIndex[normHash]
    }
}
