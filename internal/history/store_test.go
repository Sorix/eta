package history

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Sorix/eta/internal/hashline"
	"github.com/Sorix/eta/internal/progress"
)

func TestLoadReturnsNilWhenHistoryFileIsMissing(t *testing.T) {
	store := NewStore(t.TempDir())

	history, err := store.Load("missing")
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}
	if history != nil {
		t.Fatalf("Load returned %#v, want nil", history)
	}
}

func TestLoadsHistoryJSONFixture(t *testing.T) {
	var metadata historyMetadata
	readFixture(t, "testdata/compat/history-metadata.json", &metadata)

	dir := t.TempDir()
	fixtureData, err := os.ReadFile(filepath.Join("..", "..", "testdata/compat", metadata.FileName))
	if err != nil {
		t.Fatalf("read history fixture: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, metadata.FileName), fixtureData, 0o644); err != nil {
		t.Fatalf("write fixture copy: %v", err)
	}

	loaded, err := NewStore(dir).Load(metadata.Command)
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}
	if loaded == nil {
		t.Fatal("Load returned nil, want fixture history")
	}
	if len(loaded.Runs) != 1 {
		t.Fatalf("runs = %d, want 1", len(loaded.Runs))
	}
	run := loaded.Runs[0]
	if !run.Date.Equal(time.Date(2023, 11, 14, 22, 13, 20, 0, time.UTC)) {
		t.Fatalf("date = %s, want fixture date", run.Date.Format(time.RFC3339))
	}
	if run.TotalDuration != 12.345 {
		t.Fatalf("total duration = %v, want 12.345", run.TotalDuration)
	}
	if len(run.LineRecords) != 2 || run.LineRecords[0].OffsetSeconds != 1.25 || run.LineRecords[1].OffsetSeconds != 12 {
		t.Fatalf("line records = %#v, want fixture offsets", run.LineRecords)
	}
}

func TestSaveLoadsAndPrunesNewestRuns(t *testing.T) {
	store := NewStore(t.TempDir())
	runs := make([]progress.CommandRun, 0, 5)
	for index := range 5 {
		runs = append(runs, progress.CommandRun{
			Date:          time.Unix(int64(index), 0).UTC(),
			TotalDuration: float64(index),
			LineRecords:   []progress.LineRecord{makeLine("line", float64(index))},
		})
	}

	if err := store.Save(progress.CommandHistory{Runs: runs}, "command", 2, 90); err != nil {
		t.Fatalf("Save returned error: %v", err)
	}
	loaded, err := store.Load("command")
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}
	if got := len(loaded.Runs); got != 2 {
		t.Fatalf("runs = %d, want 2", got)
	}
	if loaded.Runs[0].TotalDuration != 3 || loaded.Runs[1].TotalDuration != 4 {
		t.Fatalf("durations = [%v, %v], want [3, 4]", loaded.Runs[0].TotalDuration, loaded.Runs[1].TotalDuration)
	}
}

func TestSaveDoesNotMutateInputHistory(t *testing.T) {
	store := NewStore(t.TempDir())
	lineCount := maxLinesPerRun + 1
	lines := make([]progress.LineRecord, 0, lineCount)
	for index := range lineCount {
		lines = append(lines, makeLine("line", float64(index)))
	}
	history := progress.CommandHistory{Runs: []progress.CommandRun{
		{Date: time.Unix(0, 0).UTC(), TotalDuration: 1, LineRecords: lines},
		{Date: time.Unix(1, 0).UTC(), TotalDuration: 2, LineRecords: lines},
	}}

	if err := store.Save(history, "command", 1, 90); err != nil {
		t.Fatalf("Save returned error: %v", err)
	}
	if len(history.Runs) != 2 {
		t.Fatalf("input runs = %d, want 2", len(history.Runs))
	}
	if len(history.Runs[0].LineRecords) != lineCount || len(history.Runs[1].LineRecords) != lineCount {
		t.Fatalf("input line counts = [%d, %d], want %d", len(history.Runs[0].LineRecords), len(history.Runs[1].LineRecords), lineCount)
	}
}

func TestSaveThrowsForInvalidMaximumRunCount(t *testing.T) {
	store := NewStore(t.TempDir())

	err := store.Save(progress.CommandHistory{}, "command", 0, 90)
	var invalid InvalidMaximumRunCountError
	if !errors.As(err, &invalid) || invalid.Value != 0 {
		t.Fatalf("Save error = %v, want InvalidMaximumRunCountError(0)", err)
	}
}

func TestPrunesStaleJSONFilesAfterSave(t *testing.T) {
	dir := t.TempDir()
	now := time.Date(2026, 4, 13, 12, 0, 0, 0, time.UTC)
	store := newStoreWithClock(dir, func() time.Time { return now })

	stale := filepath.Join(dir, "stale.json")
	freshText := filepath.Join(dir, "stale.txt")
	if err := os.WriteFile(stale, []byte("{}"), 0o644); err != nil {
		t.Fatalf("write stale file: %v", err)
	}
	if err := os.WriteFile(freshText, []byte("{}"), 0o644); err != nil {
		t.Fatalf("write non-json file: %v", err)
	}
	oldTime := now.Add(-72 * time.Hour)
	if err := os.Chtimes(stale, oldTime, oldTime); err != nil {
		t.Fatalf("chtimes stale file: %v", err)
	}
	if err := os.Chtimes(freshText, oldTime, oldTime); err != nil {
		t.Fatalf("chtimes non-json file: %v", err)
	}

	if err := store.Save(progress.CommandHistory{Runs: []progress.CommandRun{
		{Date: now, TotalDuration: 1, LineRecords: []progress.LineRecord{makeLine("line", 1)}},
	}}, "command", 10, 1); err != nil {
		t.Fatalf("Save returned error: %v", err)
	}
	if _, err := os.Stat(stale); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("stale JSON stat error = %v, want not exist", err)
	}
	if _, err := os.Stat(freshText); err != nil {
		t.Fatalf("non-json stale file was pruned: %v", err)
	}
}

