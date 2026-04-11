import Foundation

/// A point-in-time view of the live progress timeline.
public struct ProgressEstimate: Sendable, Equatable {
    /// Normalized progress for the bar, clamped to 0.0...1.0.
    public let progress: Double

    /// Estimated seconds remaining from this snapshot.
    ///
    /// A negative value means the current run has passed the adjusted expectation.
    /// The renderer may still display that as `0s`, but keeping the sign here makes
    /// the estimate useful for callers that want to distinguish "done soon" from
    /// "overdue".
    public let eta: Double

    /// The total wall-clock duration implied by the latest timeline correction.
    ///
    /// For example, if history expected a milestone at 10s and this run reaches it
    /// at 3s, the estimator treats the run as 7s ahead. A baseline 20s run
    /// therefore has an adjusted expected total of 13s.
    public let adjustedExpectedTotal: Double

    public init(progress: Double, eta: Double, adjustedExpectedTotal: Double) {
        self.progress = progress
        self.eta = eta
        self.adjustedExpectedTotal = adjustedExpectedTotal
    }
}

/// Estimates progress from two append-only data sources: the current run log and
/// archived historical runs.
///
/// The archived runs provide a baseline total duration and a reference output
/// timeline. The current log provides observed `LineRecord` values with their
/// actual offsets in the running command. Every estimate is derived from those two
/// inputs:
///
/// 1. Match new current log records against the reference run.
/// 2. Keep the furthest matched reference milestone.
/// 3. Compare that milestone's expected offset with its current offset.
/// 4. Shift the live time axis by that difference.
///
/// Example:
/// - Baseline total: 20s
/// - Historical line offset: 10s
/// - Current line arrives: 3s
///
/// The matched line means the current run has reached the 10s milestone after only
/// 3s. The estimator stores a `timelineOffset` of +7s and future snapshots use
/// `virtualElapsed = elapsed + timelineOffset`. Progress jumps to 50%, ETA becomes
/// 10s, and the adjusted expected total becomes 13s.
///
/// Late milestones work the same way in the other direction. If that same 10s
/// historical line arrives after 30s, the estimator stores a `timelineOffset` of
/// -20s. Progress moves back to the known 50% milestone, ETA returns to 10s, and
/// the adjusted expected total becomes 40s.
///
/// Matches are only accepted when they move forward through the reference output.
/// Duplicate or older historical lines are ignored because they are usually repeats
/// or out-of-order output. That ordering guard does not make visual progress
/// monotonic: a late but newer milestone is allowed to move the bar backwards when
/// it reveals that the previous time-based estimate was too optimistic.
///
/// This class is stateful for performance, not because the calculation needs
/// hidden process state. Tests can build it from `archiveRuns`, feed an append-only
/// `currentLog`, and assert on returned `ProgressEstimate` values. Internally it
/// remembers how many current log records were already scanned, so repeated calls
/// only inspect the new suffix instead of rescanning thousands of lines.
public final class TimelineProgressEstimator: @unchecked Sendable {
    private let calculator: EstimateCalculator
    private let lock = NSLock()

    /// Number of records already consumed from the append-only current log.
    private var processedCurrentLineCount = 0

    /// Difference between the baseline timeline and current wall-clock time.
    ///
    /// Positive means the command is ahead of history, negative means it is behind.
    private var timelineOffset: Double = 0

    /// The furthest matched milestone as an index in the reference run.
    private var lastMatchedReferenceIndex = -1

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
    /// This is the most test-friendly entry point: construct historical `Run`
    /// values, construct current `LineRecord` values, and call this method with the
    /// current log as it grows. The estimator caches `processedCurrentLineCount`, so
    /// each call scans only records that were not seen before. If the provided log
    /// shrinks, the current-log cache is reset and the new log is processed from the
    /// beginning.
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
    /// CLI code uses this path because it receives output incrementally and does not
    /// need to pass the whole current log back on every line. Tests can still use it
    /// directly when they want to model the same streaming behavior.
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
        timelineOffset = match.expectedOffset - max(0, line.offsetSeconds)
    }

    private func resetCurrentLogState() {
        processedCurrentLineCount = 0
        timelineOffset = 0
        lastMatchedReferenceIndex = -1
    }

    private func makeEstimate(elapsed: Double) -> ProgressEstimate {
        guard calculator.expectedTotal > 0 else {
            return ProgressEstimate(progress: 0, eta: 0, adjustedExpectedTotal: 0)
        }

        let virtualElapsed = max(0, elapsed + timelineOffset)
        let progress = min(1.0, virtualElapsed / calculator.expectedTotal)
        let eta = calculator.expectedTotal - virtualElapsed
        let adjustedExpectedTotal = max(0, calculator.expectedTotal - timelineOffset)

        return ProgressEstimate(
            progress: progress,
            eta: eta,
            adjustedExpectedTotal: adjustedExpectedTotal
        )
    }
}
