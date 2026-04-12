import Foundation
@testable import ProcessProgress
import Testing

@Suite("Line matching")
struct LineMatcherTests {
    @Test("matches exact hashes first and then normalized fallback")
    func matchesExactThenNormalized() {
        let lines = [
            makeLine("[1/3] Compiling Foo.swift", offset: 1),
            makeLine("[2/3] Compiling Bar.swift", offset: 2),
            makeLine("[3/3] Linking", offset: 3),
        ]
        let matcher = LineMatcher(runs: [
            CommandRun(date: Date(), totalDuration: 3, lineRecords: lines)
        ])

        #expect(matcher.match(text: "[2/3] Compiling Bar.swift") == 1)
        #expect(matcher.match(text: "[9/99] Compiling Bar.swift") == 1)
    }

    @Test("exact hash wins when normalized hashes overlap")
    func exactHashWinsWhenNormalizedHashesOverlap() {
        let matcher = LineMatcher(runs: [
            CommandRun(date: Date(), totalDuration: 2, lineRecords: [
                makeLine("Step 1", offset: 1),
                makeLine("Step 2", offset: 2),
            ])
        ])

        #expect(matcher.match(text: "Step 2") == 1)
        #expect(matcher.match(text: "Step 99") == 0)
    }

    @Test("repeated lines only match later reference indices")
    func repeatedLinesMatchAfterPreviousIndex() {
        let lines = [
            makeLine("Compiling Shared.swift", offset: 1),
            makeLine("Compiling Shared.swift", offset: 2),
            makeLine("Done", offset: 3),
        ]
        let matcher = LineMatcher(runs: [
            CommandRun(date: Date(), totalDuration: 3, lineRecords: lines)
        ])

        let first = matcher.match(text: "Compiling Shared.swift")
        let second = matcher.match(text: "Compiling Shared.swift", after: first ?? -1)

        #expect(first == 0)
        #expect(second == 1)
        #expect(matcher.match(text: "Compiling Shared.swift", after: 1) == nil)
    }

    @Test("returns nil without reference history")
    func returnsNilWithoutReferenceHistory() {
        let matcher = LineMatcher(runs: [])

        #expect(matcher.match(text: "Done") == nil)
        #expect(matcher.referenceLines.isEmpty)
        #expect(matcher.referenceTotalDuration == 0)
    }
}
