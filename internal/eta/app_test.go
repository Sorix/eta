package eta

import (
	"bytes"
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/Sorix/eta/internal/coordinator"
	"github.com/Sorix/eta/internal/process"
	"github.com/Sorix/eta/internal/progress"
	"github.com/Sorix/eta/internal/render"
)

func TestAppParseErrorReturnsUsageExitCode(t *testing.T) {
	app := testApp()

	code := app.Run(nil)

	if code != 2 {
		t.Fatalf("exit code = %d; want 2", code)
	}
	if !strings.Contains(app.Stderr.(*bytes.Buffer).String(), "eta: error:") {
		t.Fatalf("stderr = %q; want parse error", app.Stderr.(*bytes.Buffer).String())
	}
}

func TestAppClearModes(t *testing.T) {
	t.Run("clear", func(t *testing.T) {
		app := testApp()
		store := app.Store.(*fakeEtaStore)

		code := app.Run([]string{"--clear", "swift build"})

		if code != 0 {
			t.Fatalf("exit code = %d; want 0", code)
		}
		if got := store.clearedKeys; strings.Join(got, ",") != "resolved:swift build" {
			t.Fatalf("cleared keys = %#v; want resolved key", got)
		}
		if got := app.Stdout.(*bytes.Buffer).String(); got != "Cleared history for 'swift build'.\n" {
			t.Fatalf("stdout = %q", got)
		}
	})

	t.Run("clear all", func(t *testing.T) {
		app := testApp()
		store := app.Store.(*fakeEtaStore)

		code := app.Run([]string{"--clear-all"})

		if code != 0 {
			t.Fatalf("exit code = %d; want 0", code)
		}
		if store.clearAllCount != 1 {
			t.Fatalf("clearAllCount = %d; want 1", store.clearAllCount)
		}
		if got := app.Stdout.(*bytes.Buffer).String(); got != "Cleared all history.\n" {
			t.Fatalf("stdout = %q", got)
		}
	})
}

func TestAppRunUsesNameOrResolvedCommandKey(t *testing.T) {
	t.Run("custom name", func(t *testing.T) {
		app := testApp()
		store := app.Store.(*fakeEtaStore)
		runner := app.CommandRunner.(*fakeEtaRunner)
		runner.output = process.Output{TotalDuration: 1}

		code := app.Run([]string{"--name", "alias", "swift build"})

		if code != 0 {
			t.Fatalf("exit code = %d; want 0", code)
		}
		if got := store.saved[0].commandKey; got != "alias" {
			t.Fatalf("saved command key = %q; want alias", got)
		}
	})

	t.Run("empty custom name", func(t *testing.T) {
		app := testApp()
		store := app.Store.(*fakeEtaStore)
		runner := app.CommandRunner.(*fakeEtaRunner)
		runner.output = process.Output{TotalDuration: 1}

		code := app.Run([]string{"--name", "", "swift build"})

		if code != 0 {
			t.Fatalf("exit code = %d; want 0", code)
		}
		if got := store.saved[0].commandKey; got != "" {
			t.Fatalf("saved command key = %q; want empty custom name", got)
		}
	})

	t.Run("resolved command", func(t *testing.T) {
		app := testApp()
		store := app.Store.(*fakeEtaStore)
		runner := app.CommandRunner.(*fakeEtaRunner)
		runner.output = process.Output{TotalDuration: 1}

		code := app.Run([]string{"swift build"})

		if code != 0 {
			t.Fatalf("exit code = %d; want 0", code)
		}
		if got := store.saved[0].commandKey; got != "resolved:swift build" {
			t.Fatalf("saved command key = %q; want resolved command", got)
		}
	})
}

func TestAppWrappedCommandExitCodeIsReturned(t *testing.T) {
	app := testApp()
	runner := app.CommandRunner.(*fakeEtaRunner)
	runner.output = process.Output{TotalDuration: 1, ExitCode: 17}

	code := app.Run([]string{"swift build"})

	if code != 17 {
		t.Fatalf("exit code = %d; want 17", code)
	}
	if got := app.Stderr.(*bytes.Buffer).String(); got != "" {
		t.Fatalf("stderr = %q; want empty", got)
	}
}

func TestAppRunnerErrorReturnsFailure(t *testing.T) {
	app := testApp()
	runner := app.CommandRunner.(*fakeEtaRunner)
	runner.err = errors.New("runner failed")

	code := app.Run([]string{"swift build"})

	if code != 1 {
		t.Fatalf("exit code = %d; want 1", code)
	}
	if !strings.Contains(app.Stderr.(*bytes.Buffer).String(), "runner failed") {
		t.Fatalf("stderr = %q; want runner failed", app.Stderr.(*bytes.Buffer).String())
	}
}

func testApp() App {
	stdout := &bytes.Buffer{}
	stderr := &bytes.Buffer{}
	return App{
		Stdout:             stdout,
		Stderr:             stderr,
		Store:              &fakeEtaStore{},
		CommandRunner:      &fakeEtaRunner{},
		CommandKeyResolver: func(command string) string { return "resolved:" + command },
		RendererFactory: func(color render.Color, style render.BarStyle) coordinator.Renderer {
			_ = color
			_ = style
			return disabledEtaRenderer{}
		},
		Clock: func() time.Time { return time.Unix(100, 0) },
	}
}

type fakeEtaStore struct {
	history       *progress.CommandHistory
	clearedKeys   []string
	clearAllCount int
	saved         []fakeEtaSavedHistory
}

type fakeEtaSavedHistory struct {
	history         progress.CommandHistory
	commandKey      string
	maximumRunCount int
	staleAfterDays  int
}

func (s *fakeEtaStore) Load(commandKey string) (*progress.CommandHistory, error) {
	_ = commandKey
	return s.history, nil
}

func (s *fakeEtaStore) Save(history progress.CommandHistory, commandKey string, maximumRunCount, staleAfterDays int) error {
	s.saved = append(s.saved, fakeEtaSavedHistory{
		history:         history,
		commandKey:      commandKey,
		maximumRunCount: maximumRunCount,
		staleAfterDays:  staleAfterDays,
	})
	return nil
}

func (s *fakeEtaStore) Clear(commandKey string) error {
	s.clearedKeys = append(s.clearedKeys, commandKey)
	return nil
}

func (s *fakeEtaStore) ClearAll() error {
	s.clearAllCount++
	return nil
}

type fakeEtaRunner struct {
	output process.Output
	err    error
}

func (r *fakeEtaRunner) Run(ctx context.Context, command string, handler process.Handler) (process.Output, error) {
	_ = ctx
	_ = command
	_ = handler
	if r.err != nil {
		return process.Output{}, r.err
	}
	return r.output, nil
}

type disabledEtaRenderer struct{}

func (disabledEtaRenderer) Enabled() bool { return false }
func (disabledEtaRenderer) WriteFirstRunHeader() error {
	return nil
}
func (disabledEtaRenderer) Update(progress.ProgressFill, float64, float64) error {
	return nil
}
func (disabledEtaRenderer) ForceUpdate(progress.ProgressFill, float64, float64) error {
	return nil
}
func (disabledEtaRenderer) WriteOutputAndRedraw([]byte, process.Stream, progress.ProgressFill, float64, float64, bool) error {
	return nil
}
func (disabledEtaRenderer) Cleanup() error {
	return nil
}
func (disabledEtaRenderer) Finish(float64, float64) error {
	return nil
}
