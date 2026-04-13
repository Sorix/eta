package process

import (
	"bytes"
	"errors"
	"syscall"
	"testing"
)

func TestWriterPassesBytesToSeparateStreams(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	writer := Writer{Stdout: &stdout, Stderr: &stderr}

	if err := writer.Write([]byte("out\x00\n"), Stdout); err != nil {
		t.Fatalf("write stdout: %v", err)
	}
	if err := writer.Write([]byte("err\x00\n"), Stderr); err != nil {
		t.Fatalf("write stderr: %v", err)
	}

	if got := stdout.String(); got != "out\x00\n" {
		t.Fatalf("stdout = %q, want raw stdout bytes", got)
	}
	if got := stderr.String(); got != "err\x00\n" {
		t.Fatalf("stderr = %q, want raw stderr bytes", got)
	}
}

func TestWriterIgnoresBrokenPipe(t *testing.T) {
	writer := Writer{Stdout: errWriter{err: syscall.EPIPE}}

	if err := writer.Write([]byte("out\n"), Stdout); err != nil {
		t.Fatalf("Write() error = %v; want nil for broken pipe", err)
	}
}

func TestWriterReturnsOtherWriteErrors(t *testing.T) {
	writeErr := errors.New("disk full")
	writer := Writer{Stderr: errWriter{err: writeErr}}

	err := writer.Write([]byte("err\n"), Stderr)
	if !errors.Is(err, writeErr) {
		t.Fatalf("Write() error = %v; want %v", err, writeErr)
	}
}

type errWriter struct {
	err error
}

func (w errWriter) Write([]byte) (int, error) {
	return 0, w.err
}
