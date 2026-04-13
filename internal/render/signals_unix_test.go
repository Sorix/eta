//go:build unix

package render

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"
)

func TestSignalTrapCleanupResetAndReraiseOrder(t *testing.T) {
	signalCh := make(chan os.Signal, 1)
	recorder := &signalEventRecorder{}
	trap := newSignalTrap(
		[]os.Signal{syscall.SIGINT, syscall.SIGTERM},
		func() { recorder.append("cleanup") },
		signalCh,
		func() { recorder.append("stop") },
		func(signals ...os.Signal) { recorder.append("reset:" + signalList(signals)) },
		func(sig os.Signal) error {
			recorder.append("reraise:" + signalList([]os.Signal{sig}))
			return nil
		},
	)

	signalCh <- syscall.SIGTERM
	waitDone(t, trap.Done())

	want := []string{"cleanup", "stop", "reset:15", "reraise:15"}
	if got := recorder.snapshot(); strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("events = %#v; want %#v", got, want)
	}
}

func TestSignalTrapCancelIsIdempotentAndDoesNotCleanup(t *testing.T) {
	signalCh := make(chan os.Signal, 1)
	recorder := &signalEventRecorder{}
	trap := newSignalTrap(
		[]os.Signal{syscall.SIGINT, syscall.SIGTERM},
		func() { recorder.append("cleanup") },
		signalCh,
		func() { recorder.append("stop") },
		func(signals ...os.Signal) { recorder.append("reset:" + signalList(signals)) },
		nil,
	)

	trap.Cancel()
	trap.Cancel()

	want := []string{"stop", "reset:2,15"}
	if got := recorder.snapshot(); strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("events = %#v; want %#v", got, want)
	}
}

func TestSignalTrapSubprocessReraisesSignal(t *testing.T) {
	if childSignal := os.Getenv("ETA_SIGNAL_TRAP_CHILD"); childSignal != "" {
		runSignalTrapChild(t)
		return
	}

	for _, sig := range []syscall.Signal{syscall.SIGINT, syscall.SIGTERM} {
		t.Run(signalName(sig), func(t *testing.T) {
			marker := t.TempDir() + "/cleanup"
			cmd := exec.Command(os.Args[0], "-test.run=^TestSignalTrapSubprocessReraisesSignal$", "-test.count=1")
			cmd.Env = append(os.Environ(),
				"ETA_SIGNAL_TRAP_CHILD=1",
				"ETA_SIGNAL_TRAP_MARKER="+marker,
			)
			stdout, err := cmd.StdoutPipe()
			if err != nil {
				t.Fatalf("StdoutPipe() error = %v", err)
			}
			var stderr strings.Builder
			cmd.Stderr = &stderr

			if err := cmd.Start(); err != nil {
				t.Fatalf("Start() error = %v", err)
			}

			scanner := bufio.NewScanner(stdout)
			if !scanner.Scan() {
				_ = cmd.Process.Kill()
				t.Fatalf("child did not report readiness: scan error = %v, stderr = %q", scanner.Err(), stderr.String())
			}
			if got := scanner.Text(); got != "ready" {
				_ = cmd.Process.Kill()
				t.Fatalf("child readiness line = %q; want ready", got)
			}

			if err := cmd.Process.Signal(sig); err != nil {
				_ = cmd.Process.Kill()
				t.Fatalf("Signal(%v) error = %v", sig, err)
			}

			err = cmd.Wait()
			if err == nil {
				t.Fatal("child exited successfully; want signal termination")
			}
			exitErr, ok := err.(*exec.ExitError)
			if !ok {
				t.Fatalf("Wait() error = %T %v; want ExitError", err, err)
			}
			status, ok := exitErr.Sys().(syscall.WaitStatus)
			if !ok || !status.Signaled() || status.Signal() != sig {
				t.Fatalf("child status = %#v; want signal %v, stderr = %q", exitErr.Sys(), sig, stderr.String())
			}

			data, err := os.ReadFile(marker)
			if err != nil {
				t.Fatalf("cleanup marker not written: %v, stderr = %q", err, stderr.String())
			}
			if string(data) != "cleanup" {
				t.Fatalf("cleanup marker = %q; want cleanup", data)
			}
		})
	}
}

func runSignalTrapChild(t *testing.T) {
	t.Helper()

	marker := os.Getenv("ETA_SIGNAL_TRAP_MARKER")
	if marker == "" {
		t.Fatal("ETA_SIGNAL_TRAP_MARKER is empty")
	}

	_ = NewSignalTrap(func() {
		_ = os.WriteFile(marker, []byte("cleanup"), 0o600)
	})
	fmt.Println("ready")

	select {}
}

func waitDone(t *testing.T, done <-chan struct{}) {
	t.Helper()

	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for signal trap")
	}
}

func signalName(sig syscall.Signal) string {
	switch sig {
	case syscall.SIGINT:
		return "SIGINT"
	case syscall.SIGTERM:
		return "SIGTERM"
	default:
		return fmt.Sprintf("signal-%d", sig)
	}
}

func signalList(signals []os.Signal) string {
	parts := make([]string, 0, len(signals))
	for _, sig := range signals {
		sysSignal, ok := sig.(syscall.Signal)
		if !ok {
			parts = append(parts, fmt.Sprint(sig))
			continue
		}
		parts = append(parts, fmt.Sprint(int(sysSignal)))
	}
	return strings.Join(parts, ",")
}

type signalEventRecorder struct {
	mu     sync.Mutex
	events []string
}

func (r *signalEventRecorder) append(event string) {
	r.mu.Lock()
	defer r.mu.Unlock()

	r.events = append(r.events, event)
}

func (r *signalEventRecorder) snapshot() []string {
	r.mu.Lock()
	defer r.mu.Unlock()

	return append([]string(nil), r.events...)
}
