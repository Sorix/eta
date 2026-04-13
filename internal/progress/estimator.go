package progress

import "sync"

// TimelineProgressEstimator estimates progress from history and current lines.
type TimelineProgressEstimator struct {
	referenceTimeline ReferenceTimeline
	mu                sync.Mutex

	processedCurrentLineCount int
	timelineOffset            float64
	lastMatchedReferenceIndex int
	confirmedExpectedOffset   float64
}

// NewTimelineProgressEstimator creates an estimator from oldest-to-newest runs.
func NewTimelineProgressEstimator(runs []CommandRun) *TimelineProgressEstimator {
	return &TimelineProgressEstimator{
		referenceTimeline:         NewReferenceTimeline(runs),
		lastMatchedReferenceIndex: -1,
	}
}

// NewTimelineProgressEstimatorFromHistory creates an estimator from history.
func NewTimelineProgressEstimatorFromHistory(history *CommandHistory) *TimelineProgressEstimator {
	if history == nil {
		return NewTimelineProgressEstimator(nil)
	}
	return NewTimelineProgressEstimator(history.Runs)
}

// HasHistory reports whether historical data is available.
func (e *TimelineProgressEstimator) HasHistory() bool {
	return e.referenceTimeline.HasHistory
}

// ExpectedTotalDuration returns the weighted baseline duration.
func (e *TimelineProgressEstimator) ExpectedTotalDuration() float64 {
	return e.referenceTimeline.ExpectedDuration
}

// Estimate returns a live estimate from cached current-log state.
func (e *TimelineProgressEstimator) Estimate(elapsed float64) ProgressEstimate {
	e.mu.Lock()
	defer e.mu.Unlock()

	return e.makeEstimate(elapsed)
}

// EstimateLog updates from an accumulated append-only current log.
func (e *TimelineProgressEstimator) EstimateLog(currentLog []LineRecord, elapsed float64) ProgressEstimate {
	e.mu.Lock()
	defer e.mu.Unlock()

	if len(currentLog) < e.processedCurrentLineCount {
		e.resetCurrentLogState()
	}

	for _, line := range currentLog[e.processedCurrentLineCount:] {
		e.observeCurrentLineWithoutLock(line)
	}
	e.processedCurrentLineCount = len(currentLog)

	return e.makeEstimate(elapsed)
}

// ObserveCurrentLine adds one current line and returns an estimate.
func (e *TimelineProgressEstimator) ObserveCurrentLine(line LineRecord, elapsed float64) ProgressEstimate {
	e.mu.Lock()
	defer e.mu.Unlock()

	e.observeCurrentLineWithoutLock(line)
	e.processedCurrentLineCount++
	return e.makeEstimate(elapsed)
}

// ResetCurrentLog clears cached current-log position and timeline correction.
func (e *TimelineProgressEstimator) ResetCurrentLog() {
	e.mu.Lock()
	defer e.mu.Unlock()

	e.resetCurrentLogState()
}

func (e *TimelineProgressEstimator) observeCurrentLineWithoutLock(line LineRecord) {
	match, ok := e.referenceTimeline.Match(line, e.lastMatchedReferenceIndex)
	if !ok || match.Index <= e.lastMatchedReferenceIndex {
		return
	}

	e.lastMatchedReferenceIndex = match.Index
	e.confirmedExpectedOffset = match.ExpectedOffset
	e.timelineOffset = match.ExpectedOffset - max(0, line.OffsetSeconds)
}

func (e *TimelineProgressEstimator) resetCurrentLogState() {
	e.processedCurrentLineCount = 0
	e.timelineOffset = 0
	e.lastMatchedReferenceIndex = -1
	e.confirmedExpectedOffset = 0
}

func (e *TimelineProgressEstimator) makeEstimate(elapsed float64) ProgressEstimate {
	if e.referenceTimeline.ExpectedDuration <= 0 {
		return ProgressEstimate{
			Progress:                      NewProgressFill(0, 0),
			RemainingTime:                 0,
			AdjustedExpectedTotalDuration: 0,
		}
	}

	virtualElapsed := max(0, elapsed+e.timelineOffset)
	predictedElapsed := max(e.confirmedExpectedOffset, virtualElapsed)
	confirmedProgress := e.confirmedExpectedOffset / e.referenceTimeline.ExpectedDuration
	predictedProgress := predictedElapsed / e.referenceTimeline.ExpectedDuration
	remainingTime := e.referenceTimeline.ExpectedDuration - predictedElapsed
	adjustedExpectedTotalDuration := max(0, e.referenceTimeline.ExpectedDuration-e.timelineOffset)

	return ProgressEstimate{
		Progress:                      NewProgressFill(confirmedProgress, predictedProgress),
		RemainingTime:                 remainingTime,
		AdjustedExpectedTotalDuration: adjustedExpectedTotalDuration,
	}
}