func TestDownsamplesToMaximumLinesAndPreservesFirstAndLast(t *testing.T) {
	store := NewStore(t.TempDir())
	lineCount := maxLinesPerRun + 1234
	lines := make([]progress.LineRecord, 0, lineCount)
	for index := range lineCount {
		lines = append(lines, makeLine("line", float64(index)))
	}

	if err := store.Save(progress.CommandHistory{Runs: []progress.CommandRun{
		{Date: time.Unix(0, 0).UTC(), TotalDuration: 1, LineRecords: lines},
	}}, "command", 10, 90); err != nil {
		t.Fatalf("Save returned error: %v", err)
	}
	loaded, err := store.Load("command")
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}
	savedLines := loaded.Runs[0].LineRecords
	if len(savedLines) != maxLinesPerRun {
		t.Fatalf("saved lines = %d, want %d", len(savedLines), maxLinesPerRun)
	}
	if savedLines[0].OffsetSeconds != 0 {
		t.Fatalf("first offset = %v, want 0", savedLines[0].OffsetSeconds)
	}
	if savedLines[len(savedLines)-1].OffsetSeconds != float64(lineCount-1) {
		t.Fatalf("last offset = %v, want %v", savedLines[len(savedLines)-1].OffsetSeconds, float64(lineCount-1))
	}
}

func TestStoredFilesContainHashedCommandKeysAndLineRecordsOnly(t *testing.T) {
	dir := t.TempDir()
	command := "secret command"
	rawOutput := "secret output"
	store := NewStore(dir)

	if err := store.Save(progress.CommandHistory{Runs: []progress.CommandRun{
		{
			Date:          time.Unix(0, 0).UTC(),
			TotalDuration: 1,
			LineRecords: []progress.LineRecord{{
				TextHash:       hashline.Hash(rawOutput),
				NormalizedHash: hashline.NormalizedHash(rawOutput),
				OffsetSeconds:  1,
			}},
		},
	}}, command, 10, 90); err != nil {
		t.Fatalf("Save returned error: %v", err)
	}

	fileName := hashline.CommandFingerprint(command) + ".json"
	data, err := os.ReadFile(filepath.Join(dir, fileName))
	if err != nil {
		t.Fatalf("read history file: %v", err)
	}
	jsonText := string(data)
	if strings.Contains(fileName, command) {
		t.Fatalf("file name %q contains raw command", fileName)
	}
	if strings.Contains(jsonText, command) {
		t.Fatal("history JSON contains raw command")
	}
	if strings.Contains(jsonText, rawOutput) {
		t.Fatal("history JSON contains raw output")
	}
	if !strings.Contains(jsonText, hashline.Hash(rawOutput)) {
		t.Fatal("history JSON does not contain line hash")
	}
}

func TestClearsOneCommandHistoryAndThenAllHistory(t *testing.T) {
	dir := t.TempDir()
	store := NewStore(dir)
	history := progress.CommandHistory{Runs: []progress.CommandRun{
		{Date: time.Unix(0, 0).UTC(), TotalDuration: 1, LineRecords: []progress.LineRecord{makeLine("line", 1)}},
	}}

	if err := store.Save(history, "one", 10, 90); err != nil {
		t.Fatalf("save one: %v", err)
	}
	if err := store.Save(history, "two", 10, 90); err != nil {
		t.Fatalf("save two: %v", err)
	}
	if err := store.Clear("one"); err != nil {
		t.Fatalf("Clear returned error: %v", err)
	}
	if loaded, err := store.Load("one"); err != nil || loaded != nil {
		t.Fatalf("Load one = %#v, %v; want nil, nil", loaded, err)
	}
	if loaded, err := store.Load("two"); err != nil || loaded == nil {
		t.Fatalf("Load two = %#v, %v; want history, nil", loaded, err)
	}
	if err := store.ClearAll(); err != nil {
		t.Fatalf("ClearAll returned error: %v", err)
	}
	if _, err := os.Stat(dir); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("history dir stat error = %v, want not exist", err)
	}
}

type historyMetadata struct {
	Command  string `json:"command"`
	FileName string `json:"fileName"`
}

func makeLine(text string, offset float64) progress.LineRecord {
	return progress.LineRecord{
		TextHash:       hashline.Hash(text),
		NormalizedHash: hashline.NormalizedHash(text),
		OffsetSeconds:  offset,
	}
}

func readFixture(t *testing.T, path string, target any) {
	t.Helper()

	data, err := os.ReadFile(filepath.Join("..", "..", path))
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	if err := json.Unmarshal(data, target); err != nil {
		t.Fatalf("decode fixture: %v", err)
	}
}
