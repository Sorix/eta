package coordinator

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/Sorix/eta/internal/hashline"
	"github.com/Sorix/eta/internal/process"
	"github.com/Sorix/eta/internal/progress"
	"github.com/Sorix/eta/internal/render"
)

func TestCoordinatorSuccessfulCommandSavesHistoryWithRequestSettings(t *testing.T) {
	harness := newCoordinatorHarness()
	harness.runner.output = process.Output{
		LineRecords:   []progress.LineRecord{makeCoordinatorLine("Done", 1)},
		TotalDuration: 1,
		ExitCode:      0,
	}

	err := harness.coordinator().Run(context.Background(), harness.request(func(request *Request) {
		request.MaximumRunCount = 3
		request.Color = render.Magenta
		request.BarStyle = render.Solid
	}))
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}

	if got := harness.store.loadKeys; strings.Join(got, ",") != "alias" {
		t.Fatalf("load keys = %#v; want alias", got)
	}
	if len(harness.store.saved) != 1 {
		t.Fatalf("saved count = %d; want 1", len(harness.store.saved))
	}
	saved := harness.store.saved[0]
	if saved.commandKey != "alias" {
		t.Fatalf("saved command key = %q; want alias", saved.commandKey)
	}
	if saved.maximumRunCount != 3 {
		t.Fatalf("maximum run count = %d; want 3", saved.maximumRunCount)
	}
	if saved.history.Runs[0].TotalDuration != 1 || len(saved.history.Runs[0].LineRecords) != 1 {
		t.Fatalf("saved history = %+v; want one run with one line", saved.history)
	}
	if harness.capturedColor != render.Magenta || harness.capturedStyle != render.Solid {
		t.Fatalf("captured render options = (%v, %v); want magenta, solid", harness.capturedColor, harness.capturedStyle)
	}
}

func TestCoordinatorSuccessfulCommandAppendsToExistingHistory(t *testing.T) {
	harness := newCoordinatorHarness()
	harness.store.loadedHistory = makeCoordinatorHistory()
	harness.runner.output = process.Output{
		LineRecords:   []progress.LineRecord{makeCoordinatorLine("Done", 2)},
		TotalDuration: 2,
		ExitCode:      0,
	}

	if err := harness.coordinator().Run(context.Background(), harness.request()); err != nil {
		t.Fatalf("Run() error = %v", err)
	}

	saved := harness.store.saved[0]
	if len(saved.history.Runs) != 2 {
		t.Fatalf("saved runs = %d; want 2", len(saved.history.Runs))
	}
	if got := []float64{saved.history.Runs[0].TotalDuration, saved.history.Runs[1].TotalDuration}; got[0] != 10 || got[1] != 2 {
		t.Fatalf("saved durations = %#v; want [10 2]", got)
	}
	if saved.history.Runs[1].Date != harness.now {
		t.Fatalf("saved date = %v; want %v", saved.history.Runs[1].Date, harness.now)
	}
}

func TestCoordinatorNonZeroCommandDoesNotSaveHistory(t *testing.T) {
	harness := newCoordinatorHarness()
	harness.runner.output = process.Output{
		LineRecords:   []progress.LineRecord{makeCoordinatorLine("failed", 1)},
		TotalDuration: 1,
		ExitCode:      42,
	}

	err := harness.coordinator().Run(context.Background(), harness.request())
	var exitErr ExitCodeError
	if !errors.As(err, &exitErr) || exitErr.Code != 42 {
		t.Fatalf("Run() error = %T %v; want ExitCodeError 42", err, err)
	}
	if len(harness.store.saved) != 0 {
		t.Fatalf("saved count = %d; want 0", len(harness.store.saved))
	}
	if harness.loop.cancelCount != 0 || harness.trap.cancelCount != 0 {
		t.Fatalf("inactive lifecycle cancels = (%d, %d); want 0, 0", harness.loop.cancelCount, harness.trap.cancelCount)
	}
	if got := harness.renderer.events; strings.Join(got, ",") != "writeFirstRunHeader" {
		t.Fatalf("renderer events = %#v; want first-run header", got)
	}
}

