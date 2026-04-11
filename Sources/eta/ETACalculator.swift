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

    /// Progress (0.0–1.0) based on the matched line index.
    func lineProgress(forMatchedIndex index: Int) -> Double {
        guard totalReferenceLines > 0 else { return 0 }
        return min(1.0, Double(index + 1) / Double(totalReferenceLines))
    }

    /// Time-based progress (0.0–1.0) from elapsed vs expected total.
    func timeProgress(elapsed: Double) -> Double {
        guard expectedTotal > 0 else { return 0 }
        return min(1.0, elapsed / expectedTotal)
    }

    /// Blended progress: use time-based for smooth animation,
    /// anchored by the last matched line so it doesn't run ahead.
    func progress(forMatchedIndex index: Int, elapsed: Double) -> Double {
        let timeProg = timeProgress(elapsed: elapsed)
        guard index >= 0, totalReferenceLines > 0 else { return timeProg }

        let lineProg = lineProgress(forMatchedIndex: index)

        // Don't let time-based progress exceed the next line's expected position
        // (prevents the bar from racing ahead of actual work)
        let nextLineProg = min(1.0, Double(index + 2) / Double(totalReferenceLines))

        return min(max(lineProg, timeProg), nextLineProg)
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
