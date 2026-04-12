import Foundation

struct OutputLineBuffer: Sendable {
    struct Update: Sendable {
        let lineRecords: [LineRecord]
        let containsPartialLine: Bool
    }

    private var pending = Data()

    mutating func append(_ data: Data, offsetSeconds: Double) -> Update {
        var lineRecords: [LineRecord] = []

        for byte in data {
            if byte == 0x0A {
                if let record = Self.makeRecord(from: pending, offsetSeconds: offsetSeconds) {
                    lineRecords.append(record)
                }
                pending.removeAll(keepingCapacity: true)
            } else {
                pending.append(byte)
            }
        }

        return Update(lineRecords: lineRecords, containsPartialLine: !pending.isEmpty)
    }

    mutating func flushFinalLine(offsetSeconds: Double) -> [LineRecord] {
        defer { pending.removeAll(keepingCapacity: false) }
        guard let record = Self.makeRecord(from: pending, offsetSeconds: offsetSeconds) else {
            return []
        }
        return [record]
    }

    private static func makeRecord(from lineData: Data, offsetSeconds: Double) -> LineRecord? {
        guard !lineData.isEmpty,
              let raw = String(data: lineData, encoding: .utf8),
              !raw.isEmpty else {
            return nil
        }

        let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        guard !line.isEmpty else { return nil }

        return LineRecord(
            textHash: LineHash.hash(line),
            normalizedHash: LineHash.normalizedHash(line),
            offsetSeconds: offsetSeconds
        )
    }
}
