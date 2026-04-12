import Foundation

protocol CommandKeyResolving: Sendable {
    func resolvedKey(for command: String) -> String
}

/// Builds stable history keys for commands before they are hashed by storage.
struct CommandKeyResolver: CommandKeyResolving {
    typealias CurrentDirectoryProvider = @Sendable () -> String
    typealias PathResolver = @Sendable (String) -> String?
    typealias ExecutableResolver = @Sendable (String) -> String?

    static let live = CommandKeyResolver(
        currentDirectory: { FileManager.default.currentDirectoryPath },
        pathResolver: Self.realpathOrNil,
        executableResolver: Self.whichPath
    )

    private let currentDirectory: CurrentDirectoryProvider
    private let pathResolver: PathResolver
    private let executableResolver: ExecutableResolver

    init(
        currentDirectory: @escaping CurrentDirectoryProvider,
        pathResolver: @escaping PathResolver,
        executableResolver: @escaping ExecutableResolver
    ) {
        self.currentDirectory = currentDirectory
        self.pathResolver = pathResolver
        self.executableResolver = executableResolver
    }

    func resolvedKey(for command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        let firstSpace = trimmed.firstIndex(of: " ")
        let executable = firstSpace.map { String(trimmed[..<$0]) } ?? trimmed
        let rest = firstSpace.map { String(trimmed[$0...]) } ?? ""

        if executable.contains("/"), let resolved = pathResolver(executable) {
            return resolved + rest
        }

        let cwd = currentDirectory()
        if let resolved = executableResolver(executable) {
            return "\(cwd)\n\(resolved)\(rest)"
        }

        return "\(cwd)\n\(command)"
    }

    private static func realpathOrNil(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func whichPath(_ executable: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [executable]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty else { return nil }
        return path
    }
}
