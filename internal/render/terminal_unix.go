//go:build unix

package render

import (
	"fmt"
	"os"

	"golang.org/x/term"
)

const defaultTerminalWidth = 80

// Terminal is the controlling terminal used for progress rendering.
type Terminal struct {
	file    *os.File
	fd      int
	getSize func(int) (int, int, error)
}

// OpenTerminal opens /dev/tty when it is available as a terminal.
func OpenTerminal() *Terminal {
	return openTerminal("/dev/tty")
}

// openTerminal returns nil when path cannot be opened as an interactive terminal.
func openTerminal(path string) *Terminal {
	file, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		return nil
	}

	fd := int(file.Fd())
	if !term.IsTerminal(fd) {
		_ = file.Close()
		return nil
	}

	return &Terminal{
		file:    file,
		fd:      fd,
		getSize: term.GetSize,
	}
}

// Width returns the current terminal width, or 80 when it cannot be read.
func (t *Terminal) Width() int {
	if t == nil {
		return defaultTerminalWidth
	}
	return terminalWidth(t.fd, t.getSize)
}

// terminalWidth falls back to a conventional width when the terminal size is unavailable.
func terminalWidth(fd int, getSize func(int) (int, int, error)) int {
	width, _, err := getSize(fd)
	if err != nil || width <= 0 {
		return defaultTerminalWidth
	}
	return width
}

// Write writes text to the terminal.
func (t *Terminal) Write(text string) error {
	if t == nil || t.file == nil {
		return nil
	}
	if _, err := t.file.WriteString(text); err != nil {
		return fmt.Errorf("write terminal: %w", err)
	}
	return nil
}

// Close closes the terminal handle.
func (t *Terminal) Close() error {
	if t == nil || t.file == nil {
		return nil
	}
	if err := t.file.Close(); err != nil {
		return fmt.Errorf("close terminal: %w", err)
	}
	t.file = nil
	return nil
}
