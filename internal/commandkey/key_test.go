package commandkey

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestResolvePathInvocationUsesRealpathWithoutCwd(t *testing.T) {
	r := testResolver(
		"/workspace/project",
		map[string]string{"./scripts/build.sh": "/workspace/project/scripts/build.sh"},
		nil,
	)

	got := r.resolve("./scripts/build.sh --flag")
	want := "/workspace/project/scripts/build.sh --flag"
	if got != want {
		t.Fatalf("resolve path invocation = %q, want %q", got, want)
	}
}

func TestResolveBareExecutableUsesCwdAndWhichPath(t *testing.T) {
	r := testResolver(
		"/workspace/project",
		nil,
		map[string]string{"go": "/usr/local/bin/go"},
	)

	got := r.resolve("go build")
	want := "/workspace/project\n/usr/local/bin/go build"
	if got != want {
		t.Fatalf("resolve bare executable = %q, want %q", got, want)
	}
}

func TestResolveMissingExecutableUsesCwdAndOriginalCommand(t *testing.T) {
	r := testResolver("/workspace/project", nil, nil)

	got := r.resolve("  no_such_command_xyz --flag  ")
	want := "/workspace/project\nno_such_command_xyz --flag"
	if got != want {
		t.Fatalf("resolve missing executable = %q, want %q", got, want)
	}
}

func TestResolveMissingPathUsesCwdAndOriginalCommand(t *testing.T) {
	r := testResolver("/workspace/project", nil, nil)

	got := r.resolve("./missing.sh --flag")
	want := "/workspace/project\n./missing.sh --flag"
	if got != want {
		t.Fatalf("resolve missing path = %q, want %q", got, want)
	}
}

func TestResolveCanonicalizesExistingPathsAcrossRelativeAndAbsoluteForms(t *testing.T) {
	root := t.TempDir()
	script := filepath.Join(root, "work", "scripts", "task.sh")
	if err := os.MkdirAll(filepath.Dir(script), 0o755); err != nil {
		t.Fatalf("MkdirAll returned error: %v", err)
	}
	if err := os.WriteFile(script, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatalf("WriteFile returned error: %v", err)
	}

	cwd, err := os.Getwd()
	if err != nil {
		t.Fatalf("Getwd returned error: %v", err)
	}
	t.Cleanup(func() {
		if err := os.Chdir(cwd); err != nil {
			t.Fatalf("restore cwd: %v", err)
		}
	})
	nested := filepath.Join(root, "work", "nested")
	if err := os.MkdirAll(nested, 0o755); err != nil {
		t.Fatalf("MkdirAll returned error: %v", err)
	}

	if err := os.Chdir(filepath.Join(root, "work")); err != nil {
		t.Fatalf("Chdir work returned error: %v", err)
	}
	relativeKey := Resolve("./scripts/task.sh --flag")

	if err := os.Chdir(nested); err != nil {
		t.Fatalf("Chdir nested returned error: %v", err)
	}
	parentRelativeKey := Resolve("../scripts/task.sh --flag")
	absoluteKey := Resolve(script + " --flag")

	if relativeKey != parentRelativeKey {
		t.Fatalf("relative key = %q, parent-relative key = %q; want equal", relativeKey, parentRelativeKey)
	}
	if relativeKey != absoluteKey {
		t.Fatalf("relative key = %q, absolute key = %q; want equal", relativeKey, absoluteKey)
	}
}

func TestResolveSplitsAtFirstLiteralSpaceOnly(t *testing.T) {
	r := testResolver(
		"/workspace/project",
		nil,
		map[string]string{
			"go":   "/usr/local/bin/go",
			"tool": "/bin/tool-tab",
		},
	)

	tests := []struct {
		name    string
		command string
		want    string
	}{
		{
			name:    "normalizes repeated spaces after executable",
			command: "go  build",
			want:    "/workspace/project\n/usr/local/bin/go build",
		},
		{
			name:    "treats tabs like spaces after executable",
			command: "tool\targ next",
			want:    "/workspace/project\n/bin/tool-tab arg next",
		},
		{
			name:    "trims outer whitespace before resolving executable",
			command: "  go build  ",
			want:    "/workspace/project\n/usr/local/bin/go build",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := r.resolve(tc.command); got != tc.want {
				t.Fatalf("resolve(%q) = %q, want %q", tc.command, got, tc.want)
			}
		})
	}
}

func TestCommandKeyFixtures(t *testing.T) {
	var fixture commandKeyFixture
	readFixture(t, "testdata/compat/command-keys.json", &fixture)
	chdirRepoRoot(t)

	for _, tc := range fixture.Cases {
		t.Run(tc.Name, func(t *testing.T) {
			got := Resolve(tc.Command)
			want := portableCommandKey(t, tc.Command, tc.PortableTemplate)
			if got != want {
				t.Fatalf("Resolve(%q) = %q, want %q", tc.Command, got, want)
			}
		})
	}
}

type commandKeyFixture struct {
	Cases []struct {
		Name             string `json:"name"`
		Command          string `json:"command"`
		PortableTemplate string `json:"portableTemplate"`
	} `json:"cases"`
}

func testResolver(cwd string, realpaths, paths map[string]string) resolver {
	return resolver{
		cwd: func() (string, error) {
			return cwd, nil
		},
		realpath: func(path string) (string, bool) {
			resolved, ok := realpaths[path]
			return resolved, ok
		},
		which: func(executable string) (string, bool) {
			resolved, ok := paths[executable]
			return resolved, ok
		},
	}
}

func portableCommandKey(t *testing.T, command, template string) string {
	t.Helper()

	cwd, err := os.Getwd()
	if err != nil {
		t.Fatalf("get cwd: %v", err)
	}

	switch template {
	case "{cwd}\\n{which:ls} -la /tmp":
		return cwd + "\n" + mustWhich(t, "ls") + " -la /tmp"
	case "/usr/bin/env FOO=1":
		resolved, ok := realpath("/usr/bin/env")
		if !ok {
			t.Fatalf("realpath /usr/bin/env failed")
		}
		return resolved + " FOO=1"
	case "{cwd}\\nno_such_command_xyz --flag":
		return cwd + "\n" + command
	case "{cwd}\\n{which:go} build":
		return cwd + "\n" + mustWhich(t, "go") + " build"
	default:
		t.Fatalf("unsupported fixture template %q", template)
		return ""
	}
}

func mustWhich(t *testing.T, executable string) string {
	t.Helper()

	path, ok := whichPath(executable)
	if !ok {
		t.Fatalf("which %q failed", executable)
	}
	return path
}

func readFixture(t *testing.T, path string, target any) {
	t.Helper()

	data, err := os.ReadFile(filepath.Join("..", "..", path))
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	if err := json.Unmarshal(data, target); err != nil {
		t.Fatalf("decode fixture: %v", err)
	}
}

func chdirRepoRoot(t *testing.T) {
	t.Helper()

	cwd, err := os.Getwd()
	if err != nil {
		t.Fatalf("get cwd: %v", err)
	}
	repoRoot := filepath.Clean(filepath.Join(cwd, "..", ".."))
	if err := os.Chdir(repoRoot); err != nil {
		t.Fatalf("chdir repo root: %v", err)
	}
	t.Cleanup(func() {
		if err := os.Chdir(cwd); err != nil {
			t.Fatalf("restore cwd: %v", err)
		}
	})
}
