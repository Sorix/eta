import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// ANSI color names for the --color flag.
enum BarColor: String, CaseIterable, Sendable {
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

/// ANSI progress bar that renders as a sticky line on the controlling terminal.
final class ProgressRenderer: @unchecked Sendable {
    private let lock = NSLock()
    private let terminal: FileHandle?
    private let terminalFD: Int32?
    private let color: BarColor
    private var lastDrawTime: TimeInterval = 0
    private let minDrawInterval: TimeInterval = 0.2
    private var barVisible = false

    init(color: BarColor = .green) {
        let terminal = Self.openTerminal()
        self.terminal = terminal?.handle
        self.terminalFD = terminal?.fileDescriptor
        self.color = color
    }

    var isEnabled: Bool {
        terminal != nil
    }

    // MARK: - Public API

    /// Update the progress bar. Thread-safe, throttled.
    func update(progress: Double, elapsed: Double, eta: Double, runCount: Int, isLearning: Bool) {
        lock.lock()
        defer { lock.unlock() }

        guard terminal != nil else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDrawTime >= minDrawInterval else { return }
        lastDrawTime = now

        draw(progress: progress, elapsed: elapsed, eta: eta, runCount: runCount, isLearning: isLearning)
    }

    /// Draw immediately, ignoring throttle. Thread-safe.
    func forceUpdate(progress: Double, elapsed: Double, eta: Double, runCount: Int, isLearning: Bool) {
        lock.lock()
        defer { lock.unlock() }

        guard terminal != nil else { return }
        lastDrawTime = ProcessInfo.processInfo.systemUptime
        draw(progress: progress, elapsed: elapsed, eta: eta, runCount: runCount, isLearning: isLearning)
    }

    /// Clear the progress bar before printing output. Thread-safe.
    func clearBar() {
        lock.lock()
        defer { lock.unlock() }

        guard terminal != nil, barVisible else { return }
        writeTerminal("\u{1B}[2K\r")
        barVisible = false
    }

    /// Atomically: clear bar → write line → redraw bar. Prevents timer races.
    func writeLineAndRedraw(line: String, isStderr: Bool,
                            progress: Double, elapsed: Double, eta: Double,
                            runCount: Int, isLearning: Bool) {
        lock.lock()
        defer { lock.unlock() }

        // Clear current bar
        if terminal != nil, barVisible {
            writeTerminal("\u{1B}[2K\r")
            barVisible = false
        }

        // Write the output line
        if isStderr {
            FileHandle.standardError.write(Data((line + "\n").utf8))
        } else {
            FileHandle.standardOutput.write(Data((line + "\n").utf8))
        }

        // Always redraw after command output so the bar stays attached to the latest line.
        guard terminal != nil else { return }
        lastDrawTime = ProcessInfo.processInfo.systemUptime
        draw(progress: progress, elapsed: elapsed, eta: eta,
             runCount: runCount, isLearning: isLearning)
    }

    /// Show completion summary and clear the bar.
    func finish(elapsed: Double, expected: Double, hasHistory: Bool) {
        lock.lock()
        defer { lock.unlock() }

        guard terminal != nil else { return }

        // Clear the bar
        if barVisible {
            writeTerminal("\u{1B}[2K\r")
            barVisible = false
        }

        if hasHistory {
            let delta = elapsed - expected
            let sign = delta >= 0 ? "+" : ""
            writeTerminal("\u{1B}[32mDone in \(formatTime(elapsed))  (expected \(formatTime(expected)), delta \(sign)\(formatTime(delta)))\u{1B}[0m\n")
        } else {
            writeTerminal("\u{1B}[32mDone in \(formatTime(elapsed))\u{1B}[0m\n")
        }
    }

    // MARK: - Drawing

    private func draw(progress: Double, elapsed: Double, eta: Double, runCount: Int, isLearning: Bool) {
        guard let terminalFD else { return }
        let termWidth = Self.terminalWidth(fileDescriptor: terminalFD)
        let bar = buildBar(
            progress: progress, elapsed: elapsed, eta: eta,
            runCount: runCount, isLearning: isLearning, width: termWidth
        )
        writeTerminal("\u{1B}[2K\r\(bar)")
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

    private func writeTerminal(_ string: String) {
        terminal?.write(Data(string.utf8))
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(abs(seconds).rounded())
        let sign = seconds < 0 && totalSeconds > 0 ? "-" : ""
        if totalSeconds < 60 {
            return "\(sign)\(totalSeconds)s"
        } else {
            let minutes = totalSeconds / 60
            let remainingSeconds = totalSeconds % 60
            return String(format: "%@%dm%02ds", sign, minutes, remainingSeconds)
        }
    }

    private static func openTerminal() -> (handle: FileHandle, fileDescriptor: Int32)? {
        guard let handle = FileHandle(forWritingAtPath: "/dev/tty") else { return nil }
        let fileDescriptor = handle.fileDescriptor
        guard isatty(fileDescriptor) != 0 else { return nil }
        return (handle, fileDescriptor)
    }

    static func terminalWidth(fileDescriptor: Int32) -> Int {
        var w = winsize()
        if ioctl(fileDescriptor, TIOCGWINSZ, &w) == 0, w.ws_col > 0 {
            return Int(w.ws_col)
        }
        return 80
    }
}
