import ProcessProgress

extension ProgressEstimate {
    var displayRemainingTime: Double? {
        adjustedExpectedTotalDuration > 0 ? remainingTime : nil
    }
}
