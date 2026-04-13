package progress

import "time"

// LineRecord is a hashed output line observed during a command run.
type LineRecord struct {
	TextHash       string  `json:"textHash"`
	NormalizedHash string  `json:"normalizedHash"`
	OffsetSeconds  float64 `json:"offsetSeconds"`
}

// CommandRun is a successful command execution stored in history.
type CommandRun struct {
	Date          time.Time    `json:"date"`
	TotalDuration float64      `json:"totalDuration"`
	LineRecords   []LineRecord `json:"lines"`
}

// CommandHistory is the stored execution history for one command key.
type CommandHistory struct {
	Runs []CommandRun `json:"runs"`
}

// ProgressFill contains normalized progress split by confidence level.
type ProgressFill struct {
	Confirmed float64
	Predicted float64
}

// NewProgressFill clamps progress to [0, 1] and keeps predicted >= confirmed.
func NewProgressFill(confirmed, predicted float64) ProgressFill {
	confirmed = clamp01(confirmed)
	predicted = clamp01(max(confirmed, predicted))
	return ProgressFill{
		Confirmed: confirmed,
		Predicted: predicted,
	}
}

// ProgressEstimate is a point-in-time view of the live progress timeline.
type ProgressEstimate struct {
	Progress                      ProgressFill
	RemainingTime                 float64
	AdjustedExpectedTotalDuration float64
}

func clamp01(value float64) float64 {
	return min(1, max(0, value))
}
