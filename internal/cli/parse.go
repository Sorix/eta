package cli

import (
	"fmt"
	"io"
	"strings"

	"github.com/spf13/pflag"
)

const defaultMaximumRunCount = 10

// Mode identifies the selected CLI action.
type Mode int

const (
	ModeRun Mode = iota + 1
	ModeClear
	ModeClearAll
)

// Request is the validated CLI request.
type Request struct {
	Mode            Mode
	Command         string
	CommandSet      bool
	Name            string
	NameSet         bool
	ClearCommand    string
	ClearCommandSet bool
	Quiet           bool
	Solid           bool
	MaximumRunCount int
	Color           string
}

// Parse parses and validates eta command-line arguments.
func Parse(args []string) (Request, error) {
	var request Request
	request.MaximumRunCount = defaultMaximumRunCount
	request.Color = "green"

	flags := pflag.NewFlagSet("eta", pflag.ContinueOnError)
	flags.SetOutput(io.Discard)
	flags.StringVar(&request.Name, "name", "", "custom command name")
	flags.StringVar(&request.ClearCommand, "clear", "", "clear command history")
	flags.BoolVar(&request.Quiet, "quiet", false, "learn without rendering")
	flags.BoolVar(&request.Solid, "solid", false, "draw solid progress")
	flags.IntVar(&request.MaximumRunCount, "runs", defaultMaximumRunCount, "history depth")
	flags.StringVar(&request.Color, "color", "green", "progress bar color")

	var clearAll bool
	flags.BoolVar(&clearAll, "clear-all", false, "clear all history")

	if err := flags.Parse(args); err != nil {
		return Request{}, err
	}

	if err := validateColor(request.Color); err != nil {
		return Request{}, err
	}
	request.NameSet = flags.Changed("name")
	request.ClearCommandSet = flags.Changed("clear")
	if request.NameSet && strings.TrimSpace(request.Name) == "" {
		return Request{}, fmt.Errorf("--name must not be empty")
	}
	if request.MaximumRunCount <= 0 {
		return Request{}, fmt.Errorf("--runs must be greater than 0")
	}

	positionals := flags.Args()
	if len(positionals) > 1 {
		return Request{}, fmt.Errorf("expected at most one command argument")
	}
	if len(positionals) == 1 {
		request.Command = positionals[0]
		request.CommandSet = true
	}
	if request.CommandSet && strings.TrimSpace(request.Command) == "" {
		return Request{}, fmt.Errorf("command must not be empty")
	}
	if request.ClearCommandSet && strings.TrimSpace(request.ClearCommand) == "" {
		return Request{}, fmt.Errorf("--clear must not be empty")
	}

	activeModes := 0
	if request.CommandSet {
		request.Mode = ModeRun
		activeModes++
	}
	if request.ClearCommandSet {
		request.Mode = ModeClear
		activeModes++
	}
	if clearAll {
		request.Mode = ModeClearAll
		activeModes++
	}

	if activeModes == 0 {
		return Request{}, fmt.Errorf("provide a command to run, or use --clear / --clear-all")
	}
	if activeModes > 1 {
		return Request{}, fmt.Errorf("use only one mode at a time: command, --clear, or --clear-all")
	}
	if request.Mode != ModeRun {
		if request.NameSet {
			return Request{}, fmt.Errorf("--name can only be used when running a command")
		}
		if flags.Changed("quiet") {
			return Request{}, fmt.Errorf("--quiet can only be used when running a command")
		}
		if flags.Changed("solid") {
			return Request{}, fmt.Errorf("--solid can only be used when running a command")
		}
		if flags.Changed("runs") {
			return Request{}, fmt.Errorf("--runs can only be used when running a command")
		}
		if flags.Changed("color") {
			return Request{}, fmt.Errorf("--color can only be used when running a command")
		}
	}

	return request, nil
}

func validateColor(color string) error {
	switch color {
	case "green", "yellow", "red", "blue", "magenta", "cyan", "white":
		return nil
	default:
		return fmt.Errorf("invalid --color %q", color)
	}
}
