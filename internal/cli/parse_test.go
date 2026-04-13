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
		"swift build",
	})
	if err != nil {
		t.Fatalf("Parse() error = %v", err)
	}

	if request.Mode != ModeRun || request.Command != "swift build" {
		t.Fatalf("request mode/command = (%v, %q); want run swift build", request.Mode, request.Command)
	}
	if request.Name != "build" {
		t.Fatalf("Name = %q; want build", request.Name)
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
	clearRequest, err := Parse([]string{"--clear", "swift build"})
	if err != nil {
		t.Fatalf("Parse(clear) error = %v", err)
	}
	if clearRequest.Mode != ModeClear || clearRequest.ClearCommand != "swift build" {
		t.Fatalf("clear request = (%v, %q); want clear swift build", clearRequest.Mode, clearRequest.ClearCommand)
	}

	clearAllRequest, err := Parse([]string{"--clear-all"})
	if err != nil {
		t.Fatalf("Parse(clear-all) error = %v", err)
	}
	if clearAllRequest.Mode != ModeClearAll {
		t.Fatalf("Mode = %v; want ModeClearAll", clearAllRequest.Mode)
	}
}
