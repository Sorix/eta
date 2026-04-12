import Foundation
@testable import ProcessProgress
import Testing

struct NormalizationCase: Sendable {
    let input: String
    let expected: String
}

@Suite("Line normalization and hashing")
struct LineNormalizationAndHashingTests {
    @Test("normalizes digit and whitespace runs", arguments: [
        NormalizationCase(input: "[3/100]   Compiling  Foo.swift", expected: "[N/N] Compiling Foo.swift"),
        NormalizationCase(input: "  Step  5  of  20  ", expected: "Step N of N"),
        NormalizationCase(input: "Downloaded\t128\nMB", expected: "Downloaded N MB"),
        NormalizationCase(input: "No counters here", expected: "No counters here"),
        NormalizationCase(input: "Build 001 finished in 12.34s", expected: "Build N finished in N.Ns"),
    ])
    func normalizesDigitAndWhitespaceRuns(_ testCase: NormalizationCase) {
        #expect(LineNormalizer.normalized(testCase.input) == testCase.expected)
    }

    @Test("line hashes are deterministic fixed-width hex and do not retain raw text")
    func lineHashesAreDeterministic() {
        let text = "secret build output 123"
        let hash = LineHash.hash(text)
        let normalizedHash = LineHash.normalizedHash(text)

        #expect(hash == LineHash.hash(text))
        #expect(normalizedHash == LineHash.normalizedHash(text))
        #expect(hash.count == 32)
        #expect(normalizedHash.count == 32)
        #expect(hash != text)
        #expect(normalizedHash != text)
        #expect(hash.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("command fingerprints are deterministic SHA-256 hex")
    func commandFingerprintsAreDeterministic() {
        let command = "swift build 2>&1 | xcbeautify --is-ci"
        let fingerprint = CommandFingerprint.hash(command)

        #expect(fingerprint == CommandFingerprint.hash(command))
        #expect(fingerprint.count == 64)
        #expect(fingerprint != command)
        #expect(fingerprint.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }
}
