import Foundation

/// Matches current output lines against historical runs to determine progress.
struct LineMatcher: Sendable {
    /// Historical lines from the best reference run, in order.
    let referenceLines: [LineRecord]

    /// Exact text → index in referenceLines (first occurrence)
    private let exactIndex: [String: Int]
    /// Normalized text → index in referenceLines (first occurrence)
    private let normalizedIndex: [String: Int]

    init(history: CommandHistory) {
        // Use the most recent complete run as reference, fall back to most recent.
        let refRun = history.runs.last(where: { $0.complete }) ?? history.runs.last
        let lines = refRun?.lines ?? []
        self.referenceLines = lines

        var exact: [String: Int] = [:]
        var normalized: [String: Int] = [:]
        for (i, line) in lines.enumerated() {
            // Keep first occurrence — earlier lines are better progress anchors.
            if exact[line.text] == nil {
                exact[line.text] = i
            }
            if normalized[line.normalizedText] == nil {
                normalized[line.normalizedText] = i
            }
        }
        self.exactIndex = exact
        self.normalizedIndex = normalized
    }

    /// Match a line against the reference. Returns the index in referenceLines, or nil.
    func match(text: String) -> Int? {
        if let i = exactIndex[text] { return i }
        let norm = CommandRunner.normalize(text)
        return normalizedIndex[norm]
    }
}