func TestCoordinatorQuietModeBypassesRenderingAndSavesHistory(t *testing.T) {
	harness := newCoordinatorHarness()
	harness.store.loadedHistory = makeCoordinatorHistory()
	harness.runner.output = process.Output{LineRecords: []progress.LineRecord{makeCoordinatorLine("Done", 1)}, TotalDuration: 1}

	if err := harness.coordinator().Run(context.Background(), harness.request(func(request *Request) {
		request.Quiet = true
	})); err != nil {
		t.Fatalf("Run() error = %v", err)
	}

	if harness.runner.receivedHandler {
		t.Fatal("runner received handler; want nil handler")
	}
	if len(harness.renderer.events) != 0 {
		t.Fatalf("renderer events = %#v; want none", harness.renderer.events)
	}
	if harness.renderLoopCreateCount != 0 || harness.signalTrapCreateCount != 0 {
		t.Fatalf("lifecycle creates = (%d, %d); want 0, 0", harness.renderLoopCreateCount, harness.signalTrapCreateCount)
	}
	if len(harness.store.saved) != 1 {
		t.Fatalf("saved count = %d; want 1", len(harness.store.saved))
	}
}

func TestCoordinatorDisabledRendererSkipsRendering(t *testing.T) {
	harness := newCoordinatorHarness()
	harness.store.loadedHistory = makeCoordinatorHistory()
	harness.renderer.enabled = false
	harness.runner.output = process.Output{LineRecords: []progress.LineRecord{makeCoordinatorLine("Done", 1)}, TotalDuration: 1}

	if err := harness.coordinator().Run(context.Background(), harness.request()); err != nil {
		t.Fatalf("Run() error = %v", err)
	}

	if harness.runner.receivedHandler {
		t.Fatal("runner received handler; want nil handler")
	}
	if len(harness.renderer.events) != 0 {
		t.Fatalf("renderer events = %#v; want none", harness.renderer.events)
	}
	if harness.renderLoopCreateCount != 0 || harness.signalTrapCreateCount != 0 {
		t.Fatalf("lifecycle creates = (%d, %d); want 0, 0", harness.renderLoopCreateCount, harness.signalTrapCreateCount)
	}
}

func TestCoordinatorNoHistoryWritesFirstRunHeaderOnly(t *testing.T) {
	harness := newCoordinatorHarness()
	harness.runner.output = process.Output{LineRecords: []progress.LineRecord{makeCoordinatorLine("Done", 1)}, TotalDuration: 1}

	if err := harness.coordinator().Run(context.Background(), harness.request()); err != nil {
		t.Fatalf("Run() error = %v", err)
	}

	if harness.runner.receivedHandler {
		t.Fatal("runner received handler; want nil handler")
	}
	if got := harness.renderer.events; strings.Join(got, ",") != "writeFirstRunHeader" {
		t.Fatalf("renderer events = %#v; want first-run header", got)
	}
	if harness.renderLoopCreateCount != 0 || harness.signalTrapCreateCount != 0 {
		t.Fatalf("lifecycle creates = (%d, %d); want 0, 0", harness.renderLoopCreateCount, harness.signalTrapCreateCount)
	}
}

func TestCoordinatorExistingHistoryEnablesRenderingLifecycle(t *testing.T) {
	harness := newCoordinatorHarness()
	harness.store.loadedHistory = makeCoordinatorHistory()
	chunkLine := makeCoordinatorLine("Compile", 1)
	harness.runner.chunks = []process.Chunk{{
		RawOutput:           []byte("Compile\n"),
		LineRecords:         []progress.LineRecord{chunkLine},
		Stream:              process.Stdout,
		ContainsPartialLine: false,
	}}
	harness.runner.output = process.Output{
		LineRecords:   []progress.LineRecord{chunkLine},
		TotalDuration: 1,
		ExitCode:      0,
	}

	if err := harness.coordinator().Run(context.Background(), harness.request()); err != nil {
		t.Fatalf("Run() error = %v", err)
	}

	if !harness.runner.receivedHandler {
		t.Fatal("runner did not receive handler")
	}
	if harness.renderLoopCreateCount != 1 || harness.signalTrapCreateCount != 1 {
		t.Fatalf("lifecycle creates = (%d, %d); want 1, 1", harness.renderLoopCreateCount, harness.signalTrapCreateCount)
	}
	if harness.loop.cancelCount != 1 || harness.trap.cancelCount != 1 {
		t.Fatalf("lifecycle cancels = (%d, %d); want 1, 1", harness.loop.cancelCount, harness.trap.cancelCount)
	}
	if got := harness.renderer.events; strings.Join(got, ",") != "forceUpdate,writeOutputAndRedraw,finish" {
		t.Fatalf("renderer events = %#v; want active lifecycle", got)
	}
}

