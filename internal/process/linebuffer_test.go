package process

import (
	"testing"

	"github.com/Sorix/eta/internal/hashline"
)

func TestOutputLineBufferBuffersSplitChunksAndFlushesFinalLine(t *testing.T) {
	var buffer outputLineBuffer

	first := buffer.append([]byte("hel"), 0.1)
	if len(first.lineRecords) != 0 {
		t.Fatalf("first records = %d, want 0", len(first.lineRecords))
	}
	if !first.containsPartialLine {
		t.Fatal("first containsPartialLine = false, want true")
	}

	second := buffer.append([]byte("lo\nwor"), 0.2)
	if len(second.lineRecords) != 1 || second.lineRecords[0].TextHash != hashline.Hash("hello") {
		t.Fatalf("second records = %#v, want hash for hello", second.lineRecords)
	}
	if !second.containsPartialLine {
		t.Fatal("second containsPartialLine = false, want true")
	}

	final := buffer.flushFinalLine(0.3)
	if len(final) != 1 || final[0].TextHash != hashline.Hash("wor") {
		t.Fatalf("final records = %#v, want hash for wor", final)
	}
}

func TestOutputLineBufferIgnoresBlankLinesAndStripsCRLF(t *testing.T) {
	var buffer outputLineBuffer

	update := buffer.append([]byte("\n\r\nvalue\r\n"), 1)
	if len(update.lineRecords) != 1 {
		t.Fatalf("records = %d, want 1", len(update.lineRecords))
	}
	if update.lineRecords[0].TextHash != hashline.Hash("value") {
		t.Fatalf("text hash = %q, want value hash", update.lineRecords[0].TextHash)
	}
	if update.containsPartialLine {
		t.Fatal("containsPartialLine = true, want false")
	}
}

func TestOutputLineBufferIgnoresInvalidUTF8Lines(t *testing.T) {
	var buffer outputLineBuffer

	update := buffer.append([]byte{0xff, '\n'}, 1)
	if len(update.lineRecords) != 0 {
		t.Fatalf("records = %d, want 0", len(update.lineRecords))
	}
	if update.containsPartialLine {
		t.Fatal("containsPartialLine = true, want false")
	}
}
