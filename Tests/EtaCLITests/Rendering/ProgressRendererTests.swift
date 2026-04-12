@testable import EtaCLI
@testable import ProcessProgress
import Testing

@Suite("Progress renderer")
struct ProgressRendererTests {
    @Test("known ETA renders determinate progress bar")
    func knownETARendersDeterminateProgressBar() {
        let line = ProgressBarFormatter.buildLine(
            progress: ProgressFill(confirmed: 0.25, predicted: 0.5),
            remainingTime: 5,
            elapsedTime: 5,
            width: 40,
            color: .green,
            style: .layered
        )

        let visibleLine = stripANSI(line)
        #expect(visibleLine.hasPrefix("["))
        #expect(visibleLine.contains("  50%  ETA 5s"))
    }
}

private func stripANSI(_ string: String) -> String {
    string.replacingOccurrences(
        of: "\u{1B}\\[[0-9;]*m",
        with: "",
        options: .regularExpression
    )
}
