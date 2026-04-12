import Foundation

enum ProgressTimeFormatter {
    static func format(_ seconds: Double) -> String {
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
}
