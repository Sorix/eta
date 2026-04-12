import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct RGBColor: Sendable, Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    static func blend(_ foreground: RGBColor, _ background: RGBColor, alpha: Double) -> RGBColor {
        let clampedAlpha = min(max(alpha, 0), 1)
        let inverseAlpha = 1 - clampedAlpha
        return RGBColor(
            red: UInt8(Double(foreground.red) * clampedAlpha + Double(background.red) * inverseAlpha),
            green: UInt8(Double(foreground.green) * clampedAlpha + Double(background.green) * inverseAlpha),
            blue: UInt8(Double(foreground.blue) * clampedAlpha + Double(background.blue) * inverseAlpha)
        )
    }
}

struct TerminalDefaultColors: Sendable, Equatable {
    let foreground: RGBColor
    let background: RGBColor
}

enum TerminalDefaultColorQuery {
    static func query(fileDescriptor: Int32) -> TerminalDefaultColors? {
        var original = termios()
        guard tcgetattr(fileDescriptor, &original) == 0 else { return nil }

        var raw = original
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO)
        withUnsafeMutableBytes(of: &raw.c_cc) { controlCharacters in
            controlCharacters[Int(VMIN)] = 0
            controlCharacters[Int(VTIME)] = 1
        }

        guard tcsetattr(fileDescriptor, TCSANOW, &raw) == 0 else { return nil }
        defer {
            var restored = original
            _ = tcsetattr(fileDescriptor, TCSANOW, &restored)
        }

        let query = "\u{1B}]10;?\u{07}\u{1B}]11;?\u{07}"
        let queryBytes = Array(query.utf8)
        _ = queryBytes.withUnsafeBytes { buffer in
            write(fileDescriptor, buffer.baseAddress, queryBytes.count)
        }

        var response = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 256)
        while true {
            let bytesRead = buffer.withUnsafeMutableBytes { storage in
                read(fileDescriptor, storage.baseAddress, storage.count)
            }
            guard bytesRead > 0 else { break }
            response.append(contentsOf: buffer.prefix(bytesRead))
            if response.filter({ $0 == 0x07 }).count >= 2 {
                break
            }
        }

        guard !response.isEmpty, let text = String(bytes: response, encoding: .utf8) else {
            return nil
        }
        return parseDefaultColors(from: text)
    }

    static func parseDefaultColors(from response: String) -> TerminalDefaultColors? {
        guard
            let foreground = parseOSCColor(from: response, code: "10"),
            let background = parseOSCColor(from: response, code: "11")
        else {
            return nil
        }
        return TerminalDefaultColors(foreground: foreground, background: background)
    }

    private static func parseOSCColor(from response: String, code: String) -> RGBColor? {
        let normalized = response.replacingOccurrences(of: "\u{1B}\\", with: "\u{07}")
        let prefix = "\u{1B}]\(code);"
        for part in normalized.components(separatedBy: "\u{07}") where part.hasPrefix(prefix) {
            let colorText = String(part.dropFirst(prefix.count))
            if let color = parseColor(colorText) {
                return color
            }
        }
        return nil
    }

    private static func parseColor(_ text: String) -> RGBColor? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            return parseHexColor(String(trimmed.dropFirst()))
        }

        let value = trimmed.hasPrefix("rgb:") ? String(trimmed.dropFirst(4)) : trimmed
        let components = value.split(separator: "/")
        guard components.count == 3 else { return nil }

        let channels = components.compactMap { parseHexChannel(String($0)) }
        guard channels.count == 3 else { return nil }
        return RGBColor(red: channels[0], green: channels[1], blue: channels[2])
    }

    private static func parseHexColor(_ hex: String) -> RGBColor? {
        guard hex.count == 6 || hex.count == 12 else { return nil }
        let channelLength = hex.count / 3
        let channels = stride(from: 0, to: hex.count, by: channelLength).compactMap { offset -> UInt8? in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: channelLength)
            return parseHexChannel(String(hex[start..<end]))
        }
        guard channels.count == 3 else { return nil }
        return RGBColor(red: channels[0], green: channels[1], blue: channels[2])
    }

    private static func parseHexChannel(_ hex: String) -> UInt8? {
        guard !hex.isEmpty, hex.count <= 4, let value = UInt32(hex, radix: 16) else {
            return nil
        }
        let maxValue = Double((1 << (hex.count * 4)) - 1)
        return UInt8((Double(value) / maxValue * 255).rounded())
    }
}
