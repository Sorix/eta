package hashline

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type hashlineFixture struct {
	Cases []struct {
		Name           string `json:"name"`
		Input          string `json:"input"`
		Normalized     string `json:"normalized"`
		TextHash       string `json:"textHash"`
		NormalizedHash string `json:"normalizedHash"`
	} `json:"cases"`
}

type testHelper interface {
	Helper()
	Fatalf(format string, args ...any)
}

func TestHashlineFixtures(t *testing.T) {
	var fixture hashlineFixture
	readFixture(t, "testdata/compat/hashline.json", &fixture)

	for _, tc := range fixture.Cases {
		t.Run(tc.Name, func(t *testing.T) {
			if got := Normalize(tc.Input); got != tc.Normalized {
				t.Fatalf("Normalize() = %q, want %q", got, tc.Normalized)
			}
			if got := Hash(tc.Input); got != tc.TextHash {
				t.Fatalf("Hash() = %q, want %q", got, tc.TextHash)
			}
			if got := NormalizedHash(tc.Input); got != tc.NormalizedHash {
				t.Fatalf("NormalizedHash() = %q, want %q", got, tc.NormalizedHash)
			}
		})
	}
}

func TestCommandFingerprint(t *testing.T) {
	const command = "go build 2>&1 | xcbeautify --is-ci"
	fingerprint := CommandFingerprint(command)

	if fingerprint != CommandFingerprint(command) {
		t.Fatal("CommandFingerprint is not deterministic")
	}
	if len(fingerprint) != 64 {
		t.Fatalf("len(CommandFingerprint) = %d, want 64", len(fingerprint))
	}
	if strings.Contains(fingerprint, command) {
		t.Fatal("CommandFingerprint retained raw command text")
	}
	if fingerprint != strings.ToLower(fingerprint) {
		t.Fatalf("CommandFingerprint = %q, want lowercase hex", fingerprint)
	}
}

func readFixture(t testHelper, path string, target any) {
	t.Helper()

	data, err := os.ReadFile(filepath.Join("..", "..", path))
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	if err := json.Unmarshal(data, target); err != nil {
		t.Fatalf("decode fixture: %v", err)
	}
}
