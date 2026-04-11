import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// ANSI progress bar that renders as a sticky line on stderr.
final class ProgressRenderer: @unchecked Sendable {
    private let lock = NSLock()
    private let isTTY: Bool
    private var lastDrawTime: TimeInterval = 0
    private let minDrawInterval: TimeInterval = 1.0 / 15.0  // ~15 fps
    private var barVisible = false

    init() {
        self.isTTY = isatty(STDERR_FILENO) != 0
    }

    // MARK: - Public API

    /// Update the progress bar. Thread-safe, throttled.
    func update(progress: Double, elapsed: Double, eta: Double, runCount: Int, isLearning: Bool) {
        lock.lock()
        defer { lock.unlock() }

        guard isTTY else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDrawTime >= minDrawInterval else { return }
        lastDrawTime = now

        draw(progress: progress, elapsed: elapsed, eta: eta, runCount: runCount, isLearning: isLearning)
    }

    /// Force a redraw (e.g., on new output line). Thread-safe.
    func forceUpdate(progress: Double, elapsed: Double, eta: Double, runCount: Int, isLearning: Bool) {
        lock.lock()
        defer { lock.unlock() }

        guard isTTY else { return }
        lastDrawTime = ProcessInfo.processInfo.systemUptime
        draw(progress: progress, elapsed: elapsed, eta: eta, runCount: runCount, isLearning: isLearning)
    }

    /// Clear the progress bar before printing output. Thread-safe.
    func clearBar() {
        lock.lock()
        defer { lock.unlock() }

        guard isTTY, barVisible else { return }
        writeStderr("\u{1B}[2K\r")
        barVisible = false
    }

    /// Show completion summary and clear the bar.
    func finish(elapsed: Double, expected: Double, hasHistory: Bool) {
        lock.lock()
        defer { lock.unlock() }

        guard isTTY else { return }

        // Clear the bar
        if barVisible {
            writeStderr("\u{1B}[2K\r")
            barVisible = false
        }

        if hasHistory {
            let delta = elapsed - expected
            let sign = delta >= 0 ? "+" : ""
            writeStderr("\u{1B}[32mDone in \(formatTime(elapsed))  (expected \(formatTime(expected)), delta \(sign)\(formatTime(delta)))\u{1B}[0m\n")
        } else {
            writeStderr("\u{1B}[32mDone in \(formatTime(elapsed))\u{1B}[0m\n")
        }
    }

    // MARK: - Drawing

    private func draw(progress: Double, elapsed: Double, eta: Double, runCount: Int, isLearning: Bool) {
        let termWidth = Self.terminalWidth()
        let bar = buildBar(
            progress: progress, elapsed: elapsed, eta: eta,
            runCount: runCount, isLearning: isLearning, width: termWidth
        )
        writeStderr("\u{1B}[2K\r\(bar)")
        barVisible = true
    }

    private func buildBar(progress: Double, elapsed: Double, eta: Double,
                          runCount: Int, isLearning: Bool, width: Int) -> String {
        let clampedProgress = max(0, min(1, progress))

        if isLearning {
            let elapsedStr = "elapsed: \(formatTime(elapsed))"
            return "\u{1B}[33m[learning...]  \(elapsedStr)\u{1B}[0m"
        }

        let pct = String(format: "%3.0f%%", clampedProgress * 100)
        let etaStr = eta > 0 ? "ETA \(formatTime(eta))" : "ETA 0s"
        let runsStr = "(\(runCount) runs)"
        let suffix = "  \(pct)  \(etaStr)  \(runsStr)"

        // Bar width: total width minus brackets, suffix, and padding
        let barWidth = max(10, width - suffix.count - 3)
        let filled = Int(Double(barWidth) * clampedProgress)
        let empty = barWidth - filled

        let filledBar = String(repeating: "\u{2588}", count: filled)   // █
        let emptyBar = String(repeating: "\u{2591}", count: empty)     // ░

        // Color: green if > 50%, yellow if > 25%, red otherwise
        let color: String
        if clampedProgress > 0.5 {
            color = "\u{1B}[32m"  // green
        } else if clampedProgress > 0.25 {
            color = "\u{1B}[33m"  // yellow
        } else {
            color = "\u{1B}[31m"  // red
        }

        return "\(color)[\(filledBar)\(emptyBar)]\(suffix)\u{1B}[0m"
    }

    // MARK: - Helpers

    private func writeStderr(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }

    private func formatTime(_ seconds: Double) -> String {
        let absSeconds = abs(seconds)
        if absSeconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            let m = Int(absSeconds) / 60
            let s = absSeconds - Double(m * 60)
            let sign = seconds < 0 ? "-" : ""
            return String(format: "%s%dm%04.1fs", sign, m, s)
        }
    }

    static func terminalWidth() -> Int {
        var w = winsize()
        if ioctl(STDERR_FILENO, TIOCGWINSZ, &w) == 0, w.ws_col > 0 {
            return Int(w.ws_col)
        }
        return 80
    }
}
