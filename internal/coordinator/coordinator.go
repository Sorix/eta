package coordinator

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/Sorix/eta/internal/process"
	"github.com/Sorix/eta/internal/progress"
	"github.com/Sorix/eta/internal/render"
)

const staleAfterDays = 90

// Request contains the options needed to run one wrapped command.
type Request struct {
	Command         string
	CommandKey      string
	MaximumRunCount int
	Quiet           bool
	Color           render.Color
	BarStyle        render.BarStyle
}

// ExitCodeError reports a wrapped command's non-zero exit code.
type ExitCodeError struct {
	Code int
}

// Error formats the wrapped command's exit code for callers that surface it directly.
func (e ExitCodeError) Error() string {
	return fmt.Sprintf("command exited with code %d", e.Code)
}

// HistoryStore loads and saves command history.
type HistoryStore interface {
	Load(commandKey string) (*progress.CommandHistory, error)
	Save(history progress.CommandHistory, commandKey string, maximumRunCount, staleAfterDays int) error
}

// CommandRunner runs wrapped shell commands.
type CommandRunner interface {
	Run(ctx context.Context, command string, handler process.Handler) (process.Output, error)
}

// Renderer owns progress rendering for the coordinator.
type Renderer interface {
	Enabled() bool
	WriteFirstRunHeader() error
	Update(fill progress.ProgressFill, remainingTime, elapsedTime float64) error
	ForceUpdate(fill progress.ProgressFill, remainingTime, elapsedTime float64) error
	WriteOutputAndRedraw(rawOutput []byte, stream process.Stream, fill progress.ProgressFill, remainingTime, elapsedTime float64, containsPartialLine bool) error
	Cleanup() error
	Finish(elapsed, expectedDuration float64) error
}

// RenderLoop is the active progress redraw loop.
type RenderLoop interface {
	Cancel()
}

// SignalTrap is the active signal cleanup trap.
type SignalTrap interface {
	Cancel()
}

// RendererFactory builds a renderer for one coordinator run.
type RendererFactory func(color render.Color, style render.BarStyle) Renderer

// RenderLoopFactory starts the periodic redraw loop for one coordinator run.
type RenderLoopFactory func(config RenderLoopConfig) RenderLoop

// SignalTrapFactory installs cleanup logic for interrupt and termination signals.
type SignalTrapFactory func(cleanup func()) SignalTrap

// Clock returns the current time and is injected for deterministic tests.
type Clock func() time.Time

// WarningWriter reports non-fatal problems, such as history save failures.
type WarningWriter func(string)

// RenderLoopConfig carries render loop dependencies.
type RenderLoopConfig struct {
	Renderer  Renderer
	Estimator *progress.TimelineProgressEstimator
	StartTime time.Time
	Clock     Clock
}

// Dependencies contains replaceable coordinator collaborators.
type Dependencies struct {
	HistoryStore      HistoryStore
	CommandRunner     CommandRunner
	RendererFactory   RendererFactory
	RenderLoopFactory RenderLoopFactory
	SignalTrapFactory SignalTrapFactory
	Clock             Clock
	WriteWarning      WarningWriter
}

// Coordinator runs the high-level command workflow.
type Coordinator struct {
	historyStore      HistoryStore
	commandRunner     CommandRunner
	rendererFactory   RendererFactory
	renderLoopFactory RenderLoopFactory
	signalTrapFactory SignalTrapFactory
	clock             Clock
	writeWarning      WarningWriter
}

// New creates a command-run coordinator.
func New(deps Dependencies) Coordinator {
	coordinator := Coordinator{
		historyStore:      deps.HistoryStore,
		commandRunner:     deps.CommandRunner,
		rendererFactory:   deps.RendererFactory,
		renderLoopFactory: deps.RenderLoopFactory,
		signalTrapFactory: deps.SignalTrapFactory,
		clock:             deps.Clock,
		writeWarning:      deps.WriteWarning,
	}
	if coordinator.commandRunner == nil {
		runner := process.NewRunner()
		coordinator.commandRunner = runner
	}
	if coordinator.rendererFactory == nil {
		coordinator.rendererFactory = func(color render.Color, style render.BarStyle) Renderer {
			return render.NewRenderer(color, style)
		}
	}
	if coordinator.renderLoopFactory == nil {
		coordinator.renderLoopFactory = func(config RenderLoopConfig) RenderLoop {
			return render.NewRenderLoop(config.Renderer, config.Estimator, config.StartTime, config.Clock)
		}
	}
	if coordinator.signalTrapFactory == nil {
		coordinator.signalTrapFactory = func(cleanup func()) SignalTrap {
			return render.NewSignalTrap(cleanup)
		}
	}
	if coordinator.clock == nil {
		coordinator.clock = time.Now
	}
	if coordinator.writeWarning == nil {
		coordinator.writeWarning = func(string) {}
	}
	return coordinator
}

