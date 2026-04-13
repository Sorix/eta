package progress

// LineMatcher matches current output lines against a historical reference run.
type LineMatcher struct {
	ReferenceLines         []LineRecord
	ReferenceTotalDuration float64

	exactIndices      map[string][]int
	normalizedIndices map[string][]int
}

// NewLineMatcher creates a matcher using the newest successful run as reference.
func NewLineMatcher(runs []CommandRun) LineMatcher {
	var referenceRun *CommandRun
	if len(runs) > 0 {
		referenceRun = &runs[len(runs)-1]
	}

	var referenceLines []LineRecord
	var referenceTotalDuration float64
	if referenceRun != nil {
		referenceLines = referenceRun.LineRecords
		referenceTotalDuration = referenceRun.TotalDuration
	}

	matcher := LineMatcher{
		ReferenceLines:         referenceLines,
		ReferenceTotalDuration: referenceTotalDuration,
		exactIndices:           make(map[string][]int, len(referenceLines)),
		normalizedIndices:      make(map[string][]int, len(referenceLines)),
	}

	for index, line := range referenceLines {
		matcher.exactIndices[line.TextHash] = append(matcher.exactIndices[line.TextHash], index)
		matcher.normalizedIndices[line.NormalizedHash] = append(matcher.normalizedIndices[line.NormalizedHash], index)
	}

	return matcher
}

// NewLineMatcherFromHistory creates a matcher from command history.
func NewLineMatcherFromHistory(history CommandHistory) LineMatcher {
	return NewLineMatcher(history.Runs)
}

// MatchLine matches a pre-hashed line against the reference run after previousIndex.
func (m LineMatcher) MatchLine(line LineRecord, previousIndex int) (int, bool) {
	if index, ok := firstCandidateAfter(m.exactIndices[line.TextHash], previousIndex); ok {
		return index, true
	}

	return firstCandidateAfter(m.normalizedIndices[line.NormalizedHash], previousIndex)
}

func firstCandidateAfter(indices []int, previousIndex int) (int, bool) {
	for _, index := range indices {
		if index > previousIndex {
			return index, true
		}
	}
	return 0, false
}
