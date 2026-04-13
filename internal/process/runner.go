package process

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"sync"
	"time"

	"github.com/Sorix/eta/internal/progress"
)

const readBufferSize = 32 * 1024

// Output is the result of running a shell command.
type Output struct {
	LineRecords   []progress.LineRecord
	TotalDuration float64
	ExitCode      int
}

// Chunk contains raw output bytes plus complete line records parsed from them.
type Chunk struct {
	RawOutput           []byte
	LineRecords         []progress.LineRecord
	Stream              Stream
	ContainsPartialLine bool
}

// Handler receives output chunks while a command is running.
type Handler func(Chunk)

// Runner runs shell commands and records hashed output lines.
type Runner struct {
	Writer    Writer
	ShellPath string
}

// NewRunner creates a runner that passes raw output through to stdout/stderr.
func NewRunner() Runner {
	return Runner{
		Writer:    StandardWriter(),
		ShellPath: defaultShellPath(),
	}
}

// Run executes command through the configured shell.
func (r Runner) Run(ctx context.Context, command string, handler Handler) (Output, error) {
	shellPath := r.ShellPath
	if shellPath == "" {
		shellPath = defaultShellPath()
	}

	cmd := exec.CommandContext(ctx, shellPath, "-c", command)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return Output{}, fmt.Errorf("stdout pipe: %w", err)
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return Output{}, fmt.Errorf("stderr pipe: %w", err)
	}

	start := time.Now()
	if err := cmd.Start(); err != nil {
		return Output{}, fmt.Errorf("start command: %w", err)
	}

	var collector lineRecordCollector
	stdoutCh := make(chan drainResult, 1)
	stderrCh := make(chan drainResult, 1)
	go func() {
		stdoutCh <- r.drain(stdout, Stdout, start, handler, &collector)
	}()
	go func() {
		stderrCh <- r.drain(stderr, Stderr, start, handler, &collector)
	}()

	waitErr := cmd.Wait()
	stdoutResult := <-stdoutCh
	stderrResult := <-stderrCh
	totalDuration := time.Since(start).Seconds()

	collector.append(stdoutResult.buffer.flushFinalLine(totalDuration)...)
	collector.append(stderrResult.buffer.flushFinalLine(totalDuration)...)

	output := Output{
		LineRecords:   collector.snapshot(),
		TotalDuration: totalDuration,
		ExitCode:      exitCode(waitErr),
	}

	if err := errors.Join(stdoutResult.err, stderrResult.err); err != nil {
		return output, err
	}
	if waitErr != nil {
		var exitErr *exec.ExitError
		if errors.As(waitErr, &exitErr) {
			return output, nil
		}
		return output, fmt.Errorf("wait command: %w", waitErr)
	}

	return output, nil
}

type drainResult struct {
	buffer outputLineBuffer
	err    error
}

// drain copies one output stream, hashes complete lines, and forwards raw bytes as they arrive.
func (r Runner) drain(reader io.Reader, stream Stream, start time.Time, handler Handler, collector *lineRecordCollector) drainResult {
	var result drainResult
	buffer := make([]byte, readBufferSize)

	for {
		n, err := reader.Read(buffer)
		if n > 0 {
			raw := append([]byte(nil), buffer[:n]...)
			offsetSeconds := time.Since(start).Seconds()
			update := result.buffer.append(raw, offsetSeconds)
			collector.append(update.lineRecords...)

			if handler != nil {
				handler(Chunk{
					RawOutput:           raw,
					LineRecords:         update.lineRecords,
					Stream:              stream,
					ContainsPartialLine: update.containsPartialLine,
				})
			} else if writeErr := r.Writer.Write(raw, stream); writeErr != nil {
				result.err = errors.Join(result.err, writeErr)
			}
		}
		if errors.Is(err, io.EOF) {
			return result
		}
		if err != nil {
			result.err = errors.Join(result.err, fmt.Errorf("drain output: %w", err))
			return result
		}
	}
}

type lineRecordCollector struct {
	mu      sync.Mutex
	records []progress.LineRecord
}

// append records lines in drain completion order from both output streams.
func (c *lineRecordCollector) append(records ...progress.LineRecord) {
	if len(records) == 0 {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()

	c.records = append(c.records, records...)
}

// snapshot returns a copy so callers can store records without mutating shared state.
func (c *lineRecordCollector) snapshot() []progress.LineRecord {
	c.mu.Lock()
	defer c.mu.Unlock()

	return append([]progress.LineRecord(nil), c.records...)
}

func defaultShellPath() string {
	if shell := os.Getenv("SHELL"); shell != "" {
		return shell
	}
	return "/bin/sh"
}

// exitCode extracts the process exit code, returning -1 when the command failed before one existed.
func exitCode(err error) int {
	if err == nil {
		return 0
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return exitErr.ExitCode()
	}
	return -1
}
