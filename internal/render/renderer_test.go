package render

import (
	"bytes"
	"strings"
	"testing"
	"time"

	"github.com/Sorix/eta/internal/process"
	"github.com/Sorix/eta/internal/progress"
)

func TestRendererWriteFirstRunHeader(t *testing.T) {
	terminal := &fakeTerminal{width: 80}
	renderer := newTestRenderer(terminal)

	if err := renderer.WriteFirstRunHeader(); err != nil {
		t.Fatalf("WriteFirstRunHeader() error = %v", err)
	}

	got := terminal.String()
	want := "\x1b[33mThere is no history for this command \u2014 unable to show estimation data. This run will be used for future estimates.\x1b[0m\n\n"
	if got != want {
		t.Fatalf("header mismatch:\ngot  %q\nwant %q", got, want)
	}
}

func TestRendererUpdateThrottlesAndCleanupRestoresCursor(t *testing.T) {
	terminal := &fakeTerminal{width: 40}
	now := time.Unix(100, 0)
	renderer := newRenderer(terminal, process.Writer{}, Green, Layered, func() time.Time {
		return now
	})
	fill := progress.NewProgressFill(0.25, 0.50)

	if err := renderer.Update(fill, 5, 5); err != nil {
		t.Fatalf("first Update() error = %v", err)
	}
	first := terminal.String()
	if !strings.HasPrefix(first, hideCursor+clearLineReturn) {
		t.Fatalf("first draw prefix = %q", first)
	}

	now = now.Add(31 * time.Millisecond)
	if err := renderer.Update(fill, 4, 6); err != nil {
		t.Fatalf("throttled Update() error = %v", err)
	}
	if got := terminal.String(); got != first {
		t.Fatalf("throttled update wrote %q after %q", got, first)
	}

	now = now.Add(time.Millisecond)
	if err := renderer.Update(fill, 3, 7); err != nil {
		t.Fatalf("second Update() error = %v", err)
	}
	if strings.Count(terminal.String(), hideCursor) != 1 {
		t.Fatalf("cursor should only be hidden once, writes = %q", terminal.String())
	}

	if err := renderer.Cleanup(); err != nil {
		t.Fatalf("Cleanup() error = %v", err)
	}
	if !strings.HasSuffix(terminal.String(), clearLineReturn+showCursor) {
		t.Fatalf("cleanup suffix = %q", terminal.String())
	}
	if terminal.closeCount != 1 {
		t.Fatalf("terminal close count = %d, want 1", terminal.closeCount)
	}
}

func TestRendererWriteOutputAndRedrawTracksPartialLine(t *testing.T) {
	terminal := &fakeTerminal{width: 40}
	stdout := &bytes.Buffer{}
	stderr := &bytes.Buffer{}
	renderer := newRenderer(terminal, process.Writer{Stdout: stdout, Stderr: stderr}, Cyan, Layered, time.Now)
	fill := progress.NewProgressFill(0.10, 0.20)

	if err := renderer.ForceUpdate(fill, 8, 2); err != nil {
		t.Fatalf("ForceUpdate() error = %v", err)
	}
	beforeOutput := terminal.String()

	if err := renderer.WriteOutputAndRedraw([]byte("partial"), process.Stdout, fill, 7, 3, true); err != nil {
		t.Fatalf("WriteOutputAndRedraw(partial) error = %v", err)
	}
	if got := stdout.String(); got != "partial" {
		t.Fatalf("stdout = %q", got)
	}
	afterPartial := terminal.String()
	if afterPartial != beforeOutput+clearLineReturn {
		t.Fatalf("partial output terminal writes = %q", afterPartial)
	}

	if err := renderer.Update(fill, 6, 4); err != nil {
		t.Fatalf("Update() while partial error = %v", err)
	}
	if got := terminal.String(); got != afterPartial {
		t.Fatalf("update during partial line wrote %q", got[len(afterPartial):])
	}

	if err := renderer.WriteOutputAndRedraw([]byte("\n"), process.Stderr, fill, 5, 5, false); err != nil {
		t.Fatalf("WriteOutputAndRedraw(line boundary) error = %v", err)
	}
	if got := stderr.String(); got != "\n" {
		t.Fatalf("stderr = %q", got)
	}
	if got := terminal.String(); !strings.HasSuffix(got, clearLineReturn+BuildLine(fill, 5, 40, Cyan, Layered)) {
		t.Fatalf("line-boundary redraw suffix = %q", got)
	}
}

func TestRendererFinishHandlesPartialLineAndCompletion(t *testing.T) {
	terminal := &fakeTerminal{width: 40}
	renderer := newTestRenderer(terminal)
	fill := progress.NewProgressFill(0.5, 0.75)

	if err := renderer.WriteOutputAndRedraw([]byte("no newline"), process.Stdout, fill, 2, 8, true); err != nil {
		t.Fatalf("WriteOutputAndRedraw() error = %v", err)
	}
	if err := renderer.Finish(10, 8); err != nil {
		t.Fatalf("Finish() error = %v", err)
	}

	got := terminal.String()
	if !strings.Contains(got, "\n"+CompletionLine(10, 8)) {
		t.Fatalf("finish should separate partial output from completion, writes = %q", got)
	}
	if strings.Contains(got, showCursor) {
		t.Fatalf("cursor was never hidden, so finish should not show it: %q", got)
	}
	if terminal.closeCount != 1 {
		t.Fatalf("terminal close count = %d, want 1", terminal.closeCount)
	}
}

func newTestRenderer(terminal *fakeTerminal) *Renderer {
	return newRenderer(terminal, process.Writer{}, Green, Layered, time.Now)
}

type fakeTerminal struct {
	width      int
	buf        bytes.Buffer
	closeCount int
}

func (t *fakeTerminal) Width() int {
	if t.width == 0 {
		return defaultTerminalWidth
	}
	return t.width
}

func (t *fakeTerminal) Write(text string) error {
	_, err := t.buf.WriteString(text)
	return err
}

func (t *fakeTerminal) Close() error {
	t.closeCount++
	return nil
}

func (t *fakeTerminal) String() string {
	return t.buf.String()
}
