package hashline

import (
	"strings"
	"unicode"
)

// Normalize prepares an output line for fuzzy matching.
func Normalize(text string) string {
	var builder strings.Builder
	builder.Grow(len(text))

	lastWasSpace := false
	lastWasNumber := false
	for _, r := range text {
		if unicode.IsNumber(r) {
			if !lastWasNumber {
				builder.WriteRune('N')
			}
			lastWasSpace = false
			lastWasNumber = true
			continue
		}

		if unicode.IsSpace(r) {
			if !lastWasSpace {
				builder.WriteRune(' ')
				lastWasSpace = true
			}
			lastWasNumber = false
			continue
		}

		builder.WriteRune(r)
		lastWasSpace = false
		lastWasNumber = false
	}

	return strings.Trim(builder.String(), " \t")
}
