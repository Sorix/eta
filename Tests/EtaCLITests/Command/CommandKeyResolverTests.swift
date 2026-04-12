@testable import EtaCLI
import Testing

@Suite("Command key resolver")
struct CommandKeyResolverTests {
    @Test("path-based command uses canonical executable path without cwd")
    func pathCommandUsesCanonicalPath() {
        let resolver = makeResolver(
            pathResults: ["./test.sh": "/repo/scripts/test.sh"]
        )

        let key = resolver.resolvedKey(for: "./test.sh --fast")

        #expect(key == "/repo/scripts/test.sh --fast")
    }

    @Test("different relative paths to same script share canonical key")
    func relativePathsToSameScriptShareCanonicalKey() {
        let resolver = makeResolver(
            pathResults: [
                "./scripts/test.sh": "/repo/scripts/test.sh",
                "../repo/scripts/test.sh": "/repo/scripts/test.sh",
            ]
        )

        let localKey = resolver.resolvedKey(for: "./scripts/test.sh --fast")
        let parentKey = resolver.resolvedKey(for: "../repo/scripts/test.sh --fast")

        #expect(localKey == parentKey)
    }

    @Test("unresolved path command includes cwd and original command")
    func unresolvedPathCommandIncludesCwdAndOriginalCommand() {
        let resolver = makeResolver()

        let key = resolver.resolvedKey(for: "./missing.sh --flag")

        #expect(key == "/repo\n./missing.sh --flag")
    }

    @Test("bare executable includes cwd and resolved executable path")
    func bareExecutableIncludesCwdAndResolvedPath() {
        let resolver = makeResolver(
            executableResults: ["swift": "/usr/bin/swift"]
        )

        let key = resolver.resolvedKey(for: "swift build")

        #expect(key == "/repo\n/usr/bin/swift build")
    }

    @Test("same bare executable in different working directories has different keys")
    func bareExecutableDiffersByWorkingDirectory() {
        let projectA = makeResolver(
            cwd: "/repo/project-a",
            executableResults: ["swift": "/usr/bin/swift"]
        )
        let projectB = makeResolver(
            cwd: "/repo/project-b",
            executableResults: ["swift": "/usr/bin/swift"]
        )

        let projectAKey = projectA.resolvedKey(for: "swift build")
        let projectBKey = projectB.resolvedKey(for: "swift build")

        #expect(projectAKey != projectBKey)
        #expect(projectAKey == "/repo/project-a\n/usr/bin/swift build")
        #expect(projectBKey == "/repo/project-b\n/usr/bin/swift build")
    }

    @Test("same bare command name differs when PATH resolves different executables")
    func bareExecutableDiffersByResolvedPath() {
        let binA = makeResolver(
            executableResults: ["tool": "/repo/bin-a/tool"]
        )
        let binB = makeResolver(
            executableResults: ["tool": "/repo/bin-b/tool"]
        )

        let binAKey = binA.resolvedKey(for: "tool test")
        let binBKey = binB.resolvedKey(for: "tool test")

        #expect(binAKey != binBKey)
        #expect(binAKey == "/repo\n/repo/bin-a/tool test")
        #expect(binBKey == "/repo\n/repo/bin-b/tool test")
    }

    @Test("unresolved executable includes cwd and original command")
    func unresolvedExecutableIncludesCwdAndOriginalCommand() {
        let resolver = makeResolver()

        let key = resolver.resolvedKey(for: "project-task --flag")

        #expect(key == "/repo\nproject-task --flag")
    }

    private func makeResolver(
        cwd: String = "/repo",
        pathResults: [String: String] = [:],
        executableResults: [String: String] = [:]
    ) -> CommandKeyResolver {
        CommandKeyResolver(
            currentDirectory: { cwd },
            pathResolver: { pathResults[$0] },
            executableResolver: { executableResults[$0] }
        )
    }
}
