import Foundation

struct CommandOutputWriter: Sendable {
    let write: @Sendable (Data, CommandOutputStream) -> Void

    static let standard = CommandOutputWriter { data, stream in
        let handle = stream == .standardError ? FileHandle.standardError : FileHandle.standardOutput
        handle.write(data)
    }

    func write(_ data: Data, to stream: CommandOutputStream) {
        write(data, stream)
    }
}
