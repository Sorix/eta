import Foundation

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
    private let referenceTimeline: ReferenceTimeline
    private let lock = NSLock()

    /// Number of records already consumed from the append-only current log.
    private var processedCurrentLineCount = 0

    /// Baseline time minus current wall-clock time at the latest matched milestone.
    private var timelineOffset: Double = 0

    /// The furthest matched milestone as an index in the reference run.
    private var lastMatchedReferenceIndex = -1

    /// The furthest matched milestone as seconds on the baseline timeline.
    private var confirmedExpectedOffset: Double = 0

    /// Creates an estimator from optional command history.
    ///
    /// - Parameter history: Stored command history for the command currently running.
    public convenience init(history: CommandHistory?) {
        self.init(runs: history?.runs ?? [])
    }

    /// Creates an estimator from successful command runs.
    ///
    /// - Parameter runs: Successful runs ordered from oldest to newest.
    public init(runs: [CommandRun]) {
        self.referenceTimeline = ReferenceTimeline(runs: runs)
    }

    /// Whether the estimator has historical data to use.
    public var hasHistory: Bool {
        referenceTimeline.hasHistory
    }

    /// The weighted expected total duration before live timeline corrections.
    public var expectedTotalDuration: Double {
        referenceTimeline.expectedDuration
    }

    /// Returns a live estimate using the current cached log state.
    ///
    /// - Parameter elapsed: Seconds elapsed in the current command run.
    /// - Returns: Current progress and remaining-time estimate.
    public func estimate(elapsed: Double) -> ProgressEstimate {
        lock.lock()
        defer { lock.unlock() }
        return makeEstimate(elapsed: elapsed)
    }

    /// Updates the estimator from an accumulated append-only current log.
    ///
    /// The cache tracks how much of `currentLog` was already processed and resets if
    /// a shorter log is passed.
    ///
    /// - Parameters:
    ///   - currentLog: Append-only line records from the current command run.
    ///   - elapsed: Seconds elapsed in the current command run.
    /// - Returns: Current progress and remaining-time estimate.
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
    ///
    /// - Parameters:
    ///   - line: The line record observed in the current command run.
    ///   - elapsed: Optional elapsed time override. Defaults to `line.offsetSeconds`.
    /// - Returns: Current progress and remaining-time estimate.
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
        guard let match = referenceTimeline.match(line, after: lastMatchedReferenceIndex),
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
        guard referenceTimeline.expectedDuration > 0 else {
            return ProgressEstimate(
                progress: ProgressFill(confirmed: 0, predicted: 0),
                remainingTime: 0,
                adjustedExpectedTotalDuration: 0
            )
        }

        let virtualElapsed = max(0, elapsed + timelineOffset)
        let predictedElapsed = max(confirmedExpectedOffset, virtualElapsed)
        let confirmedProgress = confirmedExpectedOffset / referenceTimeline.expectedDuration
        let predictedProgress = predictedElapsed / referenceTimeline.expectedDuration
        let remainingTime = referenceTimeline.expectedDuration - predictedElapsed
        let adjustedExpectedTotalDuration = max(0, referenceTimeline.expectedDuration - timelineOffset)

        return ProgressEstimate(
            progress: ProgressFill(confirmed: confirmedProgress, predicted: predictedProgress),
            remainingTime: remainingTime,
            adjustedExpectedTotalDuration: adjustedExpectedTotalDuration
        )
    }
}
