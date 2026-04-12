import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Thin wrapper around the controlling terminal used for progress rendering.
struct TerminalHandle {
    let handle: FileHandle
    let fileDescriptor: Int32

    static func open() -> TerminalHandle? {
        guard let handle = FileHandle(forUpdatingAtPath: "/dev/tty") else { return nil }
        let fileDescriptor = handle.fileDescriptor
        guard isatty(fileDescriptor) != 0 else { return nil }
        return TerminalHandle(handle: handle, fileDescriptor: fileDescriptor)
    }

    var width: Int {
        var w = winsize()
        if ioctl(fileDescriptor, UInt(TIOCGWINSZ), &w) == 0, w.ws_col > 0 {
            return Int(w.ws_col)
        }
        return 80
    }

    func write(_ string: String) {
        handle.write(Data(string.utf8))
    }
}
