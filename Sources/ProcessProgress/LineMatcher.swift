import Foundation

/// Matches current output lines against historical runs to determine progress.
public struct LineMatcher: Sendable {
    /// Historical lines from the best reference run, in order.
    public let referenceLines: [LineRecord]
    /// Duration of the run that provided referenceLines.
    public let referenceTotalDuration: Double

    /// Exact text hash -> indices in referenceLines.
    private let exactIndices: [String: [Int]]
    /// Normalized text hash -> indices in referenceLines.
    private let normalizedIndices: [String: [Int]]

    /// Creates a matcher from command history.
    ///
    /// - Parameter history: The history whose newest run should be used as the reference timeline.
    public init(history: CommandHistory) {
        self.init(runs: history.runs)
    }

    /// Creates a matcher from successful command runs.
    ///
    /// - Parameter runs: Successful runs ordered from oldest to newest.
    public init(runs: [CommandRun]) {
        let referenceRun = runs.last
        let referenceLines = referenceRun?.lineRecords ?? []
        self.referenceLines = referenceLines
        self.referenceTotalDuration = referenceRun?.totalDuration ?? 0

        var exact: [String: [Int]] = [:]
        var normalized: [String: [Int]] = [:]
        for (index, line) in referenceLines.enumerated() {
            exact[line.textHash, default: []].append(index)
            normalized[line.normalizedHash, default: []].append(index)
        }
        self.exactIndices = exact
        self.normalizedIndices = normalized
    }

    /// Matches output text against the reference run.
    ///
    /// - Parameters:
    ///   - text: The output text to match.
    ///   - previousIndex: The previous matched reference index. Matches must appear after this index.
    /// - Returns: The matching index in `referenceLines`, or `nil` when no later match exists.
    public func match(text: String, after previousIndex: Int = -1) -> Int? {
        let textHash = LineHash.hash(text)
        if let index = Self.firstCandidate(in: exactIndices[textHash], after: previousIndex) {
            return index
        }

        let normalizedHash = LineHash.normalizedHash(text)
        return Self.firstCandidate(in: normalizedIndices[normalizedHash], after: previousIndex)
    }

    /// Matches a pre-hashed line record against the reference run.
    ///
    /// - Parameters:
    ///   - line: The pre-hashed line record to match.
    ///   - previousIndex: The previous matched reference index. Matches must appear after this index.
    /// - Returns: The matching index in `referenceLines`, or `nil` when no later match exists.
    public func match(line: LineRecord, after previousIndex: Int = -1) -> Int? {
        if let index = Self.firstCandidate(in: exactIndices[line.textHash], after: previousIndex) {
            return index
        }

        return Self.firstCandidate(in: normalizedIndices[line.normalizedHash], after: previousIndex)
    }

    private static func firstCandidate(in indices: [Int]?, after previousIndex: Int) -> Int? {
        indices?.first { $0 > previousIndex }
    }
}
