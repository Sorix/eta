import Foundation
import ProcessProgress
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

enum ProgressBarStyle: Sendable {
    case layered
    case solid
}

/// ANSI progress bar that renders as a sticky line on the controlling terminal.
///
/// Layered style uses solid fill for confirmed progress and shaded fill for
/// predicted-only progress. Solid style fills predicted progress with one glyph.
final class ProgressRenderer: ProgressRendering, @unchecked Sendable {
    private enum BarGlyphs {
        static let confirmed = "\u{2588}" // █
        static let predicted = "\u{2592}" // ▒
        static let empty = " "
    }

    private let lock = NSLock()
    private let terminal: FileHandle?
    private let terminalFD: Int32?
    private let color: BarColor
    private let style: ProgressBarStyle
    private var lastDrawTime: TimeInterval = 0
    private let minDrawInterval: TimeInterval = 0.2
    private var barVisible = false
    private var outputContainsPartialLine = false

    init(color: BarColor = .green, style: ProgressBarStyle = .layered) {
        let terminal = Self.openTerminal()
        self.terminal = terminal?.handle
        self.terminalFD = terminal?.fileDescriptor
        self.color = color
        self.style = style
    }

    var isEnabled: Bool {
        terminal != nil
    }

    // MARK: - Rendering API

    func update(progress: ProgressFill, remainingTime: Double) {
        lock.lock()
        defer { lock.unlock() }

        guard terminal != nil, !outputContainsPartialLine else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDrawTime >= minDrawInterval else { return }
        lastDrawTime = now

        draw(progress: progress, remainingTime: remainingTime)
    }

    func forceUpdate(progress: ProgressFill, remainingTime: Double) {
        lock.lock()
        defer { lock.unlock() }

        guard terminal != nil else { return }
        lastDrawTime = ProcessInfo.processInfo.systemUptime
        draw(progress: progress, remainingTime: remainingTime)
    }

    /// Keep command output and progress redraws from interleaving on the terminal.
    func writeOutputAndRedraw(
        rawOutput: Data,
        stream: CommandOutputStream,
        progress: ProgressFill,
        remainingTime: Double,
        containsPartialLine: Bool
    ) {
        lock.lock()
        defer { lock.unlock() }

        if terminal != nil, barVisible {
            writeTerminal("\u{1B}[2K\r")
            barVisible = false
        }

        writeCommandOutput(rawOutput, to: stream)
        outputContainsPartialLine = containsPartialLine

        guard terminal != nil, !outputContainsPartialLine else { return }
        lastDrawTime = ProcessInfo.processInfo.systemUptime
        draw(progress: progress, remainingTime: remainingTime)
    }

    func cleanup() {
        lock.lock()
        defer { lock.unlock() }

        guard terminal != nil, barVisible else { return }
        writeTerminal("\u{1B}[2K\r")
        barVisible = false
    }

    func finish(elapsed: Double, expectedDuration: Double) {
        lock.lock()
        defer { lock.unlock() }

        guard terminal != nil else { return }

        if barVisible {
            writeTerminal("\u{1B}[2K\r")
            barVisible = false
        }
        if outputContainsPartialLine {
            writeTerminal("\n")
            outputContainsPartialLine = false
        }

        let delta = elapsed - expectedDuration
        let sign = delta >= 0 ? "+" : ""
        writeTerminal("\u{1B}[32mDone in \(formatTime(elapsed))  (expected \(formatTime(expectedDuration)), delta \(sign)\(formatTime(delta)))\u{1B}[0m\n")
    }

    // MARK: - Drawing

    private func draw(progress: ProgressFill, remainingTime: Double) {
        guard let terminalFD else { return }
        let termWidth = Self.terminalWidth(fileDescriptor: terminalFD)
        let bar = buildBar(
            progress: progress,
            remainingTime: remainingTime,
            width: termWidth
        )
        writeTerminal("\u{1B}[2K\r\(bar)")
        barVisible = true
    }

    private func buildBar(progress: ProgressFill, remainingTime: Double, width: Int) -> String {
        let confirmedProgress = progress.confirmed
        let predictedProgress = progress.predicted

        let pct = String(format: "%3.0f%%", predictedProgress * 100)
        let remainingTimeString = remainingTime > 0 ? "ETA \(formatTime(remainingTime))" : "ETA 0s"
        let suffix = "  \(pct)  \(remainingTimeString)"

        let barWidth = max(10, width - suffix.count - 3)
        let predictedWidth = Int(Double(barWidth) * predictedProgress)

        let fill: String
        switch style {
        case .layered:
            let confirmedWidth = Int(Double(barWidth) * confirmedProgress)
            let predictedOnlyWidth = max(0, predictedWidth - confirmedWidth)
            let emptyWidth = max(0, barWidth - confirmedWidth - predictedOnlyWidth)

            fill = String(repeating: BarGlyphs.confirmed, count: confirmedWidth)
                + String(repeating: BarGlyphs.predicted, count: predictedOnlyWidth)
                + String(repeating: BarGlyphs.empty, count: emptyWidth)
        case .solid:
            let emptyWidth = max(0, barWidth - predictedWidth)

            fill = String(repeating: BarGlyphs.confirmed, count: predictedWidth)
                + String(repeating: BarGlyphs.empty, count: emptyWidth)
        }

        return "\(color.ansiCode)[\(fill)]\(suffix)\u{1B}[0m"
    }

    // MARK: - Helpers

    private func writeTerminal(_ string: String) {
        terminal?.write(Data(string.utf8))
    }

    private func writeCommandOutput(_ data: Data, to stream: CommandOutputStream) {
        let handle = stream == .standardError ? FileHandle.standardError : FileHandle.standardOutput
        handle.write(data)
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
