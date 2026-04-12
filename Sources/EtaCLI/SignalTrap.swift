import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class SignalTrap: SignalTrapping, @unchecked Sendable {
    private let signals: [Int32]
    private var sources: [DispatchSourceSignal] = []
    private let lock = NSLock()
    private var isCancelled = false

    init(signals: [Int32] = [SIGINT, SIGTERM], cleanup: @escaping @Sendable () -> Void) {
        self.signals = signals
        for signalNumber in signals {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
            source.setEventHandler {
                cleanup()
                // Restore default handling before re-raising so the parent shell sees the original termination signal.
                signal(signalNumber, SIG_DFL)
                raise(signalNumber)
            }
            source.resume()
            sources.append(source)
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return }
        isCancelled = true

        for source in sources {
            source.cancel()
        }
        for signalNumber in signals {
            signal(signalNumber, SIG_DFL)
        }
    }
}
