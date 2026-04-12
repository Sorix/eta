import Foundation
import ProcessProgress

/// Writes progress status to the controlling terminal without contaminating wrapped command output.
///
/// This type owns terminal lifecycle concerns: opening `/dev/tty`, throttling redraws,
/// hiding/restoring the cursor, and serializing command output with progress redraws.
/// `ProgressBarFormatter` owns the actual line layout.
final class ProgressRenderer: ProgressRendering, @unchecked Sendable {
    private let lock = NSLock()
    private let terminal: TerminalHandle?
    private let color: BarColor
    private let style: ProgressBarStyle
    private let terminalColors: TerminalDefaultColors?
    private var lastDrawTime: TimeInterval = 0
    private let minDrawInterval: TimeInterval = IndeterminateStatusRenderer.frameInterval
    private var barVisible = false
    private var cursorHidden = false
    private var outputContainsPartialLine = false

    init(color: BarColor = .green, style: ProgressBarStyle = .layered) {
        let terminal = TerminalHandle.open()
        self.terminal = terminal
        self.color = color
        self.style = style
        self.terminalColors = terminal.flatMap { TerminalDefaultColorQuery.query(fileDescriptor: $0.fileDescriptor) }
    }

    var isEnabled: Bool {
        terminal != nil
    }

    // MARK: - Rendering API

    func update(progress: ProgressFill, remainingTime: Double?, elapsedTime: Double) {
        lock.lock()
        defer { lock.unlock() }

        guard terminal != nil, !outputContainsPartialLine else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDrawTime >= minDrawInterval else { return }
        lastDrawTime = now

        draw(progress: progress, remainingTime: remainingTime, elapsedTime: elapsedTime)
    }

    func forceUpdate(progress: ProgressFill, remainingTime: Double?, elapsedTime: Double) {
        lock.lock()
        defer { lock.unlock() }

        guard terminal != nil else { return }
        lastDrawTime = ProcessInfo.processInfo.systemUptime
        draw(progress: progress, remainingTime: remainingTime, elapsedTime: elapsedTime)
    }

    /// Writes wrapped command bytes, then redraws progress when the stream is at a line boundary.
    func writeOutputAndRedraw(
        rawOutput: Data,
        stream: CommandOutputStream,
        progress: ProgressFill,
        remainingTime: Double?,
        elapsedTime: Double,
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
        draw(progress: progress, remainingTime: remainingTime, elapsedTime: elapsedTime)
    }

    func cleanup() {
        lock.lock()
        defer { lock.unlock() }

        guard terminal != nil else { return }
        if barVisible {
            writeTerminal("\u{1B}[2K\r")
            barVisible = false
        }
        showCursorIfNeeded()
    }

    func finish(elapsed: Double, expectedDuration: Double) {
        lock.lock()
        defer { lock.unlock() }

        guard terminal != nil else { return }

        if barVisible {
            writeTerminal("\u{1B}[2K\r")
            barVisible = false
        }
        showCursorIfNeeded()
        if outputContainsPartialLine {
            writeTerminal("\n")
            outputContainsPartialLine = false
        }

        writeTerminal(ProgressBarFormatter.completionLine(elapsed: elapsed, expectedDuration: expectedDuration))
    }

    // MARK: - Drawing

    private func draw(progress: ProgressFill, remainingTime: Double?, elapsedTime: Double) {
        guard let terminal else { return }
        let bar = buildLine(
            progress: progress,
            remainingTime: remainingTime,
            elapsedTime: elapsedTime,
            width: terminal.width
        )
        hideCursorIfNeeded()
        writeTerminal("\u{1B}[2K\r\(bar)")
        barVisible = true
    }

    private func buildLine(
        progress: ProgressFill,
        remainingTime: Double?,
        elapsedTime: Double,
        width: Int
    ) -> String {
        ProgressBarFormatter.buildLine(
            progress: progress,
            remainingTime: remainingTime,
            elapsedTime: elapsedTime,
            width: width,
            color: color,
            style: style,
            terminalColors: terminalColors
        )
    }

    // MARK: - Helpers

    private func writeTerminal(_ string: String) {
        terminal?.write(string)
    }

    private func hideCursorIfNeeded() {
        guard !cursorHidden else { return }
        writeTerminal("\u{1B}[?25l")
        cursorHidden = true
    }

    private func showCursorIfNeeded() {
        guard cursorHidden else { return }
        writeTerminal("\u{1B}[?25h")
        cursorHidden = false
    }

    private func writeCommandOutput(_ data: Data, to stream: CommandOutputStream) {
        let handle = stream == .standardError ? FileHandle.standardError : FileHandle.standardOutput
        handle.write(data)
    }
}
