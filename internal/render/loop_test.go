package render

import (
	"sync"
	"testing"
	"time"

	"github.com/Sorix/eta/internal/progress"
)

func TestRenderLoopTicksUpdateRenderer(t *testing.T) {
	start := time.Unix(100, 0)
	now := start.Add(1500 * time.Millisecond)
	ticks := make(chan time.Time, 1)
	renderer := newFakeUpdater()
	estimator := &fakeEstimator{
		estimate: progress.ProgressEstimate{
			Progress:                      progress.NewProgressFill(0.25, 0.50),
			RemainingTime:                 2,
			AdjustedExpectedTotalDuration: 4,
		},
	}
	loop := newRenderLoop(renderer, estimator, start, func() time.Time { return now }, ticks, nil)
	defer loop.Cancel()

	ticks <- now
	update := renderer.waitForUpdate(t)

	if update.fill != estimator.estimate.Progress {
		t.Fatalf("fill = %+v; want %+v", update.fill, estimator.estimate.Progress)
	}
	if update.remainingTime != 2 {
		t.Fatalf("remaining time = %v; want 2", update.remainingTime)
	}
	if update.elapsedTime != 1.5 {
		t.Fatalf("elapsed time = %v; want 1.5", update.elapsedTime)
	}
	if estimator.lastElapsed != 1.5 {
		t.Fatalf("estimator elapsed = %v; want 1.5", estimator.lastElapsed)
	}
}

func TestRenderLoopUsesZeroRemainingTimeWithoutAdjustedDuration(t *testing.T) {
	start := time.Unix(100, 0)
	ticks := make(chan time.Time, 1)
	renderer := newFakeUpdater()
	estimator := &fakeEstimator{
		estimate: progress.ProgressEstimate{
			Progress:                      progress.NewProgressFill(0, 0),
			RemainingTime:                 99,
			AdjustedExpectedTotalDuration: 0,
		},
	}
	loop := newRenderLoop(renderer, estimator, start, func() time.Time { return start }, ticks, nil)
	defer loop.Cancel()

	ticks <- start
	update := renderer.waitForUpdate(t)

	if update.remainingTime != 0 {
		t.Fatalf("remaining time = %v; want 0", update.remainingTime)
	}
}

func TestRenderLoopCancelIsIdempotentAndStopsUpdates(t *testing.T) {
	ticks := make(chan time.Time, 1)
	renderer := newFakeUpdater()
	stopCount := 0
	loop := newRenderLoop(renderer, &fakeEstimator{}, time.Now(), time.Now, ticks, func() {
		stopCount++
	})

	loop.Cancel()
	loop.Cancel()

	ticks <- time.Now()
	if got := renderer.updateCount(); got != 0 {
		t.Fatalf("updates after cancel = %d; want 0", got)
	}
	if stopCount != 1 {
		t.Fatalf("stop count = %d; want 1", stopCount)
	}
}

type fakeEstimator struct {
	mu          sync.Mutex
	estimate    progress.ProgressEstimate
	lastElapsed float64
}

func (e *fakeEstimator) Estimate(elapsed float64) progress.ProgressEstimate {
	e.mu.Lock()
	defer e.mu.Unlock()

	e.lastElapsed = elapsed
	return e.estimate
}

type renderUpdate struct {
	fill          progress.ProgressFill
	remainingTime float64
	elapsedTime   float64
}

type fakeUpdater struct {
	mu      sync.Mutex
	updates []renderUpdate
	notify  chan renderUpdate
}

func newFakeUpdater() *fakeUpdater {
	return &fakeUpdater{notify: make(chan renderUpdate, 8)}
}

func (u *fakeUpdater) Update(fill progress.ProgressFill, remainingTime, elapsedTime float64) error {
	update := renderUpdate{fill: fill, remainingTime: remainingTime, elapsedTime: elapsedTime}

	u.mu.Lock()
	u.updates = append(u.updates, update)
	u.mu.Unlock()

	u.notify <- update
	return nil
}

func (u *fakeUpdater) waitForUpdate(t *testing.T) renderUpdate {
	t.Helper()

	select {
	case update := <-u.notify:
		return update
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for update")
		return renderUpdate{}
	}
}

func (u *fakeUpdater) updateCount() int {
	u.mu.Lock()
	defer u.mu.Unlock()

	return len(u.updates)
}
