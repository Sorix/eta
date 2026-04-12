import Foundation

/// Renders `• Estimating (22s)` with a Codex-style shimmer on the status text
/// and dim metadata after it. The visible text stays stable across frames.
///
/// The visual behavior is a Swift implementation inspired by OpenAI Codex CLI's
/// Apache-2.0-licensed status shimmer. See `THIRD_PARTY_NOTICES.md`.
final class IndeterminateStatusRenderer: @unchecked Sendable {
    private enum Style {
        static let bullet = "\u{2022}" // •
        static let dimGray = "\u{1B}[90m"
        static let reset = "\u{1B}[0m"
        static let sweepSeconds: Double = 2.0
        static let sweepPadding = 10
        static let bandHalfWidth: Double = 5.0
        static let dim = "\u{1B}[2m"
        static let normalIntensity = "\u{1B}[22m"
        static let bold = "\u{1B}[1m"
    }

    static let frameInterval: TimeInterval = 0.032

    private let lock = NSLock()
    private var text: String

    init(text: String) {
        self.text = text
    }

    func updateText(_ text: String) {
        lock.withLock {
            self.text = text
        }
    }

    func render(
        elapsedText: String,
        elapsedTime: Double,
        width: Int,
        terminalColors: TerminalDefaultColors?
    ) -> String {
        let text = lock.withLock { self.text }
        return Self.render(
            text: text,
            elapsedText: elapsedText,
            elapsedTime: elapsedTime,
            width: width,
            terminalColors: terminalColors
        )
    }

    static func render(
        text: String,
        elapsedText: String,
        elapsedTime: Double,
        width: Int,
        terminalColors: TerminalDefaultColors?
    ) -> String {
        let prefix = "\(Style.bullet) "
        let suffix = " (\(elapsedText))"
        let padding = String(repeating: " ", count: max(0, width - prefix.count - text.count - suffix.count))

        return "\(animatedShimmer(prefix + text, elapsedTime: elapsedTime, terminalColors: terminalColors))"
            + "\(Style.normalIntensity)\(Style.dimGray)\(suffix)\(padding)\(Style.reset)"
    }

    /// Applies a terminal-native RGB shimmer when default colors are known, with
    /// a dim/normal/bold fallback for terminals that do not report OSC colors.
    private static func animatedShimmer(
        _ text: String,
        elapsedTime: Double,
        terminalColors: TerminalDefaultColors?
    ) -> String {
        let characters = Array(text)
        let period = Double(characters.count + Style.sweepPadding * 2)
        let elapsed = max(0, elapsedTime)
        let sweepPosition = elapsed.truncatingRemainder(dividingBy: Style.sweepSeconds)
            / Style.sweepSeconds
            * period

        return characters.enumerated().map { index, character in
            let characterPosition = Double(index + Style.sweepPadding)
            let distance = abs(characterPosition - sweepPosition)
            let intensity: Double
            if distance <= Style.bandHalfWidth {
                let x = Double.pi * (distance / Style.bandHalfWidth)
                intensity = 0.5 * (1.0 + cos(x))
            } else {
                intensity = 0
            }

            if let terminalColors {
                let highlight = min(max(intensity, 0), 1) * 0.9
                let color = RGBColor.blend(terminalColors.background, terminalColors.foreground, alpha: highlight)
                return "\u{1B}[38;2;\(color.red);\(color.green);\(color.blue)m\(Style.bold)\(character)"
            }

            let intensityStyle: String
            if intensity < 0.2 {
                intensityStyle = Style.dim
            } else if intensity < 0.6 {
                intensityStyle = Style.normalIntensity
            } else {
                intensityStyle = Style.bold
            }

            return "\(Style.normalIntensity)\(intensityStyle)\(character)"
        }.joined()
    }
}
