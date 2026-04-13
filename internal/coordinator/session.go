package coordinator

import (
	"time"

	"github.com/Sorix/eta/internal/progress"
)

type renderingSessionConfig struct {
	Renderer          Renderer
	Active            bool
	Estimator         *progress.TimelineProgressEstimator
	StartTime         time.Time
	Clock             Clock
	RenderLoopFactory RenderLoopFactory
	SignalTrapFactory SignalTrapFactory
}

type renderingSession struct {
	active   bool
	renderer Renderer
	loop     RenderLoop
	trap     SignalTrap
	didEnd   bool
}

func newRenderingSession(config renderingSessionConfig) *renderingSession {
	session := &renderingSession{
		active:   config.Active,
		renderer: config.Renderer,
	}
	if !config.Active {
		return session
	}

	estimate := config.Estimator.Estimate(0)
	_ = config.Renderer.ForceUpdate(estimate.Progress, displayRemainingTime(estimate), 0)

	loop := config.RenderLoopFactory(RenderLoopConfig{
		Renderer:  config.Renderer,
		Estimator: config.Estimator,
		StartTime: config.StartTime,
		Clock:     config.Clock,
	})
	session.loop = loop
	session.trap = config.SignalTrapFactory(func() {
		if loop != nil {
			loop.Cancel()
		}
		_ = config.Renderer.Cleanup()
	})
	return session
}

func (s *renderingSession) end(cleanupOnly bool) {
	if s == nil || s.didEnd {
		return
	}
	s.didEnd = true
	if s.loop != nil {
		s.loop.Cancel()
	}
	if s.trap != nil {
		s.trap.Cancel()
	}
	if cleanupOnly && s.active {
		_ = s.renderer.Cleanup()
	}
}

func (s *renderingSession) finish(elapsed, expectedDuration float64) {
	if s == nil || !s.active {
		return
	}
	_ = s.renderer.Finish(elapsed, expectedDuration)
}
