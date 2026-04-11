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
    /// at 3s, the tracker treats the run as 7s ahead. A baseline 20s run therefore
    /// has an adjusted expected total of 13s.
    public let adjustedExpectedTotal: Double

    public init(progress: Double, eta: Double, adjustedExpectedTotal: Double) {
        self.progress = progress
        self.eta = eta
        self.adjustedExpectedTotal = adjustedExpectedTotal
    }
}

/// Maintains the adaptive, live progress timeline for a running command.
///
/// `EstimateCalculator` provides a stable baseline: the weighted mean duration and
/// the historical output-line offsets from the reference run. This tracker owns the
/// mutable part: every time current output matches a historical line, it checks
/// where that line should have appeared on the baseline timeline and compares that
/// to the current elapsed time.
///
/// Example:
/// - Baseline total: 20s
/// - Historical line offset: 10s
/// - Current line arrives: 3s
///
/// The matched line means the current run has reached the 10s milestone after only
/// 3s. The tracker stores a `timelineOffset` of +7s and future snapshots use
/// `virtualElapsed = elapsed + timelineOffset`. Progress jumps to 50%, ETA becomes
/// 10s, and the adjusted expected total becomes 13s.
///
/// Only forward-moving matches are applied. Duplicate or older output lines are
/// ignored so they cannot drag the bar backwards. The progress value also keeps a
/// monotonic floor at the furthest matched milestone.
public final class AdaptiveProgressTracker: @unchecked Sendable {
    private let calculator: EstimateCalculator
    private let lock = NSLock()

    /// Difference between the baseline timeline and current wall-clock time.
    ///
    /// Positive means the command is ahead of history, negative means it is behind.
    private var timelineOffset: Double = 0

    /// The furthest matched milestone as normalized progress.
    private var progressFloor: Double = 0

    /// The furthest matched milestone as seconds on the baseline timeline.
    private var lastMatchedExpectedOffset: Double = 0

    public init(calculator: EstimateCalculator) {
        self.calculator = calculator
    }

    /// Returns a live estimate without changing tracker state.
    public func snapshot(elapsed: Double) -> ProgressEstimate {
        lock.lock()
        defer { lock.unlock() }
        return makeSnapshot(elapsed: elapsed)
    }

    /// Records one command output line and returns the corrected live estimate.
    ///
    /// When the line matches history, the tracker converts the reference line offset
    /// into the baseline timeline and shifts future snapshots around that milestone.
    /// Unknown lines simply return the current snapshot.
    @discardableResult
    public func observeLine(_ text: String, elapsed: Double) -> ProgressEstimate {
        lock.lock()
        defer { lock.unlock() }

        if let expectedOffset = calculator.expectedOffset(forLineMatching: text),
           expectedOffset > lastMatchedExpectedOffset {
            lastMatchedExpectedOffset = expectedOffset
            progressFloor = max(progressFloor, expectedOffset / calculator.expectedTotal)

            if expectedOffset > 0 {
                timelineOffset = expectedOffset - elapsed
            }
        }

        return makeSnapshot(elapsed: elapsed)
    }

    private func makeSnapshot(elapsed: Double) -> ProgressEstimate {
        guard calculator.expectedTotal > 0 else {
            return ProgressEstimate(progress: 0, eta: 0, adjustedExpectedTotal: 0)
        }

        let virtualElapsed = max(0, elapsed + timelineOffset)
        let progress = min(1.0, max(progressFloor, virtualElapsed / calculator.expectedTotal))
        let eta = calculator.expectedTotal - virtualElapsed
        let adjustedExpectedTotal = max(0, calculator.expectedTotal - timelineOffset)

        return ProgressEstimate(
            progress: progress,
            eta: eta,
            adjustedExpectedTotal: adjustedExpectedTotal
        )
    }
}
