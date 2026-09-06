import Foundation
import Testing
@testable import OddFrogCore

struct ShellCommandTests {
    let nasty = [
        "echo hello world",
        "echo 'it''s'",
        "echo \"double\" $(date) `whoami`",
        "printf '%s\\n' a b; echo $HOME",
        "echo one\necho two",
        "echo ünïcödé 🐸",
    ]

    private func roundTrip(_ text: String) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "printf '%s' \(ShellCommand.quote(text))"]
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    @Test func quoteRoundTripsThroughShell() throws {
        for text in nasty {
            #expect(try roundTrip(text) == text)
        }
    }

    @Test func terminalCommandStringRunsVerbatim() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", ShellCommand.terminalCommandString(shell: "/bin/sh", command: "printf '%s' \"it's $((1+1))\"")]
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        #expect(out == "it's 2")
    }

    @Test func agtermArgumentsShape() {
        let args = ShellCommand.agtermArguments(cwd: "/tmp/a b", name: "Build", shell: "/bin/zsh", command: "make all")
        #expect(args.prefix(2) == ["session", "new"])
        #expect(args.contains("--json"))
        #expect(args.contains("--wait"))
        #expect(args.last == "'/bin/zsh' -lc 'make all'")
        #expect(args[args.firstIndex(of: "--cwd")! + 1] == "/tmp/a b")
    }

    @Test func commandFileUsesConfiguredShellAndFailsOnBadCwd() throws {
        let contents = ShellCommand.commandFileContents(shell: "/bin/sh", cwd: "/nonexistent dir", command: "echo reached")
        #expect(contents.hasPrefix("#!/bin/sh -l\n"))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", contents]
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        #expect(p.terminationStatus == 1)
    }

    @Test func agtermUnavailableDetection() {
        #expect(ShellCommand.isAgtermUnavailable(stderr: "Error: connect(/tmp/x.sock) failed: No such file or directory — is agterm running?"))
        #expect(!ShellCommand.isAgtermUnavailable(stderr: "{\"error\":\"no workspace named x\",\"ok\":false}"))
    }
}
