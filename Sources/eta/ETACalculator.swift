import Foundation

/// Calculates expected total duration and current progress from history.
struct ETACalculator: Sendable {
    let expectedTotal: Double
    let hasHistory: Bool
    private let matcher: LineMatcher
    private let totalReferenceLines: Int

    init(history: CommandHistory?) {
        guard let history, !history.runs.isEmpty else {
            self.expectedTotal = 0
            self.hasHistory = false
            self.matcher = LineMatcher(history: CommandHistory(commandString: "", runs: []))
            self.totalReferenceLines = 0
            return
        }

        self.hasHistory = true
        self.matcher = LineMatcher(history: history)
        self.totalReferenceLines = matcher.referenceLines.count
        self.expectedTotal = Self.weightedMeanDuration(runs: history.runs)
    }

    /// Smooth time-based progress (0.0–1.0) from elapsed vs expected total.
    func progress(elapsed: Double) -> Double {
        guard expectedTotal > 0 else { return 0 }
        return min(1.0, elapsed / expectedTotal)
    }

    /// ETA in seconds from now. Negative means overdue.
    func eta(elapsed: Double) -> Double {
        expectedTotal - elapsed
    }

    /// Match a line against history.
    func matchLine(_ text: String) -> Int? {
        matcher.match(text: text)
    }

    // MARK: - Exponential Weighted Mean

    /// Compute exponential weighted mean of run durations.
    /// More recent runs get higher weight. α = 0.3 (recent bias).
    private static func weightedMeanDuration(runs: [Run]) -> Double {
        let completedRuns = runs.filter { $0.complete }
        guard !completedRuns.isEmpty else {
            // Fall back to all runs if none are marked complete.
            return runs.last?.totalDuration ?? 0
        }

        let alpha = 0.3
        var weight = 1.0
        var totalWeight = 0.0
        var weightedSum = 0.0

        // Iterate from most recent to oldest.
        for run in completedRuns.reversed() {
            weightedSum += run.totalDuration * weight
            totalWeight += weight
            weight *= (1.0 - alpha)
        }

        return weightedSum / totalWeight
    }
}
