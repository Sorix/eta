package progress

import "testing"

func TestLineMatcherMatchesExactThenNormalized(t *testing.T) {
	lines := []LineRecord{
		makeLine("compile-foo-1", "compile-foo-N", 1),
		makeLine("compile-bar-2", "compile-bar-N", 2),
		makeLine("link-3", "link-N", 3),
	}
	matcher := NewLineMatcher([]CommandRun{{TotalDuration: 3, LineRecords: lines}})

	if index, ok := matcher.MatchLine(makeLine("compile-bar-2", "compile-bar-N", 0), -1); !ok || index != 1 {
		t.Fatalf("exact match = %d, %v; want 1, true", index, ok)
	}
	if index, ok := matcher.MatchLine(makeLine("compile-bar-99", "compile-bar-N", 0), -1); !ok || index != 1 {
		t.Fatalf("normalized match = %d, %v; want 1, true", index, ok)
	}
}

func TestLineMatcherExactHashWinsWhenNormalizedHashesOverlap(t *testing.T) {
	matcher := NewLineMatcher([]CommandRun{{
		TotalDuration: 2,
		LineRecords: []LineRecord{
			makeLine("step-1", "step-N", 1),
			makeLine("step-2", "step-N", 2),
		},
	}})

	if index, ok := matcher.MatchLine(makeLine("step-2", "step-N", 0), -1); !ok || index != 1 {
		t.Fatalf("exact match = %d, %v; want 1, true", index, ok)
	}
	if index, ok := matcher.MatchLine(makeLine("step-99", "step-N", 0), -1); !ok || index != 0 {
		t.Fatalf("fallback match = %d, %v; want 0, true", index, ok)
	}
}

func TestLineMatcherRepeatedLinesMatchAfterPreviousIndex(t *testing.T) {
	lines := []LineRecord{
		makeLine("compile-shared", "compile-shared", 1),
		makeLine("compile-shared", "compile-shared", 2),
		makeLine("done", "done", 3),
	}
	matcher := NewLineMatcher([]CommandRun{{TotalDuration: 3, LineRecords: lines}})

	first, ok := matcher.MatchLine(makeLine("compile-shared", "compile-shared", 0), -1)
	if !ok || first != 0 {
		t.Fatalf("first match = %d, %v; want 0, true", first, ok)
	}
	second, ok := matcher.MatchLine(makeLine("compile-shared", "compile-shared", 0), first)
	if !ok || second != 1 {
		t.Fatalf("second match = %d, %v; want 1, true", second, ok)
	}
	if index, ok := matcher.MatchLine(makeLine("compile-shared", "compile-shared", 0), 1); ok {
		t.Fatalf("match after exhausted repeated lines = %d, true; want false", index)
	}
}

func TestLineMatcherReturnsFalseWithoutReferenceHistory(t *testing.T) {
	matcher := NewLineMatcher(nil)

	if index, ok := matcher.MatchLine(makeLine("done", "done", 0), -1); ok {
		t.Fatalf("match without history = %d, true; want false", index)
	}
	if len(matcher.ReferenceLines) != 0 {
		t.Fatalf("reference lines length = %d; want 0", len(matcher.ReferenceLines))
	}
	if matcher.ReferenceTotalDuration != 0 {
		t.Fatalf("reference duration = %v; want 0", matcher.ReferenceTotalDuration)
	}
}

func makeLine(textHash, normalizedHash string, offset float64) LineRecord {
	return LineRecord{
		TextHash:       textHash,
		NormalizedHash: normalizedHash,
		OffsetSeconds:  offset,
	}
}
