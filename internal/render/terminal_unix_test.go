//go:build unix

package render

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestOpenTerminalReturnsNilForMissingOrNonTTYPath(t *testing.T) {
	if terminal := openTerminal(filepath.Join(t.TempDir(), "missing")); terminal != nil {
		t.Fatalf("open missing terminal = %#v, want nil", terminal)
	}

	regularFile := filepath.Join(t.TempDir(), "regular")
	if err := os.WriteFile(regularFile, []byte("not a tty"), 0o644); err != nil {
		t.Fatalf("write regular file: %v", err)
	}
	if terminal := openTerminal(regularFile); terminal != nil {
		t.Fatalf("open regular file terminal = %#v, want nil", terminal)
	}
}

func TestTerminalWidthUsesSizeOrFallback(t *testing.T) {
	width := terminalWidth(1, func(int) (int, int, error) {
		return 132, 40, nil
	})
	if width != 132 {
		t.Fatalf("terminalWidth = %d, want 132", width)
	}

	width = terminalWidth(1, func(int) (int, int, error) {
		return 0, 0, errors.New("no size")
	})
	if width != defaultTerminalWidth {
		t.Fatalf("terminalWidth fallback = %d, want %d", width, defaultTerminalWidth)
	}
}
