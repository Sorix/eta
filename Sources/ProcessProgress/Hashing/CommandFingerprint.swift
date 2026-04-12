#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Creates privacy-preserving fingerprints for command keys.
public enum CommandFingerprint {
    /// Returns the SHA-256 digest for a command key.
    ///
    /// - Parameter string: The command key to hash.
    /// - Returns: A lowercase hexadecimal SHA-256 digest.
    public static func hash(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
