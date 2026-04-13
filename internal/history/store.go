package history

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/Sorix/eta/internal/hashline"
	"github.com/Sorix/eta/internal/progress"
	"github.com/google/renameio/v2"
)

const maxLinesPerRun = 5000

// InvalidMaximumRunCountError reports an invalid history retention setting.
type InvalidMaximumRunCountError struct {
	Value int
}

func (e InvalidMaximumRunCountError) Error() string {
	return fmt.Sprintf("maximumRunCount must be greater than 0 (got %d)", e.Value)
}

// Store loads, saves, and clears privacy-preserving command history files.
type Store struct {
	directory string
	now       func() time.Time
}

// NewStore creates a history store rooted at directory.
func NewStore(directory string) Store {
	return Store{
		directory: directory,
		now:       time.Now,
	}
}

// newStoreWithClock injects a clock for tests that exercise stale-history pruning.
func newStoreWithClock(directory string, now func() time.Time) Store {
	store := NewStore(directory)
	store.now = now
	return store
}

// DefaultDirectory returns the platform user cache directory for eta.
func DefaultDirectory() (string, error) {
	cacheDir, err := os.UserCacheDir()
	if err != nil {
		return "", fmt.Errorf("user cache dir: %w", err)
	}
	return filepath.Join(cacheDir, "eta"), nil
}

// Load reads history for commandKey, returning nil when no file exists.
func (s Store) Load(commandKey string) (*progress.CommandHistory, error) {
	data, err := os.ReadFile(s.filePath(commandKey))
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read history: %w", err)
	}

	var history progress.CommandHistory
	if err := json.Unmarshal(data, &history); err != nil {
		return nil, fmt.Errorf("decode history: %w", err)
	}
	return &history, nil
}

// Save writes history for commandKey, retaining the newest maximumRunCount runs.
func (s Store) Save(history progress.CommandHistory, commandKey string, maximumRunCount, staleAfterDays int) error {
	if maximumRunCount <= 0 {
		return InvalidMaximumRunCountError{Value: maximumRunCount}
	}

	pruned := pruneRuns(history, maximumRunCount)
	for index := range pruned.Runs {
		pruned.Runs[index].LineRecords = downsample(pruned.Runs[index].LineRecords, maxLinesPerRun)
	}

	if err := os.MkdirAll(s.directory, 0o755); err != nil {
		return fmt.Errorf("create history dir: %w", err)
	}

	data, err := json.MarshalIndent(pruned, "", "  ")
	if err != nil {
		return fmt.Errorf("encode history: %w", err)
	}
	data = append(data, '\n')

	if err := renameio.WriteFile(s.filePath(commandKey), data, 0o644); err != nil {
		return fmt.Errorf("write history: %w", err)
	}
	s.pruneStale(staleAfterDays)
	return nil
}

// Clear removes history for one command key.
func (s Store) Clear(commandKey string) error {
	err := os.Remove(s.filePath(commandKey))
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("clear history: %w", err)
	}
	return nil
}

// ClearAll removes the entire history directory.
func (s Store) ClearAll() error {
	err := os.RemoveAll(s.directory)
	if err != nil {
		return fmt.Errorf("clear all history: %w", err)
	}
	return nil
}

// filePath hashes commandKey so history filenames never expose the original command text.
func (s Store) filePath(commandKey string) string {
	return filepath.Join(s.directory, hashline.CommandFingerprint(commandKey)+".json")
}

// pruneRuns keeps only the newest maximumRunCount runs while preserving chronological order.
func pruneRuns(history progress.CommandHistory, maximumRunCount int) progress.CommandHistory {
	start := 0
	if len(history.Runs) > maximumRunCount {
		start = len(history.Runs) - maximumRunCount
	}
	history.Runs = append([]progress.CommandRun(nil), history.Runs[start:]...)
	return history
}

// downsample keeps the first and last line and spreads the remaining samples evenly in between.
func downsample(lines []progress.LineRecord, maximumCount int) []progress.LineRecord {
	if len(lines) <= maximumCount || maximumCount < 2 {
		return lines
	}

	result := make([]progress.LineRecord, 0, maximumCount)
	result = append(result, lines[0])
	step := float64(len(lines)-1) / float64(maximumCount-1)
	for index := 1; index < maximumCount-1; index++ {
		result = append(result, lines[int(round(float64(index)*step))])
	}
	result = append(result, lines[len(lines)-1])
	return result
}

// round implements symmetric half-away-from-zero rounding for downsampling indices.
func round(value float64) float64 {
	if value < 0 {
		return float64(int(value - 0.5))
	}
	return float64(int(value + 0.5))
}

// pruneStale best-effort removes old JSON history files and ignores cleanup failures.
func (s Store) pruneStale(staleAfterDays int) {
	entries, err := os.ReadDir(s.directory)
	if err != nil {
		return
	}

	cutoff := s.now().Add(-time.Duration(staleAfterDays) * 24 * time.Hour)
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".json" {
			continue
		}

		path := filepath.Join(s.directory, entry.Name())
		info, err := entry.Info()
		if err != nil || !info.ModTime().Before(cutoff) {
			continue
		}
		_ = os.Remove(path)
	}
}
