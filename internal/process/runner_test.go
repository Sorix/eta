package process

import (
	"bytes"
	"context"
	"sync"
	"testing"

	"github.com/Sorix/eta/internal/hashline"
)

func TestRunnerCollectsStdoutStderrExitCodeAndFinalPartialLine(t *testing.T) {
	runner := Runner{Writer: Writer{}, ShellPath: "/bin/sh"}
	var mu sync.Mutex
	var streams []Stream

	output, err := runner.Run(context.Background(), "printf 'out\\npartial'; printf 'err\\n' >&2; exit 7", func(chunk Chunk) {
		mu.Lock()
		defer mu.Unlock()
		streams = append(streams, chunk.Stream)
	})
	if err != nil {
		t.Fatalf("Run returned error: %v", err)
	}

	if output.ExitCode != 7 {
		t.Fatalf("exit code = %d, want 7", output.ExitCode)
	}
	if !containsHash(output, "out") || !containsHash(output, "partial") || !containsHash(output, "err") {
		t.Fatalf("line records = %#v, want out, partial, err", output.LineRecords)
	}
	if !containsStream(streams, Stdout) || !containsStream(streams, Stderr) {
		t.Fatalf("streams = %#v, want stdout and stderr", streams)
	}
}

func TestRunnerWritesThroughStandardWriterWithoutHandler(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	runner := Runner{
		Writer:    Writer{Stdout: &stdout, Stderr: &stderr},
		ShellPath: "/bin/sh",
	}

	output, err := runner.Run(context.Background(), "printf 'out\\n'; printf 'err\\n' >&2", nil)
	if err != nil {
		t.Fatalf("Run returned error: %v", err)
	}

	if output.ExitCode != 0 {
		t.Fatalf("exit code = %d, want 0", output.ExitCode)
	}
	if stdout.String() != "out\n" {
		t.Fatalf("stdout = %q, want out newline", stdout.String())
	}
	if stderr.String() != "err\n" {
		t.Fatalf("stderr = %q, want err newline", stderr.String())
	}
}

func TestRunnerHandlesManyOutputLines(t *testing.T) {
	const lineCount = 50_000
	runner := Runner{Writer: Writer{}, ShellPath: "/bin/sh"}

	output, err := runner.Run(context.Background(), "i=1; while [ \"$i\" -le 50000 ]; do printf 'line %s\\n' \"$i\"; i=$((i + 1)); done", func(Chunk) {})
	if err != nil {
		t.Fatalf("Run returned error: %v", err)
	}

	if output.ExitCode != 0 {
		t.Fatalf("exit code = %d, want 0", output.ExitCode)
	}
	if len(output.LineRecords) != lineCount {
		t.Fatalf("line records = %d, want %d", len(output.LineRecords), lineCount)
	}
}

func TestRunnerDrainsLargeStdoutAndStderrStreamsWithoutBlocking(t *testing.T) {
	const lineCount = 20_000
	runner := Runner{Writer: Writer{}, ShellPath: "/bin/sh"}
	var mu sync.Mutex
	streamCounts := map[Stream]int{}

	command := `
i=1
while [ "$i" -le 20000 ]; do
  printf 'stdout %s\n' "$i"
  printf 'stderr %s\n' "$i" >&2
  i=$((i + 1))
done
`
	output, err := runner.Run(context.Background(), command, func(chunk Chunk) {
		mu.Lock()
		defer mu.Unlock()
		streamCounts[chunk.Stream] += len(chunk.LineRecords)
	})
	if err != nil {
		t.Fatalf("Run returned error: %v", err)
	}

	if output.ExitCode != 0 {
		t.Fatalf("exit code = %d, want 0", output.ExitCode)
	}
	if len(output.LineRecords) != lineCount*2 {
		t.Fatalf("line records = %d, want %d", len(output.LineRecords), lineCount*2)
	}
	if streamCounts[Stdout] != lineCount {
		t.Fatalf("stdout line count = %d, want %d", streamCounts[Stdout], lineCount)
	}
	if streamCounts[Stderr] != lineCount {
		t.Fatalf("stderr line count = %d, want %d", streamCounts[Stderr], lineCount)
	}
}

func containsHash(output Output, line string) bool {
	hash := hashline.Hash(line)
	for _, record := range output.LineRecords {
		if record.TextHash == hash {
			return true
		}
	}
	return false
}

func containsStream(streams []Stream, target Stream) bool {
	for _, stream := range streams {
		if stream == target {
			return true
		}
	}
	return false
}
