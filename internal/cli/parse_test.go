package cli

import (
	"strings"
	"testing"
)

func TestParseRejectsInvalidModesAndRunCounts(t *testing.T) {
	tests := []struct {
		name string
		args []string
	}{
		{name: "quiet without mode", args: []string{"--quiet"}},
		{name: "clear plus command", args: []string{"--clear", "echo hi", "echo hi"}},
		{name: "clear all plus command", args: []string{"--clear-all", "echo hi"}},
		{name: "clear plus clear all", args: []string{"--clear", "one", "--clear-all"}},
		{name: "zero runs", args: []string{"--runs", "0", "echo hi"}},
		{name: "negative runs", args: []string{"--runs", "-1", "echo hi"}},
		{name: "text runs", args: []string{"--runs", "many", "echo hi"}},
		{name: "too many command arguments", args: []string{"echo", "hi"}},
		{name: "invalid color", args: []string{"--color", "orange", "echo hi"}},
		{name: "uppercase color", args: []string{"--color", "Cyan", "echo hi"}},
		{name: "empty explicit name", args: []string{"--name", "", "echo hi"}},
		{name: "whitespace explicit name", args: []string{"--name", " \t ", "echo hi"}},
		{name: "empty command", args: []string{""}},
		{name: "whitespace command", args: []string{" \t "}},
		{name: "empty clear command", args: []string{"--clear", ""}},
		{name: "whitespace clear command", args: []string{"--clear", " \t "}},
		{name: "name in clear mode", args: []string{"--name", "alias", "--clear", "echo hi"}},
		{name: "quiet in clear all mode", args: []string{"--quiet", "--clear-all"}},
		{name: "solid in clear mode", args: []string{"--solid", "--clear", "echo hi"}},
		{name: "runs in clear mode", args: []string{"--runs", "5", "--clear", "echo hi"}},
		{name: "color in clear all mode", args: []string{"--color", "cyan", "--clear-all"}},
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

func TestParseHelpMode(t *testing.T) {
	tests := [][]string{
		{},
		{"--help"},
		{"-h"},
	}

	for _, args := range tests {
		request, err := Parse(args)
		if err != nil {
			t.Fatalf("Parse(%q) error = %v", args, err)
		}
		if request.Mode != ModeHelp {
			t.Fatalf("Parse(%q) mode = %v; want ModeHelp", args, request.Mode)
		}
	}
}

func TestUsageIncludesCoreSections(t *testing.T) {
	usage := Usage()

	for _, fragment := range []string{
		"Usage:\n  eta [flags] '<command>'",
		"eta --clear '<command>'",
		"Examples:\n  eta 'go test ./...'",
		"--help",
		"--clear-all",
	} {
		if !strings.Contains(usage, fragment) {
			t.Fatalf("Usage() missing %q in:\n%s", fragment, usage)
		}
	}
}
