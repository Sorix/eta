package commandkey

import (
	"os/exec"
	"path/filepath"
	"strings"
)

func realpath(path string) (string, bool) {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return "", false
	}
	resolved, err := filepath.EvalSymlinks(absolute)
	if err != nil {
		return "", false
	}
	return resolved, true
}

func whichPath(executable string) (string, bool) {
	out, err := exec.Command("/usr/bin/which", executable).Output()
	if err != nil {
		return "", false
	}
	path := strings.TrimSpace(string(out))
	if path == "" {
		return "", false
	}
	return path, true
}
