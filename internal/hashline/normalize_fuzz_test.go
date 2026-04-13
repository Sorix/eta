package hashline

import (
	"strings"
	"testing"
	"unicode"
)

func FuzzNormalize(f *testing.F) {
	var fixture hashlineFixture
	readFixture(f, "testdata/swift-compat/hashline.json", &fixture)
	for _, tc := range fixture.Cases {
		f.Add(tc.Input)
	}
	f.Add("")
	f.Add("   ")
	f.Add("\n\t123\r\n")
	f.Add("Version Ⅻ and stage ٣ complete")
	f.Add(string([]byte{0xff, '\n', '4'}))

	f.Fuzz(func(t *testing.T, input string) {
		normalized := Normalize(input)
		if again := Normalize(normalized); again != normalized {
			t.Fatalf("Normalize is not idempotent: Normalize(%q) = %q", normalized, again)
		}
		if strings.HasPrefix(normalized, " ") || strings.HasPrefix(normalized, "\t") ||
			strings.HasSuffix(normalized, " ") || strings.HasSuffix(normalized, "\t") {
			t.Fatalf("Normalize left trim whitespace in %q", normalized)
		}

		lastWasSpace := false
		for _, r := range normalized {
			if unicode.IsNumber(r) {
				t.Fatalf("Normalize left numeric rune %q in %q", r, normalized)
			}
			if unicode.IsSpace(r) {
				if lastWasSpace {
					t.Fatalf("Normalize left adjacent whitespace in %q", normalized)
				}
				lastWasSpace = true
			} else {
				lastWasSpace = false
			}
		}

		if Hash(input) != Hash(input) {
			t.Fatal("Hash is not deterministic")
		}
		if NormalizedHash(input) != Hash(normalized) {
			t.Fatal("NormalizedHash does not hash Normalize(input)")
		}
	})
}
