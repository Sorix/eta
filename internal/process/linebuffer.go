package process

import (
	"strings"
	"unicode/utf8"

	"github.com/Sorix/eta/internal/hashline"
	"github.com/Sorix/eta/internal/progress"
)

type lineBufferUpdate struct {
	lineRecords         []progress.LineRecord
	containsPartialLine bool
}

type outputLineBuffer struct {
	pending []byte
}

func (b *outputLineBuffer) append(data []byte, offsetSeconds float64) lineBufferUpdate {
	var records []progress.LineRecord
	for _, value := range data {
		if value == '\n' {
			if record, ok := makeRecord(b.pending, offsetSeconds); ok {
				records = append(records, record)
			}
			b.pending = b.pending[:0]
			continue
		}
		b.pending = append(b.pending, value)
	}

	return lineBufferUpdate{
		lineRecords:         records,
		containsPartialLine: len(b.pending) > 0,
	}
}

func (b *outputLineBuffer) flushFinalLine(offsetSeconds float64) []progress.LineRecord {
	defer func() {
		b.pending = nil
	}()

	record, ok := makeRecord(b.pending, offsetSeconds)
	if !ok {
		return nil
	}
	return []progress.LineRecord{record}
}

func makeRecord(lineData []byte, offsetSeconds float64) (progress.LineRecord, bool) {
	if len(lineData) == 0 || !utf8.Valid(lineData) {
		return progress.LineRecord{}, false
	}

	line := string(lineData)
	line = strings.TrimSuffix(line, "\r")
	if line == "" {
		return progress.LineRecord{}, false
	}

	return progress.LineRecord{
		TextHash:       hashline.Hash(line),
		NormalizedHash: hashline.NormalizedHash(line),
		OffsetSeconds:  offsetSeconds,
	}, true
}
