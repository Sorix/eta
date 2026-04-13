package render

import (
	"fmt"
	"os"
	"os/signal"
	"sync"
	"syscall"
)

// SignalTrap cleans up rendering before restoring and re-raising termination signals.
type SignalTrap struct {
	cancelOnce sync.Once
	cancel     chan struct{}
	done       chan struct{}
}

// NewSignalTrap traps SIGINT and SIGTERM.
func NewSignalTrap(cleanup func()) *SignalTrap {
	return NewSignalTrapForSignals([]os.Signal{syscall.SIGINT, syscall.SIGTERM}, cleanup)
}

// NewSignalTrapForSignals traps the provided signals.
func NewSignalTrapForSignals(signals []os.Signal, cleanup func()) *SignalTrap {
	signalCh := make(chan os.Signal, 1)
	signal.Notify(signalCh, signals...)

	return newSignalTrap(signals, cleanup, signalCh, func() {
		signal.Stop(signalCh)
	}, signal.Reset, reraiseSignal)
}

func newSignalTrap(signals []os.Signal, cleanup func(), signalCh <-chan os.Signal, stop func(), reset func(...os.Signal), reraise func(os.Signal) error) *SignalTrap {
	if cleanup == nil {
		cleanup = func() {}
	}
	if stop == nil {
		stop = func() {}
	}
	if reset == nil {
		reset = func(...os.Signal) {}
	}
	if reraise == nil {
		reraise = func(os.Signal) error { return nil }
	}

	trap := &SignalTrap{
		cancel: make(chan struct{}),
		done:   make(chan struct{}),
	}
	go trap.run(signals, cleanup, signalCh, stop, reset, reraise)
	return trap
}

// Cancel unregisters the signal trap and restores default signal handling.
func (t *SignalTrap) Cancel() {
	if t == nil {
		return
	}
	t.cancelOnce.Do(func() {
		close(t.cancel)
	})
	<-t.done
}

// Done is closed after the trap goroutine exits.
func (t *SignalTrap) Done() <-chan struct{} {
	if t == nil {
		done := make(chan struct{})
		close(done)
		return done
	}
	return t.done
}

func (t *SignalTrap) run(signals []os.Signal, cleanup func(), signalCh <-chan os.Signal, stop func(), reset func(...os.Signal), reraise func(os.Signal) error) {
	defer close(t.done)

	select {
	case sig := <-signalCh:
		cleanup()
		stop()
		reset(sig)
		_ = reraise(sig)
	case <-t.cancel:
		stop()
		reset(signals...)
	}
}

func reraiseSignal(sig os.Signal) error {
	sysSignal, ok := sig.(syscall.Signal)
	if !ok {
		return fmt.Errorf("reraise signal: unsupported signal %v", sig)
	}
	return syscall.Kill(os.Getpid(), sysSignal)
}
