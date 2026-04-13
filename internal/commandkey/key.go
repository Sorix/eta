package commandkey

import (
	"os"
	"strings"
)

type resolver struct {
	cwd      func() (string, error)
	realpath func(string) (string, bool)
	which    func(string) (string, bool)
}

// Resolve builds the stable command key used for history lookup.
//
// It intentionally mirrors the Swift CLI:
//   - trim leading/trailing whitespace before identifying the executable
//   - split the executable at the first literal space only
//   - canonicalize existing path-style executable names without adding cwd
//   - prefix cwd for bare executables, including names unresolved on PATH
func Resolve(command string) string {
	return defaultResolver().resolve(command)
}

func defaultResolver() resolver {
	return resolver{
		cwd:      os.Getwd,
		realpath: realpath,
		which:    whichPath,
	}
}

func (r resolver) resolve(command string) string {
	trimmed := strings.TrimSpace(command)
	firstSpace := strings.Index(trimmed, " ")

	executable := trimmed
	rest := ""
	if firstSpace >= 0 {
		executable = trimmed[:firstSpace]
		rest = trimmed[firstSpace:]
	}

	if strings.Contains(executable, "/") {
		if resolved, ok := r.realpath(executable); ok {
			return resolved + rest
		}
	}

	cwd, err := r.cwd()
	if err != nil {
		cwd = ""
	}
	if resolved, ok := r.which(executable); ok {
		return cwd + "\n" + resolved + rest
	}

	return cwd + "\n" + command
}
