import Foundation
import ProcessProgress

// Narrow dependencies keep CommandRunCoordinator focused on workflow and make the
// terminal/process/signal pieces replaceable in tests.
typealias DateProvider = @Sendable () -> Date
typealias RendererFactory = @Sendable (BarColor, ProgressBarStyle) -> any ProgressRendering
typealias RenderLoopFactory = @Sendable (ProgressRenderLoopConfiguration) -> any ProgressRenderLooping
typealias SignalTrapFactory = @Sendable (@escaping @Sendable () -> Void) -> any SignalTrapping

struct ProgressRenderLoopConfiguration: Sendable {
    let renderer: any ProgressRendering
    let estimator: TimelineProgressEstimator
    let startTime: Date
    let dateProvider: DateProvider
}

protocol HistoryStoring {
    func load(for command: String) throws -> CommandHistory?
    func save(
        _ history: CommandHistory,
        for command: String,
        maximumRunCount: Int,
        staleAfterDays: Int
    ) throws
    func clear(for command: String) throws
    func clearAll() throws
}

extension HistoryStore: HistoryStoring {}

protocol CommandRunning {
    func run(_ command: String, outputHandler: CommandOutputHandler?) throws -> CommandOutput
}

extension CommandRunner: CommandRunning {}

protocol ProgressRendering: AnyObject, Sendable {
    var isEnabled: Bool { get }

    func writeFirstRunHeader()
    func update(progress: ProgressFill, remainingTime: Double?, elapsedTime: Double)
    func forceUpdate(progress: ProgressFill, remainingTime: Double?, elapsedTime: Double)
    func writeOutputAndRedraw(
        rawOutput: Data,
        stream: CommandOutputStream,
        progress: ProgressFill,
        remainingTime: Double?,
        elapsedTime: Double,
        containsPartialLine: Bool
    )
    func cleanup()
    func finish(elapsed: Double, expectedDuration: Double)
}

protocol ProgressRenderLooping: Sendable {
    func cancel()
}

protocol SignalTrapping: Sendable {
    func cancel()
}
