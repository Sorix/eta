import Foundation

/// Baseline timeline derived from stored successful runs.
struct ReferenceLineMatch: Sendable, Equatable {
    let index: Int
    let expectedOffset: Double
}

/// Computes the weighted expected duration and maps current lines onto the reference run.
struct ReferenceTimeline: Sendable {
    let expectedDuration: Double
    let hasHistory: Bool

    private let matcher: LineMatcher

    init(history: CommandHistory?) {
        self.init(runs: history?.runs ?? [])
    }

    init(runs: [CommandRun]) {
        guard !runs.isEmpty else {
            self.expectedDuration = 0
            self.hasHistory = false
            self.matcher = LineMatcher(runs: [])
            return
        }

        self.hasHistory = true
        self.matcher = LineMatcher(runs: runs)
        self.expectedDuration = Self.weightedMeanDuration(runs: runs)
    }

    func match(_ line: LineRecord, after previousIndex: Int = -1) -> ReferenceLineMatch? {
        guard let index = matcher.match(line: line, after: previousIndex),
              matcher.referenceLines.indices.contains(index),
              expectedDuration > 0 else {
            return nil
        }

        let referenceLine = matcher.referenceLines[index]
        guard matcher.referenceTotalDuration > 0 else {
            return ReferenceLineMatch(
                index: index,
                expectedOffset: min(expectedDuration, max(0, referenceLine.offsetSeconds))
            )
        }

        let referenceProgress = min(1.0, max(0, referenceLine.offsetSeconds / matcher.referenceTotalDuration))
        return ReferenceLineMatch(index: index, expectedOffset: referenceProgress * expectedDuration)
    }

    private static func weightedMeanDuration(runs: [CommandRun]) -> Double {
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