// Run executes the command workflow and saves successful history.
func (c Coordinator) Run(ctx context.Context, request Request) error {
	if c.historyStore == nil {
		return fmt.Errorf("history store is required")
	}
	if request.MaximumRunCount <= 0 {
		return fmt.Errorf("maximum run count must be greater than 0")
	}

	history, err := c.historyStore.Load(request.CommandKey)
	if err != nil {
		return err
	}

	estimator := progress.NewTimelineProgressEstimatorFromHistory(history)
	renderer := c.rendererFactory(request.Color, request.BarStyle)
	hasHistory := estimator.HasHistory()
	shouldRenderProgress := !request.Quiet && renderer.Enabled() && hasHistory

	if !request.Quiet && renderer.Enabled() && !hasHistory {
		_ = renderer.WriteFirstRunHeader()
	}

	startTime := c.clock()
	session := newRenderingSession(renderingSessionConfig{
		Renderer:          renderer,
		Active:            shouldRenderProgress,
		Estimator:         estimator,
		StartTime:         startTime,
		Clock:             c.clock,
		RenderLoopFactory: c.renderLoopFactory,
		SignalTrapFactory: c.signalTrapFactory,
	})

	output, err := c.runCommand(ctx, request.Command, session.active, startTime, estimator, renderer)
	if err != nil {
		session.end(true)
		return err
	}

	if output.ExitCode != 0 {
		session.end(true)
		return ExitCodeError{Code: output.ExitCode}
	}

	session.end(false)
	session.finish(output.TotalDuration, estimator.ExpectedTotalDuration())
	c.saveSuccessfulRun(output, history, request)
	return nil
}

// runCommand streams command output through the renderer while keeping progress state in sync.
func (c Coordinator) runCommand(ctx context.Context, command string, renderingProgress bool, startTime time.Time, estimator *progress.TimelineProgressEstimator, renderer Renderer) (process.Output, error) {
	if !renderingProgress {
		return c.commandRunner.Run(ctx, command, nil)
	}

	var handlerMu sync.Mutex
	var handlerErr error
	handler := func(chunk process.Chunk) {
		elapsed := c.clock().Sub(startTime).Seconds()
		estimate := estimator.Estimate(elapsed)
		for _, record := range chunk.LineRecords {
			estimate = estimator.ObserveCurrentLine(record, elapsed)
		}

		if err := renderer.WriteOutputAndRedraw(chunk.RawOutput, chunk.Stream, estimate.Progress, displayRemainingTime(estimate), elapsed, chunk.ContainsPartialLine); err != nil {
			handlerMu.Lock()
			handlerErr = errors.Join(handlerErr, err)
			handlerMu.Unlock()
		}
	}

	output, err := c.commandRunner.Run(ctx, command, handler)
	handlerMu.Lock()
	joinedErr := errors.Join(err, handlerErr)
	handlerMu.Unlock()
	return output, joinedErr
}

// saveSuccessfulRun appends the latest successful output and warns instead of failing on save errors.
func (c Coordinator) saveSuccessfulRun(output process.Output, history *progress.CommandHistory, request Request) {
	updatedHistory := progress.CommandHistory{}
	if history != nil {
		updatedHistory.Runs = append(updatedHistory.Runs, history.Runs...)
	}
	updatedHistory.Runs = append(updatedHistory.Runs, progress.CommandRun{
		Date:          c.clock(),
		TotalDuration: output.TotalDuration,
		LineRecords:   output.LineRecords,
	})

	if err := c.historyStore.Save(updatedHistory, request.CommandKey, request.MaximumRunCount, staleAfterDays); err != nil {
		c.writeWarning(fmt.Sprintf("eta: warning: failed to save history: %v", err))
	}
}

// displayRemainingTime hides the ETA display when the estimate has no usable baseline.
func displayRemainingTime(estimate progress.ProgressEstimate) float64 {
	if estimate.AdjustedExpectedTotalDuration <= 0 {
		return 0
	}
	return estimate.RemainingTime
}
