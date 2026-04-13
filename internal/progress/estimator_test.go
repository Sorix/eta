package progress

import (
	"math"
	"testing"
)

func TestProgressFillClampsProgressAndKeepsPredictionAtOrAboveConfirmed(t *testing.T) {
	tests := []struct {
		name              string
		confirmed         float64
		predicted         float64
		expectedConfirmed float64
		expectedPredicted float64
	}{
		{name: "below zero", confirmed: -1, predicted: -1, expectedConfirmed: 0, expectedPredicted: 0},
		{name: "prediction below confirmed", confirmed: 0.7, predicted: 0.2, expectedConfirmed: 0.7, expectedPredicted: 0.7},
		{name: "prediction above one", confirmed: 0.5, predicted: 1.5, expectedConfirmed: 0.5, expectedPredicted: 1},
		{name: "confirmed above one", confirmed: 2, predicted: 0.5, expectedConfirmed: 1, expectedPredicted: 1},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			fill := NewProgressFill(tt.confirmed, tt.predicted)
			if fill.Confirmed != tt.expectedConfirmed || fill.Predicted != tt.expectedPredicted {
				t.Fatalf("NewProgressFill(%v, %v) = (%v, %v); want (%v, %v)",
					tt.confirmed, tt.predicted, fill.Confirmed, fill.Predicted, tt.expectedConfirmed, tt.expectedPredicted)
			}
		})
	}
}

func TestTimelineProgressEstimatorReturnsEmptyEstimateWithoutHistory(t *testing.T) {
	estimator := NewTimelineProgressEstimatorFromHistory(nil)
	estimate := estimator.Estimate(10)

	if estimator.HasHistory() {
		t.Fatal("HasHistory() = true; want false")
	}
	if estimator.ExpectedTotalDuration() != 0 {
		t.Fatalf("ExpectedTotalDuration() = %v; want 0", estimator.ExpectedTotalDuration())
	}
	if estimate.Progress != NewProgressFill(0, 0) {
		t.Fatalf("progress = %+v; want zero fill", estimate.Progress)
	}
	if estimate.RemainingTime != 0 {
		t.Fatalf("remaining time = %v; want 0", estimate.RemainingTime)
	}
}

func TestTimelineProgressEstimatorWeightsRecentRunsMoreHeavily(t *testing.T) {
	oldRun := CommandRun{TotalDuration: 100, LineRecords: []LineRecord{makeLine("old", "old", 100)}}
	newRun := CommandRun{TotalDuration: 10, LineRecords: []LineRecord{makeLine("new", "new", 10)}}
	estimator := NewTimelineProgressEstimator([]CommandRun{oldRun, newRun})

	expected := (10.0 + 100.0*0.7) / 1.7
	if !almostEqual(estimator.ExpectedTotalDuration(), expected) {
		t.Fatalf("ExpectedTotalDuration() = %v; want %v", estimator.ExpectedTotalDuration(), expected)
	}
}

func TestTimelineProgressEstimatorAdvancesConfirmedProgressAndClampsPrediction(t *testing.T) {
	referenceLines := []LineRecord{
		makeLine("configure", "configure", 2),
		makeLine("compile", "compile", 5),
		makeLine("done", "done", 10),
	}
	estimator := NewTimelineProgressEstimator([]CommandRun{{
		TotalDuration: 10,
		LineRecords:   referenceLines,
	}})

	compileEstimate := estimator.ObserveCurrentLine(makeLine("compile", "compile", 1), 1)
	if compileEstimate.Progress.Confirmed != 0.5 {
		t.Fatalf("confirmed progress = %v; want 0.5", compileEstimate.Progress.Confirmed)
	}
	if compileEstimate.Progress.Predicted < compileEstimate.Progress.Confirmed {
		t.Fatalf("predicted progress = %v; want >= confirmed %v", compileEstimate.Progress.Predicted, compileEstimate.Progress.Confirmed)
	}

	laterEstimate := estimator.Estimate(100)
	if laterEstimate.Progress.Predicted != 1 {
		t.Fatalf("later predicted progress = %v; want 1", laterEstimate.Progress.Predicted)
	}
	if laterEstimate.RemainingTime != -94 {
		t.Fatalf("later remaining time = %v; want -94", laterEstimate.RemainingTime)
	}

	estimator.ResetCurrentLog()
	resetEstimate := estimator.Estimate(0)
	if resetEstimate.Progress.Confirmed != 0 {
		t.Fatalf("reset confirmed progress = %v; want 0", resetEstimate.Progress.Confirmed)
	}
}

func TestTimelineProgressEstimatorCurrentLogCacheResetsForShorterLog(t *testing.T) {
	referenceLines := []LineRecord{
		makeLine("step-1", "step-N", 1),
		makeLine("step-2", "step-N", 2),
	}
	estimator := NewTimelineProgressEstimator([]CommandRun{{
		TotalDuration: 2,
		LineRecords:   referenceLines,
	}})

	_ = estimator.EstimateLog(referenceLines, 2)
	resetEstimate := estimator.EstimateLog([]LineRecord{referenceLines[0]}, 1)

	if resetEstimate.Progress.Confirmed != 0.5 {
		t.Fatalf("reset confirmed progress = %v; want 0.5", resetEstimate.Progress.Confirmed)
	}
}

func TestTimelineProgressEstimatorSlowObservedMilestonesExtendAdjustedExpectedDuration(t *testing.T) {
	estimator := NewTimelineProgressEstimator([]CommandRun{{
		TotalDuration: 10,
		LineRecords: []LineRecord{
			makeLine("halfway", "halfway", 5),
			makeLine("done", "done", 10),
		},
	}})

	estimate := estimator.ObserveCurrentLine(makeLine("halfway", "halfway", 20), 20)

	if estimate.Progress.Confirmed != 0.5 {
		t.Fatalf("confirmed progress = %v; want 0.5", estimate.Progress.Confirmed)
	}
	if estimate.RemainingTime != 5 {
		t.Fatalf("remaining time = %v; want 5", estimate.RemainingTime)
	}
	if estimate.AdjustedExpectedTotalDuration != 25 {
		t.Fatalf("adjusted duration = %v; want 25", estimate.AdjustedExpectedTotalDuration)
	}
}

func TestReferenceTimelineScalesReferenceLineOffsetsOntoWeightedExpectedDuration(t *testing.T) {
	timeline := NewReferenceTimeline([]CommandRun{
		{TotalDuration: 20, LineRecords: []LineRecord{makeLine("old", "old", 20)}},
		{TotalDuration: 10, LineRecords: []LineRecord{makeLine("halfway", "halfway", 5)}},
	})

	match, ok := timeline.Match(makeLine("halfway", "halfway", 0), -1)
	if !ok {
		t.Fatal("timeline.Match returned false; want true")
	}

	expectedDuration := (10.0 + 20.0*0.7) / 1.7
	if !almostEqual(timeline.ExpectedDuration, expectedDuration) {
		t.Fatalf("ExpectedDuration = %v; want %v", timeline.ExpectedDuration, expectedDuration)
	}
	if !almostEqual(match.ExpectedOffset, expectedDuration/2) {
		t.Fatalf("ExpectedOffset = %v; want %v", match.ExpectedOffset, expectedDuration/2)
	}
}

func almostEqual(got, want float64) bool {
	return math.Abs(got-want) < 0.000001
}
