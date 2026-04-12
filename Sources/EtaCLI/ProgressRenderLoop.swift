import Foundation
import ProcessProgress

final class ProgressRenderLoop: ProgressRenderLooping, @unchecked Sendable {
    private let timer: DispatchSourceTimer

    init(
        renderer: any ProgressRendering,
        estimator: TimelineProgressEstimator,
        startTime: Date,
        dateProvider: @escaping DateProvider
    ) {
        self.timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now() + 0.2, repeating: 0.2)
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
        timer.cancel()
    }
}
