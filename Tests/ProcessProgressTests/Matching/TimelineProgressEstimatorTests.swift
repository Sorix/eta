import Foundation
@testable import ProcessProgress
import Testing

struct ProgressFillCase: Sendable {
    let confirmed: Double
    let predicted: Double
    let expectedConfirmed: Double
    let expectedPredicted: Double
}

@Suite("Progress fill")
struct ProgressFillTests {
    @Test("clamps progress and keeps prediction at or above confirmed progress", arguments: [
        ProgressFillCase(confirmed: -1, predicted: -1, expectedConfirmed: 0, expectedPredicted: 0),
        ProgressFillCase(confirmed: 0.7, predicted: 0.2, expectedConfirmed: 0.7, expectedPredicted: 0.7),
        ProgressFillCase(confirmed: 0.5, predicted: 1.5, expectedConfirmed: 0.5, expectedPredicted: 1),
        ProgressFillCase(confirmed: 2, predicted: 0.5, expectedConfirmed: 1, expectedPredicted: 1),
    ])
    func clampsProgress(_ testCase: ProgressFillCase) {
        let progress = ProgressFill(confirmed: testCase.confirmed, predicted: testCase.predicted)

        #expect(progress.confirmed == testCase.expectedConfirmed)
        #expect(progress.predicted == testCase.expectedPredicted)
    }
}

@Suite("Timeline progress estimator")
struct TimelineProgressEstimatorTests {
    @Test("returns empty estimate without history")
    func returnsEmptyEstimateWithoutHistory() {
        let estimator = TimelineProgressEstimator(history: nil)
        let estimate = estimator.estimate(elapsed: 10)

        #expect(!estimator.hasHistory)
        #expect(estimator.expectedTotalDuration == 0)
        #expect(estimate.progress == ProgressFill(confirmed: 0, predicted: 0))
        #expect(estimate.remainingTime == 0)
    }

    @Test("weights recent runs more heavily")
    func weightsRecentRunsMoreHeavily() {
        let oldRun = CommandRun(date: Date(), totalDuration: 100, lineRecords: [makeLine("old", offset: 100)])
        let newRun = CommandRun(date: Date(), totalDuration: 10, lineRecords: [makeLine("new", offset: 10)])
        let estimator = TimelineProgressEstimator(runs: [oldRun, newRun])

        let expected = (10.0 + 100.0 * 0.7) / 1.7
        #expect(abs(estimator.expectedTotalDuration - expected) < 0.000_001)
    }

    @Test("advances confirmed progress from matched lines and clamps prediction")
    func advancesConfirmedProgressAndClampsPrediction() {
        let referenceLines = [
            makeLine("Configure", offset: 2),
            makeLine("Compile", offset: 5),
            makeLine("Done", offset: 10),
        ]
        let estimator = TimelineProgressEstimator(runs: [
            CommandRun(date: Date(), totalDuration: 10, lineRecords: referenceLines)
        ])

        let compileEstimate = estimator.observeCurrentLine(makeLine("Compile", offset: 1), elapsed: 1)
        #expect(compileEstimate.progress.confirmed == 0.5)
        #expect(compileEstimate.progress.predicted >= compileEstimate.progress.confirmed)

        let laterEstimate = estimator.estimate(elapsed: 100)
        #expect(laterEstimate.progress.predicted == 1)
        #expect(laterEstimate.remainingTime == -94)

        estimator.resetCurrentLog()
        let resetEstimate = estimator.estimate(elapsed: 0)
        #expect(resetEstimate.progress.confirmed == 0)
    }

    @Test("append-only current log cache resets when a shorter log is supplied")
    func currentLogCacheResetsForShorterLog() {
        let referenceLines = [
            makeLine("Step 1", offset: 1),
            makeLine("Step 2", offset: 2),
        ]
        let estimator = TimelineProgressEstimator(runs: [
            CommandRun(date: Date(), totalDuration: 2, lineRecords: referenceLines)
        ])

        _ = estimator.estimate(currentLog: referenceLines, elapsed: 2)
        let resetEstimate = estimator.estimate(currentLog: [referenceLines[0]], elapsed: 1)

        #expect(resetEstimate.progress.confirmed == 0.5)
    }

    @Test("slow observed milestones extend adjusted expected duration")
    func slowObservedMilestonesExtendAdjustedExpectedDuration() {
        let estimator = TimelineProgressEstimator(runs: [
            CommandRun(date: Date(), totalDuration: 10, lineRecords: [
                makeLine("Halfway", offset: 5),
                makeLine("Done", offset: 10),
            ])
        ])

        let estimate = estimator.observeCurrentLine(makeLine("Halfway", offset: 20), elapsed: 20)

        #expect(estimate.progress.confirmed == 0.5)
        #expect(estimate.remainingTime == 5)
        #expect(estimate.adjustedExpectedTotalDuration == 25)
    }
}

@Suite("Reference timeline")
struct ReferenceTimelineTests {
    @Test("scales reference line offsets onto weighted expected duration")
    func scalesReferenceLineOffsetsOntoWeightedExpectedDuration() throws {
        let timeline = ReferenceTimeline(runs: [
            CommandRun(date: Date(), totalDuration: 20, lineRecords: [makeLine("old", offset: 20)]),
            CommandRun(date: Date(), totalDuration: 10, lineRecords: [makeLine("Halfway", offset: 5)]),
        ])

        let match = try #require(timeline.match(makeLine("Halfway"), after: -1))
        let expectedDuration = (10.0 + 20.0 * 0.7) / 1.7

        #expect(abs(timeline.expectedDuration - expectedDuration) < 0.000_001)
        #expect(abs(match.expectedOffset - expectedDuration / 2) < 0.000_001)
    }
}
