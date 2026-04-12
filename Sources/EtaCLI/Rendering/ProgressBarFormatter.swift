import Foundation
import ProcessProgress

/// Builds ANSI-formatted progress lines without performing terminal I/O.
enum ProgressBarFormatter {
    private enum Glyphs {
        static let confirmed = "\u{2588}" // █
        static let predicted = "\u{2592}" // ▒
        static let empty = " "
    }

    /// Returns a determinate ETA bar.
    static func buildLine(
        progress: ProgressFill,
        remainingTime: Double,
        elapsedTime: Double,
        width: Int,
        color: BarColor,
        style: ProgressBarStyle
    ) -> String {
        buildDeterminateBar(
            progress: progress,
            remainingTime: remainingTime,
            width: width,
            color: color,
            style: style
        )
    }

    /// Returns the final `Done in ...` line printed after a successful run.
    static func completionLine(elapsed: Double, expectedDuration: Double) -> String {
        if expectedDuration > 0 {
            let delta = elapsed - expectedDuration
            let sign = delta >= 0 ? "+" : ""
            return "\u{1B}[32mDone in \(ProgressTimeFormatter.format(elapsed))  (expected \(ProgressTimeFormatter.format(expectedDuration)), delta \(sign)\(ProgressTimeFormatter.format(delta)))\u{1B}[0m\n"
        } else {
            return "\u{1B}[32mDone in \(ProgressTimeFormatter.format(elapsed))\u{1B}[0m\n"
        }
    }

    private static func buildDeterminateBar(
        progress: ProgressFill,
        remainingTime: Double,
        width: Int,
        color: BarColor,
        style: ProgressBarStyle
    ) -> String {
        let confirmedProgress = progress.confirmed
        let predictedProgress = progress.predicted
        let pct = String(format: "%3.0f%%", predictedProgress * 100)
        let remainingTimeString = remainingTime > 0 ? "ETA \(ProgressTimeFormatter.format(remainingTime))" : "ETA 0s"
        let suffix = "  \(pct)  \(remainingTimeString)"

        let barWidth = max(10, width - suffix.count - 3)
        let predictedWidth = Int(Double(barWidth) * predictedProgress)

        let fill: String
        switch style {
        case .layered:
            let confirmedWidth = Int(Double(barWidth) * confirmedProgress)
            let predictedOnlyWidth = max(0, predictedWidth - confirmedWidth)
            let emptyWidth = max(0, barWidth - confirmedWidth - predictedOnlyWidth)

            fill = String(repeating: Glyphs.confirmed, count: confirmedWidth)
                + String(repeating: Glyphs.predicted, count: predictedOnlyWidth)
                + String(repeating: Glyphs.empty, count: emptyWidth)
        case .solid:
            let emptyWidth = max(0, barWidth - predictedWidth)

            fill = String(repeating: Glyphs.confirmed, count: predictedWidth)
                + String(repeating: Glyphs.empty, count: emptyWidth)
        }

        return "\(color.ansiCode)[\(fill)]\(suffix)\u{1B}[0m"
    }
}
