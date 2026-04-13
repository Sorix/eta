package cli

import "testing"

func TestParseRejectsInvalidModesAndRunCounts(t *testing.T) {
	tests := []struct {
		name string
		args []string
	}{
		{name: "no mode", args: []string{}},
		{name: "clear plus command", args: []string{"--clear", "echo hi", "echo hi"}},
		{name: "clear all plus command", args: []string{"--clear-all", "echo hi"}},
		{name: "clear plus clear all", args: []string{"--clear", "one", "--clear-all"}},
		{name: "zero runs", args: []string{"--runs", "0", "echo hi"}},
		{name: "negative runs", args: []string{"--runs", "-1", "echo hi"}},
		{name: "too many command arguments", args: []string{"echo", "hi"}},
		{name: "invalid color", args: []string{"--color", "orange", "echo hi"}},
		{name: "uppercase color", args: []string{"--color", "Cyan", "echo hi"}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if _, err := Parse(tt.args); err == nil {
				t.Fatalf("Parse(%q) succeeded; want error", tt.args)
			}
		})
	}
}

func TestParseRunModeDefaults(t *testing.T) {
	request, err := Parse([]string{"echo hi"})
	if err != nil {
		t.Fatalf("Parse() error = %v", err)
	}

	if request.Mode != ModeRun {
		t.Fatalf("Mode = %v; want ModeRun", request.Mode)
	}
	if request.Command != "echo hi" {
		t.Fatalf("Command = %q; want echo hi", request.Command)
	}
	if !request.CommandSet {
		t.Fatal("CommandSet = false; want true")
	}
	if request.MaximumRunCount != defaultMaximumRunCount {
		t.Fatalf("MaximumRunCount = %d; want %d", request.MaximumRunCount, defaultMaximumRunCount)
	}
	if request.Color != "green" {
		t.Fatalf("Color = %q; want green", request.Color)
	}
}

func TestParseRunModeOptions(t *testing.T) {
	request, err := Parse([]string{
		"--name", "build",
		"--quiet",
		"--solid",
		"--runs", "4",
		"--color", "cyan",
		"go build",
	})
	if err != nil {
		t.Fatalf("Parse() error = %v", err)
	}

	if request.Mode != ModeRun || request.Command != "go build" {
		t.Fatalf("request mode/command = (%v, %q); want run go build", request.Mode, request.Command)
	}
	if request.Name != "build" {
		t.Fatalf("Name = %q; want build", request.Name)
	}
	if !request.NameSet {
		t.Fatal("NameSet = false; want true")
	}
	if !request.Quiet {
		t.Fatal("Quiet = false; want true")
	}
	if !request.Solid {
		t.Fatal("Solid = false; want true")
	}
	if request.MaximumRunCount != 4 {
		t.Fatalf("MaximumRunCount = %d; want 4", request.MaximumRunCount)
	}
	if request.Color != "cyan" {
		t.Fatalf("Color = %q; want cyan", request.Color)
	}
}

func TestParseClearModes(t *testing.T) {
	clearRequest, err := Parse([]string{"--clear", "go build"})
	if err != nil {
		t.Fatalf("Parse(clear) error = %v", err)
	}
	if clearRequest.Mode != ModeClear || clearRequest.ClearCommand != "go build" {
		t.Fatalf("clear request = (%v, %q); want clear go build", clearRequest.Mode, clearRequest.ClearCommand)
	}
	if !clearRequest.ClearCommandSet {
		t.Fatal("ClearCommandSet = false; want true")
	}

	clearAllRequest, err := Parse([]string{"--clear-all"})
	if err != nil {
		t.Fatalf("Parse(clear-all) error = %v", err)
	}
	if clearAllRequest.Mode != ModeClearAll {
		t.Fatalf("Mode = %v; want ModeClearAll", clearAllRequest.Mode)
	}
}

func TestParseTreatsPresentEmptyStringsAsPresent(t *testing.T) {
	emptyCommand, err := Parse([]string{""})
	if err != nil {
		t.Fatalf("Parse(empty command) error = %v", err)
	}
	if emptyCommand.Mode != ModeRun || !emptyCommand.CommandSet || emptyCommand.Command != "" {
		t.Fatalf("empty command request = %+v; want run mode with empty command present", emptyCommand)
	}

	emptyClear, err := Parse([]string{"--clear", ""})
	if err != nil {
		t.Fatalf("Parse(empty clear) error = %v", err)
	}
	if emptyClear.Mode != ModeClear || !emptyClear.ClearCommandSet || emptyClear.ClearCommand != "" {
		t.Fatalf("empty clear request = %+v; want clear mode with empty command present", emptyClear)
	}

	emptyName, err := Parse([]string{"--name", "", "echo hi"})
	if err != nil {
		t.Fatalf("Parse(empty name) error = %v", err)
	}
	if !emptyName.NameSet || emptyName.Name != "" {
		t.Fatalf("empty name request = %+v; want empty name present", emptyName)
	}
}
