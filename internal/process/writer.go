package process

import (
	"errors"
	"fmt"
	"io"
	"os"
	"syscall"
)

// Stream identifies the process output stream that produced bytes.
type Stream int

const (
	Stdout Stream = iota
	Stderr
)

// Writer passes raw output bytes to the corresponding destination stream.
type Writer struct {
	Stdout io.Writer
	Stderr io.Writer
}

// StandardWriter writes to os.Stdout and os.Stderr.
func StandardWriter() Writer {
	return Writer{
		Stdout: os.Stdout,
		Stderr: os.Stderr,
	}
}

func (w Writer) Write(data []byte, stream Stream) error {
	var target io.Writer
	switch stream {
	case Stdout:
		target = w.Stdout
	case Stderr:
		target = w.Stderr
	default:
		return fmt.Errorf("unknown output stream %d", stream)
	}
	if target == nil {
		return nil
	}

	_, err := target.Write(data)
	if err != nil {
		if errors.Is(err, syscall.EPIPE) {
			return nil
		}
		return fmt.Errorf("write command output: %w", err)
	}
	return nil
}
