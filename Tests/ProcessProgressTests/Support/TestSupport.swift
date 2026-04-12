import Foundation
@testable import ProcessProgress

func makeLine(_ text: String, offset: Double = 0) -> LineRecord {
    LineRecord(
        textHash: LineHash.hash(text),
        normalizedHash: LineHash.normalizedHash(text),
        offsetSeconds: offset
    )
}

func makeTemporaryDirectory(_ name: String = #function) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("eta-process-tests-\(UUID().uuidString)-\(name)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
