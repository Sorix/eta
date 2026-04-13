package progress

const durationAlpha = 0.3

// ReferenceLineMatch maps a current line onto the weighted reference timeline.
type ReferenceLineMatch struct {
	Index          int
	ExpectedOffset float64
}

// ReferenceTimeline computes expected duration and reference-line offsets.
type ReferenceTimeline struct {
	ExpectedDuration float64
	HasHistory       bool

	matcher LineMatcher
}

// NewReferenceTimeline creates a baseline timeline from oldest-to-newest runs.
func NewReferenceTimeline(runs []CommandRun) ReferenceTimeline {
	if len(runs) == 0 {
		return ReferenceTimeline{
			ExpectedDuration: 0,
			HasHistory:       false,
			matcher:          NewLineMatcher(nil),
		}
	}

	return ReferenceTimeline{
		ExpectedDuration: weightedMeanDuration(runs),
		HasHistory:       true,
		matcher:          NewLineMatcher(runs),
	}
}

// NewReferenceTimelineFromHistory creates a baseline timeline from history.
func NewReferenceTimelineFromHistory(history CommandHistory) ReferenceTimeline {
	return NewReferenceTimeline(history.Runs)
}

// Match maps a pre-hashed line onto the expected timeline after previousIndex.
func (t ReferenceTimeline) Match(line LineRecord, previousIndex int) (ReferenceLineMatch, bool) {
	index, ok := t.matcher.MatchLine(line, previousIndex)
	if !ok || index < 0 || index >= len(t.matcher.ReferenceLines) || t.ExpectedDuration <= 0 {
		return ReferenceLineMatch{}, false
	}

	referenceLine := t.matcher.ReferenceLines[index]
	if t.matcher.ReferenceTotalDuration <= 0 {
		return ReferenceLineMatch{
			Index:          index,
			ExpectedOffset: min(t.ExpectedDuration, max(0, referenceLine.OffsetSeconds)),
		}, true
	}

	referenceProgress := clamp01(referenceLine.OffsetSeconds / t.matcher.ReferenceTotalDuration)
	return ReferenceLineMatch{
		Index:          index,
		ExpectedOffset: referenceProgress * t.ExpectedDuration,
	}, true
}

func weightedMeanDuration(runs []CommandRun) float64 {
	if len(runs) == 0 {
		return 0
	}

	weight := 1.0
	totalWeight := 0.0
	weightedSum := 0.0

	for index := len(runs) - 1; index >= 0; index-- {
		weightedSum += runs[index].TotalDuration * weight
		totalWeight += weight
		weight *= 1 - durationAlpha
	}

	return weightedSum / totalWeight
}