func TestCoordinatorRunnerFailureCleansUpActiveRenderingLifecycle(t *testing.T) {
	harness := newCoordinatorHarness()
	harness.store.loadedHistory = makeCoordinatorHistory()
	harness.runner.err = errRunFailed

	err := harness.coordinator().Run(context.Background(), harness.request())
	if !errors.Is(err, errRunFailed) {
		t.Fatalf("Run() error = %v; want errRunFailed", err)
	}
	if len(harness.store.saved) != 0 {
		t.Fatalf("saved count = %d; want 0", len(harness.store.saved))
	}
	if harness.loop.cancelCount != 1 || harness.trap.cancelCount != 1 {
		t.Fatalf("lifecycle cancels = (%d, %d); want 1, 1", harness.loop.cancelCount, harness.trap.cancelCount)
	}
	if got := harness.renderer.events; strings.Join(got, ",") != "forceUpdate,cleanup" {
		t.Fatalf("renderer events = %#v; want forceUpdate, cleanup", got)
	}
}

func TestCoordinatorSaveFailureWritesWarningWithoutFailingCommand(t *testing.T) {
	harness := newCoordinatorHarness()
	harness.store.saveErr = errSaveFailed
	harness.runner.output = process.Output{LineRecords: []progress.LineRecord{makeCoordinatorLine("Done", 1)}, TotalDuration: 1}

	if err := harness.coordinator().Run(context.Background(), harness.request()); err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if len(harness.warnings) != 1 || !strings.Contains(harness.warnings[0], "failed to save history") {
		t.Fatalf("warnings = %#v; want failed to save history", harness.warnings)
	}
}

var (
	errRunFailed  = errors.New("run failed")
	errSaveFailed = errors.New("save failed")
)

type coordinatorHarness struct {
	store                 *fakeHistoryStore
	runner                *fakeCommandRunner
	renderer              *fakeCoordinatorRenderer
	loop                  *fakeRenderLoop
	trap                  *fakeSignalTrap
	now                   time.Time
	warnings              []string
	capturedColor         render.Color
	capturedStyle         render.BarStyle
	renderLoopCreateCount int
	signalTrapCreateCount int
}

func newCoordinatorHarness() *coordinatorHarness {
	return &coordinatorHarness{
		store:    &fakeHistoryStore{},
		runner:   &fakeCommandRunner{},
		renderer: &fakeCoordinatorRenderer{enabled: true},
		loop:     &fakeRenderLoop{},
		trap:     &fakeSignalTrap{},
		now:      time.Unix(100, 0),
	}
}

func (h *coordinatorHarness) coordinator() Coordinator {
	return New(Dependencies{
		HistoryStore:  h.store,
		CommandRunner: h.runner,
		RendererFactory: func(color render.Color, style render.BarStyle) Renderer {
			h.capturedColor = color
			h.capturedStyle = style
			return h.renderer
		},
		RenderLoopFactory: func(RenderLoopConfig) RenderLoop {
			h.renderLoopCreateCount++
			return h.loop
		},
		SignalTrapFactory: func(cleanup func()) SignalTrap {
			h.signalTrapCreateCount++
			h.trap.cleanup = cleanup
			return h.trap
		},
		Clock: func() time.Time {
			return h.now
		},
		WriteWarning: func(warning string) {
			h.warnings = append(h.warnings, warning)
		},
	})
}

func (h *coordinatorHarness) request(mutators ...func(*Request)) Request {
	request := Request{
		Command:         "go build",
		CommandKey:      "alias",
		MaximumRunCount: 7,
		Color:           render.Cyan,
		BarStyle:        render.Layered,
	}
	for _, mutate := range mutators {
		mutate(&request)
	}
	return request
}

