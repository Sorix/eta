package render

import (
	"errors"
	"sync"
	"time"

	"github.com/Sorix/eta/internal/process"
	"github.com/Sorix/eta/internal/progress"
)

const (
	clearLineReturn = "\x1b[2K\r"
	hideCursor      = "\x1b[?25l"
	showCursor      = "\x1b[?25h"
	firstRunHeader  = "\x1b[33mThere is no history for this command \u2014 unable to show estimation data. This run will be used for future estimates.\x1b[0m\n\n"
	minDrawInterval = 32 * time.Millisecond
)

type terminalHandle interface {
	Width() int
	Write(string) error
	Close() error
}

// Renderer serializes progress redraws with wrapped command output.
type Renderer struct {
	mu       sync.Mutex
	terminal terminalHandle
	writer   process.Writer
	color    Color
	style    BarStyle
	clock    func() time.Time

	lastDrawTime              time.Time
	hasLastDrawTime           bool
	barVisible                bool
	cursorHidden              bool
	outputContainsPartialLine bool
}

// NewRenderer creates a terminal renderer backed by /dev/tty.
func NewRenderer(color Color, style BarStyle) *Renderer {
	return newRenderer(OpenTerminal(), process.StandardWriter(), color, style, time.Now)
}

func newRenderer(terminal terminalHandle, writer process.Writer, color Color, style BarStyle, clock func() time.Time) *Renderer {
	if clock == nil {
		clock = time.Now
	}
	return &Renderer{
		terminal: terminal,
		writer:   writer,
		color:    color,
		style:    style,
		clock:    clock,
	}
}

// Enabled reports whether progress can be written to a terminal.
func (r *Renderer) Enabled() bool {
	if r == nil {
		return false
	}
	r.mu.Lock()
	defer r.mu.Unlock()

	return r.terminal != nil
}

// WriteFirstRunHeader writes the no-history header to the terminal.
func (r *Renderer) WriteFirstRunHeader() error {
	if r == nil {
		return nil
	}
	r.mu.Lock()
	defer r.mu.Unlock()

	return r.writeTerminalLocked(firstRunHeader)
}

// Update redraws progress when rendering is enabled, not inside a partial output line, and not throttled.
func (r *Renderer) Update(fill progress.ProgressFill, remainingTime, elapsedTime float64) error {
	if r == nil {
		return nil
	}
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.terminal == nil || r.outputContainsPartialLine {
		return nil
	}

	now := r.clock()
	if r.hasLastDrawTime && now.Sub(r.lastDrawTime) < minDrawInterval {
		return nil
	}
	r.lastDrawTime = now
	r.hasLastDrawTime = true

	return r.drawLocked(fill, remainingTime, elapsedTime)
}

// ForceUpdate redraws progress immediately when rendering is enabled.
func (r *Renderer) ForceUpdate(fill progress.ProgressFill, remainingTime, elapsedTime float64) error {
	if r == nil {
		return nil
	}
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.terminal == nil {
		return nil
	}
	r.lastDrawTime = r.clock()
	r.hasLastDrawTime = true
	return r.drawLocked(fill, remainingTime, elapsedTime)
}

// WriteOutputAndRedraw clears the bar, forwards command output, and redraws only after full lines.
func (r *Renderer) WriteOutputAndRedraw(rawOutput []byte, stream process.Stream, fill progress.ProgressFill, remainingTime, elapsedTime float64, containsPartialLine bool) error {
	if r == nil {
		return process.StandardWriter().Write(rawOutput, stream)
	}
	r.mu.Lock()
	defer r.mu.Unlock()

	var err error
	if r.terminal != nil && r.barVisible {
		err = errors.Join(err, r.writeTerminalLocked(clearLineReturn))
		r.barVisible = false
	}

	err = errors.Join(err, r.writer.Write(rawOutput, stream))
	r.outputContainsPartialLine = containsPartialLine

	if r.terminal == nil || r.outputContainsPartialLine {
		return err
	}

	r.lastDrawTime = r.clock()
	r.hasLastDrawTime = true
	return errors.Join(err, r.drawLocked(fill, remainingTime, elapsedTime))
}

// Cleanup clears a visible bar and restores the cursor.
func (r *Renderer) Cleanup() error {
	if r == nil {
		return nil
	}
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.terminal == nil {
		return nil
	}

	var err error
	if r.barVisible {
		err = errors.Join(err, r.writeTerminalLocked(clearLineReturn))
		r.barVisible = false
	}
	err = errors.Join(err, r.showCursorLocked())
	err = errors.Join(err, r.closeTerminalLocked())
	return err
}

// Finish clears the bar, restores the cursor, and writes the completion line.
func (r *Renderer) Finish(elapsed, expectedDuration float64) error {
	if r == nil {
		return nil
	}
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.terminal == nil {
		return nil
	}

	var err error
	if r.barVisible {
		err = errors.Join(err, r.writeTerminalLocked(clearLineReturn))
		r.barVisible = false
	}
	err = errors.Join(err, r.showCursorLocked())
	if r.outputContainsPartialLine {
		err = errors.Join(err, r.writeTerminalLocked("\n"))
		r.outputContainsPartialLine = false
	}
	err = errors.Join(err, r.writeTerminalLocked(CompletionLine(elapsed, expectedDuration)))
	err = errors.Join(err, r.closeTerminalLocked())
	return err
}

// drawLocked writes one full progress line while holding r.mu.
func (r *Renderer) drawLocked(fill progress.ProgressFill, remainingTime, elapsedTime float64) error {
	if r.terminal == nil {
		return nil
	}

	bar := BuildLine(fill, remainingTime, elapsedTime, r.terminal.Width(), r.color, r.style)
	err := errors.Join(r.hideCursorLocked(), r.writeTerminalLocked(clearLineReturn+bar))
	r.barVisible = true
	return err
}

// hideCursorLocked hides the terminal cursor once and remembers that state locally.
func (r *Renderer) hideCursorLocked() error {
	if r.cursorHidden {
		return nil
	}
	r.cursorHidden = true
	return r.writeTerminalLocked(hideCursor)
}

// showCursorLocked restores the cursor only if this renderer previously hid it.
func (r *Renderer) showCursorLocked() error {
	if !r.cursorHidden {
		return nil
	}
	r.cursorHidden = false
	return r.writeTerminalLocked(showCursor)
}

// writeTerminalLocked writes directly to /dev/tty and treats a missing terminal as a no-op.
func (r *Renderer) writeTerminalLocked(text string) error {
	if r.terminal == nil {
		return nil
	}
	return r.terminal.Write(text)
}

func (r *Renderer) closeTerminalLocked() error {
	if r.terminal == nil {
		return nil
	}
	err := r.terminal.Close()
	r.terminal = nil
	return err
}
