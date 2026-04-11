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

    public init(history: CommandHistory) {
        self.init(runs: history.runs)
    }

    public init(runs: [Run]) {
        let refRun = runs.last
        let lines = refRun?.lines ?? []
        self.referenceLines = lines
        self.referenceTotalDuration = refRun?.totalDuration ?? 0

        var exact: [String: [Int]] = [:]
        var normalized: [String: [Int]] = [:]
        for (i, line) in lines.enumerated() {
            exact[line.textHash, default: []].append(i)
            normalized[line.normalizedHash, default: []].append(i)
        }
        self.exactIndices = exact
        self.normalizedIndices = normalized
    }

    /// Match a line against the reference. Returns the index in referenceLines, or nil.
    public func match(text: String) -> Int? {
        match(text: text, after: -1)
    }

    /// Match a line against the reference after a previous reference index.
    public func match(text: String, after previousIndex: Int) -> Int? {
        let textHash = LineHash.hash(text)
        if let i = Self.firstCandidate(in: exactIndices[textHash], after: previousIndex) {
            return i
        }
        let normHash = LineHash.normalizedHash(text)
        return Self.firstCandidate(in: normalizedIndices[normHash], after: previousIndex)
    }

    /// Match a pre-hashed line record against the reference. Returns the index in
    /// referenceLines, or nil.
    public func match(line: LineRecord) -> Int? {
        match(line: line, after: -1)
    }

    /// Match a pre-hashed line record after a previous reference index.
    public func match(line: LineRecord, after previousIndex: Int) -> Int? {
        if let i = Self.firstCandidate(in: exactIndices[line.textHash], after: previousIndex) {
            return i
        }
        return Self.firstCandidate(in: normalizedIndices[line.normalizedHash], after: previousIndex)
    }

    private static func firstCandidate(in indices: [Int]?, after previousIndex: Int) -> Int? {
        indices?.first { $0 > previousIndex }
    }
}