type savedHistory struct {
	history         progress.CommandHistory
	commandKey      string
	maximumRunCount int
	staleAfterDays  int
}

type fakeHistoryStore struct {
	loadedHistory *progress.CommandHistory
	saveErr       error
	loadKeys      []string
	saved         []savedHistory
}

func (s *fakeHistoryStore) Load(commandKey string) (*progress.CommandHistory, error) {
	s.loadKeys = append(s.loadKeys, commandKey)
	return s.loadedHistory, nil
}

func (s *fakeHistoryStore) Save(history progress.CommandHistory, commandKey string, maximumRunCount, staleAfterDays int) error {
	if s.saveErr != nil {
		return s.saveErr
	}
	s.saved = append(s.saved, savedHistory{
		history:         history,
		commandKey:      commandKey,
		maximumRunCount: maximumRunCount,
		staleAfterDays:  staleAfterDays,
	})
	return nil
}

type fakeCommandRunner struct {
	output          process.Output
	err             error
	commands        []string
	receivedHandler bool
	chunks          []process.Chunk
}

func (r *fakeCommandRunner) Run(ctx context.Context, command string, handler process.Handler) (process.Output, error) {
	_ = ctx
	r.commands = append(r.commands, command)
	r.receivedHandler = handler != nil
	if r.err != nil {
		return process.Output{}, r.err
	}
	for _, chunk := range r.chunks {
		if handler != nil {
			handler(chunk)
		}
	}
	return r.output, nil
}

type fakeCoordinatorRenderer struct {
	enabled bool
	events  []string
}

func (r *fakeCoordinatorRenderer) Enabled() bool { return r.enabled }

func (r *fakeCoordinatorRenderer) WriteFirstRunHeader() error {
	r.events = append(r.events, "writeFirstRunHeader")
	return nil
}

func (r *fakeCoordinatorRenderer) Update(fill progress.ProgressFill, remainingTime, elapsedTime float64) error {
	_ = fill
	_ = remainingTime
	_ = elapsedTime
	r.events = append(r.events, "update")
	return nil
}

func (r *fakeCoordinatorRenderer) ForceUpdate(fill progress.ProgressFill, remainingTime, elapsedTime float64) error {
	_ = fill
	_ = remainingTime
	_ = elapsedTime
	r.events = append(r.events, "forceUpdate")
	return nil
}

func (r *fakeCoordinatorRenderer) WriteOutputAndRedraw(rawOutput []byte, stream process.Stream, fill progress.ProgressFill, remainingTime, elapsedTime float64, containsPartialLine bool) error {
	_ = rawOutput
	_ = stream
	_ = fill
	_ = remainingTime
	_ = elapsedTime
	_ = containsPartialLine
	r.events = append(r.events, "writeOutputAndRedraw")
	return nil
}

func (r *fakeCoordinatorRenderer) Cleanup() error {
	r.events = append(r.events, "cleanup")
	return nil
}

func (r *fakeCoordinatorRenderer) Finish(elapsed, expectedDuration float64) error {
	_ = elapsed
	_ = expectedDuration
	r.events = append(r.events, "finish")
	return nil
}

type fakeRenderLoop struct {
	cancelCount int
}

func (l *fakeRenderLoop) Cancel() {
	l.cancelCount++
}

type fakeSignalTrap struct {
	cancelCount int
	cleanup     func()
}

func (t *fakeSignalTrap) Cancel() {
	t.cancelCount++
}

func makeCoordinatorLine(text string, offset float64) progress.LineRecord {
	return progress.LineRecord{
		TextHash:       hashline.Hash(text),
		NormalizedHash: hashline.NormalizedHash(text),
		OffsetSeconds:  offset,
	}
}

func makeCoordinatorHistory() *progress.CommandHistory {
	return &progress.CommandHistory{Runs: []progress.CommandRun{{
		Date:          time.Unix(1, 0),
		TotalDuration: 10,
		LineRecords: []progress.LineRecord{
			makeCoordinatorLine("Configure", 1),
			makeCoordinatorLine("Compile", 5),
			makeCoordinatorLine("Done", 10),
		},
	}}}
}
