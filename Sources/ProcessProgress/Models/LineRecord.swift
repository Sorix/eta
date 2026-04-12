/// A hashed output line observed during a command run.
public struct LineRecord: Codable, Sendable {
    /// MD5 digest of the original output line.
    public let textHash: String

    /// MD5 digest of the normalized output line.
    public let normalizedHash: String

    /// Seconds from the command start until this line was observed.
    public let offsetSeconds: Double

    /// Creates a line record from precomputed hashes and a timeline offset.
    ///
    /// - Parameters:
    ///   - textHash: MD5 digest of the original output line.
    ///   - normalizedHash: MD5 digest of the normalized output line.
    ///   - offsetSeconds: Seconds from the command start until this line was observed.
    public init(textHash: String, normalizedHash: String, offsetSeconds: Double) {
        self.textHash = textHash
        self.normalizedHash = normalizedHash
        self.offsetSeconds = offsetSeconds
    }
}
