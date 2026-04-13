package eta

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/Sorix/eta/internal/cli"
	"github.com/Sorix/eta/internal/commandkey"
	"github.com/Sorix/eta/internal/coordinator"
	"github.com/Sorix/eta/internal/history"
	"github.com/Sorix/eta/internal/process"
	"github.com/Sorix/eta/internal/progress"
	"github.com/Sorix/eta/internal/render"
)

type store interface {
	Load(commandKey string) (*progress.CommandHistory, error)
	Save(history progress.CommandHistory, commandKey string, maximumRunCount, staleAfterDays int) error
	Clear(commandKey string) error
	ClearAll() error
}

// App contains the process-bound dependencies for eta.
type App struct {
	Stdout io.Writer
	Stderr io.Writer

	Store              store
	NewStore           func() (store, error)
	CommandKeyResolver func(string) string
	CommandRunner      coordinator.CommandRunner
	RendererFactory    coordinator.RendererFactory
	RenderLoopFactory  coordinator.RenderLoopFactory
	SignalTrapFactory  coordinator.SignalTrapFactory
	Clock              coordinator.Clock
}

// Main is the production wiring boundary for the eta command.
func Main(args []string) int {
	return App{
		Stdout: os.Stdout,
		Stderr: os.Stderr,
	}.Run(args)
}

// Run parses arguments, executes the selected mode, and returns a process exit code.
func (a App) Run(args []string) int {
	stdout := a.Stdout
	if stdout == nil {
		stdout = io.Discard
	}
	stderr := a.Stderr
	if stderr == nil {
		stderr = io.Discard
	}

	request, err := cli.Parse(args)
	if err != nil {
		fmt.Fprintf(stderr, "eta: error: %v\n", err)
		return 2
	}

	if request.Mode == cli.ModeHelp {
		fmt.Fprint(stdout, cli.Usage())
		return 0
	}

	store, err := a.historyStore()
	if err != nil {
		fmt.Fprintf(stderr, "eta: error: %v\n", err)
		return 1
	}

	resolve := a.CommandKeyResolver
	if resolve == nil {
		resolve = commandkey.Resolve
	}

	switch request.Mode {
	case cli.ModeClear:
		if err := store.Clear(resolve(request.ClearCommand)); err != nil {
			fmt.Fprintf(stderr, "eta: error: %v\n", err)
			return 1
		}
		fmt.Fprintf(stdout, "Cleared history for '%s'.\n", request.ClearCommand)
		return 0
	case cli.ModeClearAll:
		if err := store.ClearAll(); err != nil {
			fmt.Fprintf(stderr, "eta: error: %v\n", err)
			return 1
		}
		fmt.Fprintln(stdout, "Cleared all history.")
		return 0
	case cli.ModeRun:
		return a.runCommand(request, store, resolve, stderr)
	default:
		fmt.Fprintln(stderr, "eta: error: invalid command mode")
		return 2
	}
}

func (a App) runCommand(request cli.Request, store store, resolve func(string) string, stderr io.Writer) int {
	commandKey := request.Name
	if !request.NameSet {
		commandKey = resolve(request.Command)
	}

	style := render.Layered
	if request.Solid {
		style = render.Solid
	}

	clock := a.Clock
	if clock == nil {
		clock = time.Now
	}

	commandRunner := a.CommandRunner
	if commandRunner == nil {
		runner := process.NewRunner()
		commandRunner = runner
	}

	runCoordinator := coordinator.New(coordinator.Dependencies{
		HistoryStore:      store,
		CommandRunner:     commandRunner,
		RendererFactory:   a.RendererFactory,
		RenderLoopFactory: a.RenderLoopFactory,
		SignalTrapFactory: a.SignalTrapFactory,
		Clock:             clock,
		WriteWarning: func(warning string) {
			fmt.Fprintln(stderr, warning)
		},
	})

	err := runCoordinator.Run(context.Background(), coordinator.Request{
		Command:         request.Command,
		CommandKey:      commandKey,
		MaximumRunCount: request.MaximumRunCount,
		Quiet:           request.Quiet,
		Color:           render.Color(request.Color),
		BarStyle:        style,
	})
	if err == nil {
		return 0
	}

	var exitErr coordinator.ExitCodeError
	if errors.As(err, &exitErr) {
		return exitErr.Code
	}

	fmt.Fprintf(stderr, "eta: error: %v\n", err)
	return 1
}

func (a App) historyStore() (store, error) {
	if a.Store != nil {
		return a.Store, nil
	}
	if a.NewStore != nil {
		return a.NewStore()
	}

	if directory := os.Getenv("ETA_CACHE_DIR"); directory != "" {
		return history.NewStore(directory), nil
	}
	directory, err := history.DefaultDirectory()
	if err != nil {
		return nil, err
	}
	return history.NewStore(directory), nil
}
