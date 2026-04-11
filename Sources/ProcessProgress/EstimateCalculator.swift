import Foundation

/// A current line matched to a reference line on the baseline timeline.
public struct ReferenceLineMatch: Sendable, Equatable {
    /// Index of the matched line in the reference run.
    public let index: Int

    /// Where that reference line should appear on the weighted baseline timeline.
    public let expectedOffset: Double

    public init(index: Int, expectedOffset: Double) {
        self.index = index
        self.expectedOffset = expectedOffset
    }
}

/// Calculates the baseline expected duration and reference offsets from history.
public struct EstimateCalculator: Sendable {
    public let expectedTotal: Double
    public let hasHistory: Bool
    private let matcher: LineMatcher

    public init(history: CommandHistory?) {
        self.init(runs: history?.runs ?? [])
    }

    public init(runs: [Run]) {
        guard !runs.isEmpty else {
            self.expectedTotal = 0
            self.hasHistory = false
            self.matcher = LineMatcher(runs: [])
            return
        }

        self.hasHistory = true
        self.matcher = LineMatcher(runs: runs)
        self.expectedTotal = Self.weightedMeanDuration(runs: runs)
    }

    /// Smooth time-based progress (0.0–1.0) from elapsed vs expected total.
    public func progress(elapsed: Double) -> Double {
        guard expectedTotal > 0 else { return 0 }
        return min(1.0, elapsed / expectedTotal)
    }

    /// ETA in seconds from now. Negative means overdue.
    public func eta(elapsed: Double) -> Double {
        expectedTotal - elapsed
    }

    /// Match a line against history.
    public func matchLine(_ text: String) -> Int? {
        matcher.match(text: text)
    }

    /// Match a pre-hashed line record against history.
    public func matchLine(_ line: LineRecord) -> Int? {
        matcher.match(line: line)
    }

    func referenceMatch(for line: LineRecord) -> ReferenceLineMatch? {
        guard let index = matcher.match(line: line),
              matcher.referenceLines.indices.contains(index),
              expectedTotal > 0 else {
            return nil
        }

        let line = matcher.referenceLines[index]
        guard matcher.referenceTotalDuration > 0 else {
            return ReferenceLineMatch(
                index: index,
                expectedOffset: min(expectedTotal, max(0, line.offsetSeconds))
            )
        }

        let referenceProgress = min(1.0, max(0, line.offsetSeconds / matcher.referenceTotalDuration))
        return ReferenceLineMatch(
            index: index,
            expectedOffset: referenceProgress * expectedTotal
        )
    }

    // MARK: - Exponential Weighted Mean

    /// Compute exponential weighted mean of run durations.
    /// More recent runs get higher weight. α = 0.3 (recent bias).
    private static func weightedMeanDuration(runs: [Run]) -> Double {
        guard !runs.isEmpty else { return 0 }

        let alpha = 0.3
        var weight = 1.0
        var totalWeight = 0.0
        var weightedSum = 0.0

        for run in runs.reversed() {
            weightedSum += run.totalDuration * weight
            totalWeight += weight
            weight *= (1.0 - alpha)
        }

        return weightedSum / totalWeight
    }
}
