import Foundation
@testable import EtaCLI
@testable import ProcessProgress
import Testing

@Suite("Command run coordinator")
struct CommandRunCoordinatorTests {
    @Test("successful command saves history with request settings")
    func successfulCommandSavesHistory() throws {
        let harness = CoordinatorHarness()
        harness.commandRunner.output = CommandOutput(
            lineRecords: [makeLine("Done", offset: 1)],
            totalDuration: 1,
            exitCode: 0
        )

        try harness.coordinator.run(harness.request(maximumRunCount: 3, color: .magenta, progressBarStyle: .solid))

        let saved = try #require(harness.historyStore.saved.first)
        #expect(harness.historyStore.loadCommands == ["alias"])
        #expect(saved.command == "alias")
        #expect(saved.maximumRunCount == 3)
        #expect(saved.history.runs.count == 1)
        #expect(saved.history.runs.first?.lineRecords.count == 1)
        #expect(harness.capturedColor == .magenta)
        #expect(harness.capturedStyle == .solid)
    }

    @Test("successful command appends to existing history")
    func successfulCommandAppendsToExistingHistory() throws {
        let harness = CoordinatorHarness()
        harness.historyStore.loadedHistory = makeHistory()
        harness.commandRunner.output = CommandOutput(lineRecords: [makeLine("Done")], totalDuration: 2, exitCode: 0)

        try harness.coordinator.run(harness.request())

        let saved = try #require(harness.historyStore.saved.first)
        #expect(saved.history.runs.count == 2)
        #expect(saved.history.runs.map(\.totalDuration) == [10, 2])
        #expect(saved.history.runs.last?.date == Date(timeIntervalSince1970: 100))
    }

    @Test("non-zero command exits without saving history")
    func nonZeroCommandDoesNotSaveHistory() {
        let harness = CoordinatorHarness()
        harness.commandRunner.output = CommandOutput(lineRecords: [makeLine("failed")], totalDuration: 1, exitCode: 42)
        var didThrow = false

        do {
            try harness.coordinator.run(harness.request())
        } catch {
            didThrow = true
        }

        #expect(didThrow)
        #expect(harness.historyStore.saved.isEmpty)
    }

    @Test("quiet mode bypasses rendering and still records history")
    func quietModeBypassesRendering() throws {
        let harness = CoordinatorHarness()
        harness.historyStore.loadedHistory = makeHistory()
        harness.commandRunner.output = CommandOutput(lineRecords: [makeLine("Done")], totalDuration: 1, exitCode: 0)

        try harness.coordinator.run(harness.request(quiet: true))

        #expect(!harness.commandRunner.receivedOutputHandler)
        #expect(harness.renderer.events.isEmpty)
        #expect(harness.renderLoopCreateCount == 0)
        #expect(harness.signalTrapCreateCount == 0)
        #expect(harness.historyStore.saved.count == 1)
    }

    @Test("disabled renderer skips rendering even with history")
    func disabledRendererSkipsRenderingEvenWithHistory() throws {
        let harness = CoordinatorHarness()
        harness.historyStore.loadedHistory = makeHistory()
        harness.renderer.isEnabled = false
        harness.commandRunner.output = CommandOutput(lineRecords: [makeLine("Done")], totalDuration: 1, exitCode: 0)

        try harness.coordinator.run(harness.request())

        #expect(!harness.commandRunner.receivedOutputHandler)
        #expect(harness.renderer.events.isEmpty)
        #expect(harness.renderLoopCreateCount == 0)
        #expect(harness.signalTrapCreateCount == 0)
        #expect(harness.historyStore.saved.count == 1)
    }

    @Test("no history renders elapsed status without ETA")
    func noHistoryRendersElapsedStatusWithoutETA() throws {
        let harness = CoordinatorHarness()
        harness.commandRunner.chunks = [
            CommandOutputChunk(
                rawOutput: Data("Done\n".utf8),
                lineRecords: [makeLine("Done", offset: 1)],
                stream: .standardOutput,
                containsPartialLine: false
            )
        ]
        harness.commandRunner.output = CommandOutput(lineRecords: [makeLine("Done")], totalDuration: 1, exitCode: 0)

        try harness.coordinator.run(harness.request())

        #expect(harness.commandRunner.receivedOutputHandler)
        #expect(harness.renderer.events == ["forceUpdate", "writeOutputAndRedraw", "finish"])
        #expect(harness.renderer.remainingTimes == [nil, nil])
        #expect(harness.renderer.elapsedTimes == [0, 0])
        #expect(harness.renderLoopCreateCount == 1)
        #expect(harness.signalTrapCreateCount == 1)
        #expect(harness.renderLoop.cancelCount == 1)
        #expect(harness.signalTrap.cancelCount == 1)
    }

    @Test("existing history enables render loop and rendering lifecycle")
    func existingHistoryEnablesRenderLoop() throws {
        let harness = CoordinatorHarness()
        harness.historyStore.loadedHistory = makeHistory()
        harness.commandRunner.chunks = [
            CommandOutputChunk(
                rawOutput: Data("Compile\n".utf8),
                lineRecords: [makeLine("Compile", offset: 1)],
                stream: .standardOutput,
                containsPartialLine: false
            )
        ]
        harness.commandRunner.output = CommandOutput(lineRecords: [makeLine("Compile", offset: 1)], totalDuration: 1, exitCode: 0)

        try harness.coordinator.run(harness.request())

        #expect(harness.commandRunner.receivedOutputHandler)
        #expect(harness.renderLoopCreateCount == 1)
        #expect(harness.signalTrapCreateCount == 1)
        #expect(harness.renderLoop.cancelCount == 1)
        #expect(harness.signalTrap.cancelCount == 1)
        #expect(harness.renderer.events == ["forceUpdate", "writeOutputAndRedraw", "finish"])
    }

    @Test("runner failure cleans up active rendering lifecycle")
    func runnerFailureCleansUpActiveRenderingLifecycle() {
        let harness = CoordinatorHarness()
        harness.historyStore.loadedHistory = makeHistory()
        harness.commandRunner.error = FakeError.runFailed
        var didThrow = false

        do {
            try harness.coordinator.run(harness.request())
        } catch {
            didThrow = true
        }

        #expect(didThrow)
        #expect(harness.historyStore.saved.isEmpty)
        #expect(harness.renderLoop.cancelCount == 1)
        #expect(harness.signalTrap.cancelCount == 1)
        #expect(harness.renderer.events == ["forceUpdate", "cleanup"])
    }

    @Test("save failure writes warning without failing successful command")
    func saveFailureWritesWarning() throws {
        let harness = CoordinatorHarness()
        harness.historyStore.saveError = FakeError.saveFailed
        harness.commandRunner.output = CommandOutput(lineRecords: [makeLine("Done")], totalDuration: 1, exitCode: 0)

        try harness.coordinator.run(harness.request())

        #expect(harness.warnings.all.count == 1)
        #expect(harness.warnings.all.first?.contains("failed to save history") == true)
    }
}
