package process

import (
	"bytes"
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
