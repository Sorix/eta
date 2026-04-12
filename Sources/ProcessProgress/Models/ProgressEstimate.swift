/// A point-in-time view of the live progress timeline.
public struct ProgressEstimate: Sendable, Equatable {
    /// Progress split by confidence level.
    public let progress: ProgressFill

    /// Estimated seconds remaining from this snapshot, based on predicted progress.
    ///
    /// Negative means the current run has passed the adjusted expectation.
    public let remainingTime: Double

    /// The total wall-clock duration implied by the latest timeline correction.
    public let adjustedExpectedTotalDuration: Double

    /// Creates a progress estimate snapshot.
    ///
    /// - Parameters:
    ///   - progress: Progress split by confidence level.
    ///   - remainingTime: Estimated seconds remaining from this snapshot.
    ///   - adjustedExpectedTotalDuration: Total wall-clock duration implied by the latest timeline correction.
    public init(progress: ProgressFill, remainingTime: Double, adjustedExpectedTotalDuration: Double) {
        self.progress = progress
        self.remainingTime = remainingTime
        self.adjustedExpectedTotalDuration = adjustedExpectedTotalDuration
    }
}

/// Normalized progress values split by confidence level.
public struct ProgressFill: Sendable, Equatable {
    /// Backed by the furthest matched historical line.
    public let confirmed: Double

    /// Timer projection from the latest correction point.
    public let predicted: Double

    /// Creates normalized progress values.
    ///
    /// - Parameters:
    ///   - confirmed: Progress backed by the furthest matched historical line.
    ///   - predicted: Timer-projected progress.
    public init(confirmed: Double, predicted: Double) {
        self.confirmed = Self.clamp(confirmed)
        self.predicted = Self.clamp(max(confirmed, predicted))
    }

    private static func clamp(_ value: Double) -> Double {
        min(1.0, max(0, value))
    }
}
