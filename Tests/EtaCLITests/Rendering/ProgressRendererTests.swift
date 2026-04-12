@testable import EtaCLI
@testable import ProcessProgress
import Testing

@Suite("Progress renderer")
struct ProgressRendererTests {
    @Test("unknown ETA renders Codex-style estimating status")
    func unknownETARendersEstimatingStatus() {
        let line = ProgressBarFormatter.buildLine(
            progress: ProgressFill(confirmed: 0, predicted: 0),
            remainingTime: nil,
            elapsedTime: 22,
            width: 32,
            color: .cyan,
            style: .layered,
            terminalColors: nil
        )

        let visibleLine = stripANSI(line)
        #expect(visibleLine.hasPrefix("• Estimating (22s)"))
        #expect(visibleLine.count == 32)
        #expect(!visibleLine.contains("ETA"))
        #expect(line.contains("\u{1B}[90m (22s)"))
    }

    @Test("unknown ETA estimating status animates without changing layout")
    func unknownETAEstimatingStatusAnimates() {
        let firstFrame = ProgressBarFormatter.buildLine(
            progress: ProgressFill(confirmed: 0, predicted: 0),
            remainingTime: nil,
            elapsedTime: 0,
            width: 32,
            color: .cyan,
            style: .layered,
            terminalColors: nil
        )
        let secondFrame = ProgressBarFormatter.buildLine(
            progress: ProgressFill(confirmed: 0, predicted: 0),
            remainingTime: nil,
            elapsedTime: 0.49,
            width: 32,
            color: .cyan,
            style: .layered,
            terminalColors: nil
        )

        #expect(firstFrame != secondFrame)
        #expect(stripANSI(firstFrame) == stripANSI(secondFrame))
    }

    @Test("unknown ETA status ignores configured bar color")
    func unknownETAStatusIgnoresConfiguredBarColor() {
        let greenLine = ProgressBarFormatter.buildLine(
            progress: ProgressFill(confirmed: 0, predicted: 0),
            remainingTime: nil,
            elapsedTime: 1,
            width: 32,
            color: .green,
            style: .layered,
            terminalColors: nil
        )
        let magentaLine = ProgressBarFormatter.buildLine(
            progress: ProgressFill(confirmed: 0, predicted: 0),
            remainingTime: nil,
            elapsedTime: 1,
            width: 32,
            color: .magenta,
            style: .solid,
            terminalColors: nil
        )

        #expect(greenLine == magentaLine)
        #expect(!greenLine.contains(BarColor.green.ansiCode))
        #expect(!magentaLine.contains(BarColor.magenta.ansiCode))
    }

    @Test("known ETA still renders determinate progress bar")
    func knownETAStillRendersDeterminateProgressBar() {
        let line = ProgressBarFormatter.buildLine(
            progress: ProgressFill(confirmed: 0.25, predicted: 0.5),
            remainingTime: 5,
            elapsedTime: 5,
            width: 40,
            color: .green,
            style: .layered,
            terminalColors: nil
        )

        let visibleLine = stripANSI(line)
        #expect(visibleLine.hasPrefix("["))
        #expect(visibleLine.contains("  50%  ETA 5s"))
    }

    @Test("indeterminate status supports custom text and terminal RGB shimmer")
    func indeterminateStatusSupportsCustomTextAndTerminalRGBShimmer() {
        let colors = TerminalDefaultColors(
            foreground: RGBColor(red: 220, green: 221, blue: 222),
            background: RGBColor(red: 10, green: 11, blue: 12)
        )
        let renderer = IndeterminateStatusRenderer(text: "Estimating")
        renderer.updateText("Learning")

        let line = renderer.render(
            elapsedText: "3s",
            elapsedTime: 0.49,
            width: 32,
            terminalColors: colors
        )

        let visibleLine = stripANSI(line)
        #expect(visibleLine.hasPrefix("• Learning (3s)"))
        #expect(visibleLine.count == 32)
        #expect(line.contains("\u{1B}[38;2;"))
    }

    @Test("terminal default color query parses OSC foreground and background responses")
    func terminalDefaultColorQueryParsesOSCResponses() throws {
        let response = "\u{1B}]10;rgb:ffff/0000/8080\u{07}\u{1B}]11;#010203\u{07}"

        let colors = try #require(TerminalDefaultColorQuery.parseDefaultColors(from: response))

        #expect(colors.foreground == RGBColor(red: 255, green: 0, blue: 128))
        #expect(colors.background == RGBColor(red: 1, green: 2, blue: 3))
    }
}

private func stripANSI(_ string: String) -> String {
    string.replacingOccurrences(
        of: "\u{1B}\\[[0-9;]*m",
        with: "",
        options: .regularExpression
    )
}
