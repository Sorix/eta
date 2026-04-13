package commandkey

import (
	"os/exec"
	"path/filepath"
	"strings"
)

func realpath(path string) (string, bool) {
	resolved, err := filepath.EvalSymlinks(path)
	if err != nil {
		return "", false
	}
	absolute, err := filepath.Abs(resolved)
	if err != nil {
		return resolved, true
	}
	return absolute, true
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
