package render

import (
	"fmt"
	"math"
	"strings"

	"github.com/Sorix/eta/internal/progress"
)

const (
	glyphConfirmed = "█"
	glyphPredicted = "▒"
	glyphEmpty     = " "
	resetANSI      = "\x1b[0m"
)

// BuildLine returns a determinate ETA progress bar.
func BuildLine(fill progress.ProgressFill, remainingTime, elapsedTime float64, width int, color Color, style BarStyle) string {
	_ = elapsedTime
	return buildDeterminateBar(fill, remainingTime, width, color, style)
}

// CompletionLine returns the final success status line.
func CompletionLine(elapsed, expectedDuration float64) string {
	if expectedDuration > 0 {
		delta := elapsed - expectedDuration
		sign := ""
		if delta >= 0 {
			sign = "+"
		}
		return fmt.Sprintf("\x1b[32mDone in %s  (expected %s, delta %s%s)%s\n",
			FormatTime(elapsed), FormatTime(expectedDuration), sign, FormatTime(delta), resetANSI)
	}
	return fmt.Sprintf("\x1b[32mDone in %s%s\n", FormatTime(elapsed), resetANSI)
}

// FormatTime formats seconds like the Swift CLI formatter.
func FormatTime(seconds float64) string {
	totalSeconds := int(math.Round(math.Abs(seconds)))
	sign := ""
	if seconds < 0 && totalSeconds > 0 {
		sign = "-"
	}
	if totalSeconds < 60 {
		return fmt.Sprintf("%s%ds", sign, totalSeconds)
	}
	minutes := totalSeconds / 60
	remainingSeconds := totalSeconds % 60
	return fmt.Sprintf("%s%dm%02ds", sign, minutes, remainingSeconds)
}

func buildDeterminateBar(fill progress.ProgressFill, remainingTime float64, width int, color Color, style BarStyle) string {
	pct := fmt.Sprintf("%3.0f%%", fill.Predicted*100)
	remainingTimeString := "ETA 0s"
	if remainingTime > 0 {
		remainingTimeString = "ETA " + FormatTime(remainingTime)
	}
	suffix := "  " + pct + "  " + remainingTimeString

	barWidth := max(10, width-len(suffix)-3)
	predictedWidth := int(float64(barWidth) * fill.Predicted)

	var barFill string
	switch style {
	case Layered:
		confirmedWidth := int(float64(barWidth) * fill.Confirmed)
		predictedOnlyWidth := max(0, predictedWidth-confirmedWidth)
		emptyWidth := max(0, barWidth-confirmedWidth-predictedOnlyWidth)
		barFill = strings.Repeat(glyphConfirmed, confirmedWidth) +
			strings.Repeat(glyphPredicted, predictedOnlyWidth) +
			strings.Repeat(glyphEmpty, emptyWidth)
	case Solid:
		emptyWidth := max(0, barWidth-predictedWidth)
		barFill = strings.Repeat(glyphConfirmed, predictedWidth) +
			strings.Repeat(glyphEmpty, emptyWidth)
	default:
		emptyWidth := max(0, barWidth-predictedWidth)
		barFill = strings.Repeat(glyphConfirmed, predictedWidth) +
			strings.Repeat(glyphEmpty, emptyWidth)
	}

	return color.ansiCode() + "[" + barFill + "]" + suffix + resetANSI
}
