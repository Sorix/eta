import Foundation

/// A point-in-time view of the live progress timeline.
public struct ProgressEstimate: Sendable, Equatable {
    /// Progress split by confidence level.
    public let progress: ProgressFill

    /// Estimated seconds remaining from this snapshot, based on predicted progress.
    ///
    /// Negative means the current run has passed the adjusted expectation.
    public let eta: Double

    /// The total wall-clock duration implied by the latest timeline correction.
    public let adjustedExpectedTotal: Double

    public init(progress: ProgressFill, eta: Double, adjustedExpectedTotal: Double) {
        self.progress = progress
        self.eta = eta
        self.adjustedExpectedTotal = adjustedExpectedTotal
    }
}

/// Normalized progress values split by confidence level.
public struct ProgressFill: Sendable, Equatable {
    /// Backed by the furthest matched historical line.
    public let confirmed: Double

    /// Timer projection from the latest correction point.
    public let predicted: Double

    public init(confirmed: Double, predicted: Double) {
        self.confirmed = Self.clamp(confirmed)
        self.predicted = Self.clamp(max(confirmed, predicted))
    }

    private static func clamp(_ value: Double) -> Double {
        min(1.0, max(0, value))
    }
}

/// Estimates progress from historical runs plus the append-only current run log.
///
/// Historical runs define a baseline timeline. Current log records confirm
/// milestones on that timeline. The estimator keeps a small cache so repeated calls
/// only scan new current records.
///
/// Progress has two parts:
/// - confirmed: the furthest matched historical milestone
/// - predicted: timer progress from the latest timeline correction
///
/// If a 10s historical milestone arrives at 3s, future estimates are shifted 7s
/// ahead. If it arrives at 30s, they are shifted 20s behind. Newer milestones may
/// move progress backward when the command is slower than expected.
public final class TimelineProgressEstimator: @unchecked Sendable {
    private let calculator: EstimateCalculator
    private let lock = NSLock()

    /// Number of records already consumed from the append-only current log.
    private var processedCurrentLineCount = 0

    /// Baseline time minus current wall-clock time at the latest matched milestone.
    private var timelineOffset: Double = 0

    /// The furthest matched milestone as an index in the reference run.
    private var lastMatchedReferenceIndex = -1

    /// The furthest matched milestone as seconds on the baseline timeline.
    private var confirmedExpectedOffset: Double = 0

    public convenience init(history: CommandHistory?) {
        self.init(archiveRuns: history?.runs ?? [])
    }

    public init(archiveRuns: [Run]) {
        self.calculator = EstimateCalculator(runs: archiveRuns)
    }

    public var hasArchive: Bool {
        calculator.hasHistory
    }

    public var expectedTotal: Double {
        calculator.expectedTotal
    }

    /// Returns a live estimate using the current cached log state.
    public func estimate(elapsed: Double) -> ProgressEstimate {
        lock.lock()
        defer { lock.unlock() }
        return makeEstimate(elapsed: elapsed)
    }

    /// Updates the estimator from an append-only current log and returns an estimate.
    ///
    /// This is the test-friendly API. The cache tracks how much of `currentLog` was
    /// already processed and resets if a shorter log is passed.
    @discardableResult
    public func estimate(currentLog: [LineRecord], elapsed: Double) -> ProgressEstimate {
        lock.lock()
        defer { lock.unlock() }

        if currentLog.count < processedCurrentLineCount {
            resetCurrentLogState()
        }

        for line in currentLog.dropFirst(processedCurrentLineCount) {
            observeCurrentLineWithoutLock(line)
        }
        processedCurrentLineCount = currentLog.count

        return makeEstimate(elapsed: elapsed)
    }

    /// Adds one current log record and returns an estimate.
    @discardableResult
    public func observeCurrentLine(_ line: LineRecord, elapsed: Double? = nil) -> ProgressEstimate {
        lock.lock()
        defer { lock.unlock() }

        observeCurrentLineWithoutLock(line)
        processedCurrentLineCount += 1
        return makeEstimate(elapsed: elapsed ?? line.offsetSeconds)
    }

    /// Clears the cached current log position and any timeline correction.
    ///
    /// Use this when switching to a different current log with the same estimator.
    public func resetCurrentLog() {
        lock.lock()
        defer { lock.unlock() }
        resetCurrentLogState()
    }

    private func observeCurrentLineWithoutLock(_ line: LineRecord) {
        guard let match = calculator.referenceMatch(for: line),
              match.index > lastMatchedReferenceIndex else {
            return
        }

        lastMatchedReferenceIndex = match.index
        confirmedExpectedOffset = match.expectedOffset
        timelineOffset = match.expectedOffset - max(0, line.offsetSeconds)
    }

    private func resetCurrentLogState() {
        processedCurrentLineCount = 0
        timelineOffset = 0
        lastMatchedReferenceIndex = -1
        confirmedExpectedOffset = 0
    }

    private func makeEstimate(elapsed: Double) -> ProgressEstimate {
        guard calculator.expectedTotal > 0 else {
            return ProgressEstimate(
                progress: ProgressFill(confirmed: 0, predicted: 0),
                eta: 0,
                adjustedExpectedTotal: 0
            )
        }

        let virtualElapsed = max(0, elapsed + timelineOffset)
        let predictedElapsed = max(confirmedExpectedOffset, virtualElapsed)
        let confirmedProgress = confirmedExpectedOffset / calculator.expectedTotal
        let predictedProgress = predictedElapsed / calculator.expectedTotal
        let eta = calculator.expectedTotal - predictedElapsed
        let adjustedExpectedTotal = max(0, calculator.expectedTotal - timelineOffset)

        return ProgressEstimate(
            progress: ProgressFill(confirmed: confirmedProgress, predicted: predictedProgress),
            eta: eta,
            adjustedExpectedTotal: adjustedExpectedTotal
        )
    }
}
