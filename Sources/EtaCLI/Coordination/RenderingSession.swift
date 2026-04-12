import Foundation
import ProcessProgress

/// Owns the optional progress-rendering lifecycle for a single command run.
///
/// Construction starts the initial draw, timer, and signal trap when rendering is
/// active. `end(cleanupOnly:)` is idempotent so coordinator error paths can call it
/// without duplicating terminal cleanup.
struct RenderingSession {
    let isActive: Bool

    private let renderer: any ProgressRendering
    private let renderLoop: (any ProgressRenderLooping)?
    private let signalTrap: (any SignalTrapping)?
    private var didEnd = false

    init(
        renderer: any ProgressRendering,
        isActive: Bool,
        estimator: TimelineProgressEstimator,
        startTime: Date,
        dateProvider: @escaping DateProvider,
        renderLoopFactory: RenderLoopFactory,
        signalTrapFactory: SignalTrapFactory
    ) {
        self.renderer = renderer
        self.isActive = isActive

        guard isActive else {
            self.renderLoop = nil
            self.signalTrap = nil
            return
        }

        let estimate = estimator.estimate(elapsed: 0)
        renderer.forceUpdate(
            progress: estimate.progress,
            remainingTime: estimate.displayRemainingTime,
            elapsedTime: 0
        )

        let renderLoop = renderLoopFactory(ProgressRenderLoopConfiguration(
            renderer: renderer,
            estimator: estimator,
            startTime: startTime,
            dateProvider: dateProvider
        ))
        self.renderLoop = renderLoop
        self.signalTrap = signalTrapFactory {
            renderLoop.cancel()
            renderer.cleanup()
        }
    }

    /// Stops timer and signal handling; optionally clears any active terminal status.
    mutating func end(cleanupOnly: Bool) {
        guard !didEnd else { return }
        didEnd = true
        renderLoop?.cancel()
        signalTrap?.cancel()
        if cleanupOnly, isActive {
            renderer.cleanup()
        }
    }

    /// Prints the final success line when rendering was active.
    func finish(elapsed: Double, expectedDuration: Double) {
        guard isActive else { return }
        renderer.finish(elapsed: elapsed, expectedDuration: expectedDuration)
    }
}
