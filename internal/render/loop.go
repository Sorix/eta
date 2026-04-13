package render

import (
	"sync"
	"time"

	"github.com/Sorix/eta/internal/progress"
)

// Updater receives periodic progress updates.
type Updater interface {
	Update(fill progress.ProgressFill, remainingTime, elapsedTime float64) error
}

type estimateSource interface {
	Estimate(elapsed float64) progress.ProgressEstimate
}

// RenderLoop drives periodic renderer updates.
type RenderLoop struct {
	cancelOnce sync.Once
	cancel     chan struct{}
	done       chan struct{}
}

// NewRenderLoop starts a progress render loop at the standard frame interval.
func NewRenderLoop(renderer Updater, estimator *progress.TimelineProgressEstimator, startTime time.Time, clock func() time.Time) *RenderLoop {
	ticker := time.NewTicker(minDrawInterval)
	return newRenderLoop(renderer, estimator, startTime, clock, ticker.C, ticker.Stop)
}

func newRenderLoop(renderer Updater, estimator estimateSource, startTime time.Time, clock func() time.Time, ticks <-chan time.Time, stopTicker func()) *RenderLoop {
	if clock == nil {
		clock = time.Now
	}
	if stopTicker == nil {
		stopTicker = func() {}
	}

	loop := &RenderLoop{
		cancel: make(chan struct{}),
		done:   make(chan struct{}),
	}

	go loop.run(renderer, estimator, startTime, clock, ticks, stopTicker)
	return loop
}

// Cancel stops future renderer updates.
func (l *RenderLoop) Cancel() {
	if l == nil {
		return
	}
	l.cancelOnce.Do(func() {
		close(l.cancel)
	})
}

// Done is closed after the loop goroutine exits.
func (l *RenderLoop) Done() <-chan struct{} {
	if l == nil {
		done := make(chan struct{})
		close(done)
		return done
	}
	return l.done
}

func (l *RenderLoop) run(renderer Updater, estimator estimateSource, startTime time.Time, clock func() time.Time, ticks <-chan time.Time, stopTicker func()) {
	defer close(l.done)
	defer stopTicker()

	for {
		select {
		case <-l.cancel:
			return
		case _, ok := <-ticks:
			if !ok {
				return
			}
			if renderer == nil || estimator == nil {
				continue
			}
			elapsed := clock().Sub(startTime).Seconds()
			estimate := estimator.Estimate(elapsed)
			_ = renderer.Update(estimate.Progress, displayRemainingTime(estimate), elapsed)
		}
	}
}

func displayRemainingTime(estimate progress.ProgressEstimate) float64 {
	if estimate.AdjustedExpectedTotalDuration <= 0 {
		return 0
	}
	return estimate.RemainingTime
}
