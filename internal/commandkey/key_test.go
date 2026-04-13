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
		map[string]string{"swift": "/usr/bin/swift"},
	)

	got := r.resolve("swift build")
	want := "/workspace/project\n/usr/bin/swift build"
	if got != want {
		t.Fatalf("resolve bare executable = %q, want %q", got, want)
	}
}

func TestResolveMissingExecutableUsesCwdAndOriginalCommand(t *testing.T) {
	r := testResolver("/workspace/project", nil, nil)

	got := r.resolve("no_such_command_xyz --flag")
	want := "/workspace/project\nno_such_command_xyz --flag"
	if got != want {
		t.Fatalf("resolve missing executable = %q, want %q", got, want)
	}
}

func TestResolveSplitsAtFirstLiteralSpaceOnly(t *testing.T) {
	r := testResolver(
		"/workspace/project",
		nil,
		map[string]string{
			"swift":     "/usr/bin/swift",
			"tool\targ": "/bin/tool-tab",
		},
	)

	tests := []struct {
		name    string
		command string
		want    string
	}{
		{
			name:    "preserves repeated spaces after executable",
			command: "swift  build",
			want:    "/workspace/project\n/usr/bin/swift  build",
		},
		{
			name:    "does not split on tab",
			command: "tool\targ next",
			want:    "/workspace/project\n/bin/tool-tab next",
		},
		{
			name:    "trims outer whitespace before resolving executable",
			command: "  swift build  ",
			want:    "/workspace/project\n/usr/bin/swift build",
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

func TestSwiftCommandKeyFixtures(t *testing.T) {
	var fixture commandKeyFixture
	readFixture(t, "testdata/swift-compat/command-keys.json", &fixture)
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
	case "{cwd}\\n{which:swift}  build":
		return cwd + "\n" + mustWhich(t, "swift") + "  build"
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
