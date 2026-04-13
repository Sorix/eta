package render

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/Sorix/eta/internal/progress"
)

func TestFormatterFixtures(t *testing.T) {
	var fixture formatterFixture
	readFixture(t, "testdata/compat/formatter.json", &fixture)

	tests := map[string]string{
		"green layered half progress width 40": BuildLine(
			progress.NewProgressFill(0.25, 0.5),
			5,
			5,
			40,
			Green,
			Layered,
		),
		"magenta solid full progress narrow width": BuildLine(
			progress.NewProgressFill(1, 1),
			0,
			61,
			20,
			Magenta,
			Solid,
		),
		"completion with expected delta": CompletionLine(12.4, 10),
		"completion without history":     CompletionLine(59.5, 0),
	}

	for _, tc := range fixture.Cases {
		t.Run(tc.Name, func(t *testing.T) {
			got, ok := tests[tc.Name]
			if !ok {
				t.Fatalf("missing local formatter case %q", tc.Name)
			}
			if got != tc.Raw {
				t.Fatalf("formatter output = %q, want %q", got, tc.Raw)
			}
		})
	}
}

func TestFormatTime(t *testing.T) {
	tests := []struct {
		seconds float64
		want    string
	}{
		{seconds: 0.4, want: "0s"},
		{seconds: 59.5, want: "1m00s"},
		{seconds: 61, want: "1m01s"},
		{seconds: -2.4, want: "-2s"},
		{seconds: -0.4, want: "0s"},
	}

	for _, tc := range tests {
		if got := FormatTime(tc.seconds); got != tc.want {
			t.Fatalf("FormatTime(%v) = %q, want %q", tc.seconds, got, tc.want)
		}
	}
}

type formatterFixture struct {
	Cases []struct {
		Name string `json:"name"`
		Raw  string `json:"raw"`
	} `json:"cases"`
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
