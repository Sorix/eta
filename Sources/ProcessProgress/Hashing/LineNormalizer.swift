import Foundation

/// Normalizes output lines before fuzzy matching.
public enum LineNormalizer {
    /// Returns a copy of `text` with digit runs replaced by `N` and whitespace collapsed.
    ///
    /// The fallback line matcher uses this to match progress lines whose counters or
    /// spacing change across runs, such as `[3/100] Compiling Foo.swift`.
    ///
    /// - Parameter text: The output line to normalize.
    /// - Returns: A normalized output line.
    public static func normalized(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var lastWasSpace = false
        var lastWasDigit = false

        for character in text {
            if character.isNumber {
                if !lastWasDigit {
                    result.append("N")
                }
                lastWasSpace = false
                lastWasDigit = true
                continue
            }

            if character.isWhitespace {
                if !lastWasSpace {
                    result.append(" ")
                    lastWasSpace = true
                }
                lastWasDigit = false
            } else {
                result.append(character)
                lastWasSpace = false
                lastWasDigit = false
            }
        }

        return result.trimmingCharacters(in: .whitespaces)
    }
}
