#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Creates privacy-preserving hashes for output lines.
public enum LineHash {
    /// MD5 is marked `Insecure` in CryptoKit because it's vulnerable to deliberate
    /// collision attacks - but that's irrelevant here. We use it as a one-way digest
    /// to avoid storing raw command output on disk. MD5 is not reversible (output can't
    /// be turned back into the original text), and collisions only cause a slightly
    /// inaccurate ETA - no security implications. Hardware-accelerated on Apple Silicon.
    ///
    /// - Parameter string: The output line to hash.
    /// - Returns: A lowercase hexadecimal MD5 digest.
    public static func hash(_ string: String) -> String {
        md5(string)
    }

    /// Returns an MD5 digest after normalizing the output line for fuzzy matching.
    ///
    /// - Parameter string: The output line to normalize and hash.
    /// - Returns: A lowercase hexadecimal MD5 digest.
    public static func normalizedHash(_ string: String) -> String {
        md5(LineNormalizer.normalized(string))
    }

    static func md5(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
