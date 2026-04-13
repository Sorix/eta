package commandkey

import (
	"os"
	"strings"
	"unicode"
	"unicode/utf8"
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
//   - split the executable at the first shell whitespace run
//   - normalize the executable/rest separator to a single literal space
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
	executable, rest := splitCommand(trimmed)

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

	return cwd + "\n" + trimmed
}

func splitCommand(command string) (string, string) {
	firstSeparator := strings.IndexFunc(command, unicode.IsSpace)
	if firstSeparator < 0 {
		return command, ""
	}

	restStart := firstSeparator
	for restStart < len(command) {
		r, size := utf8DecodeRuneInString(command[restStart:])
		if !unicode.IsSpace(r) {
			break
		}
		restStart += size
	}

	if restStart >= len(command) {
		return command[:firstSeparator], ""
	}
	return command[:firstSeparator], " " + command[restStart:]
}

func utf8DecodeRuneInString(text string) (rune, int) {
	return utf8.DecodeRuneInString(text)
}
