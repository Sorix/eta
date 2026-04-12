import Foundation
import ProcessProgress

final class ProgressRenderLoop: ProgressRenderLooping, @unchecked Sendable {
    private static let frameInterval: TimeInterval = 0.032

    private let timer: DispatchSourceTimer
    private let lock = NSLock()
    private var isCancelled = false

    init(
        renderer: any ProgressRendering,
        estimator: TimelineProgressEstimator,
        startTime: Date,
        dateProvider: @escaping DateProvider
    ) {
        self.timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now() + Self.frameInterval, repeating: Self.frameInterval)
        timer.setEventHandler { [renderer, estimator, startTime, dateProvider] in
            let elapsed = dateProvider().timeIntervalSince(startTime)
            let estimate = estimator.estimate(elapsed: elapsed)
            renderer.update(
                progress: estimate.progress,
                remainingTime: estimate.adjustedExpectedTotalDuration > 0 ? estimate.remainingTime : nil,
                elapsedTime: elapsed
            )
        }
        timer.resume()
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return }
        isCancelled = true
        timer.cancel()
    }
}
