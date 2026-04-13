package hashline

import (
	"crypto/md5"
	"crypto/sha256"
	"encoding/hex"
)

// Hash returns the lowercase hexadecimal MD5 digest for an output line.
func Hash(text string) string {
	sum := md5.Sum([]byte(text))
	return hex.EncodeToString(sum[:])
}

// NormalizedHash returns the lowercase hexadecimal MD5 digest for a normalized output line.
func NormalizedHash(text string) string {
	return Hash(Normalize(text))
}

// CommandFingerprint returns the lowercase hexadecimal SHA-256 digest for a command key.
func CommandFingerprint(commandKey string) string {
	sum := sha256.Sum256([]byte(commandKey))
	return hex.EncodeToString(sum[:])
}
