import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import ArgumentParser

/// ANSI color names for the --color flag.
enum BarColor: String, CaseIterable, Sendable, ExpressibleByArgument {
    case green, yellow, red, blue, magenta, cyan, white

    var ansiCode: String {
        switch self {
        case .green:   return "\u{1B}[32m"
        case .yellow:  return "\u{1B}[33m"
        case .red:     return "\u{1B}[31m"
        case .blue:    return "\u{1B}[34m"
        case .magenta: return "\u{1B}[35m"
        case .cyan:    return "\u{1B}[36m"
        case .white:   return "\u{1B}[37m"
        }
    }
}

/// ANSI progress bar that renders as a sticky line on stderr.
final class ProgressRenderer: @unchecked Sendable {
    private let lock = NSLock()
    private let isTTY: Bool
    private let color: BarColor
    private var lastDrawTime: TimeInterval = 0
    private let minDrawInterval: TimeInterval = 1.0 / 15.0  // ~15 fps
    private var barVisible = false

    init(color: BarColor = .green) {
        self.isTTY = isatty(STDERR_FILENO) != 0
        self.color = color
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

    /// Atomically: clear bar → write line → redraw bar. Prevents timer races.
    func writeLineAndRedraw(line: String, isStderr: Bool,
                            progress: Double, elapsed: Double, eta: Double,
                            runCount: Int, isLearning: Bool) {
        lock.lock()
        defer { lock.unlock() }

        // Clear current bar
        if isTTY, barVisible {
            writeStderr("\u{1B}[2K\r")
            barVisible = false
        }

        // Write the output line
        if isStderr {
            FileHandle.standardError.write(Data((line + "\n").utf8))
        } else {
            FileHandle.standardOutput.write(Data((line + "\n").utf8))
        }

        // Redraw bar
        guard isTTY else { return }
        lastDrawTime = ProcessInfo.processInfo.systemUptime
        draw(progress: progress, elapsed: elapsed, eta: eta,
             runCount: runCount, isLearning: isLearning)
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

        return "\(color.ansiCode)[\(filledBar)\(emptyBar)]\(suffix)\u{1B}[0m"
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
