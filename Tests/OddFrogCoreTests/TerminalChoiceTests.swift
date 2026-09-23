import Foundation
import Testing
import OddFrogPluginAPI
@testable import OddFrogCore

struct TerminalChoiceTests {
    @Test func missingOrUnknownAppIsTerminalPreset() {
        #expect(TerminalChoice(values: nil) == .preset(.terminal))
        #expect(TerminalChoice(values: ["app": .string("Nope")]) == .preset(.terminal))
    }

    @Test func knownPresets() {
        #expect(TerminalChoice(values: ["app": .string("agterm")]) == .preset(.agterm))
        #expect(TerminalChoice(values: ["app": .string("iTerm2")]) == .preset(.iterm))
    }

    @Test func customChoice() {
        #expect(TerminalChoice(values: ["app": .string("Custom"), "custom_command": .string("x {command}")]) == .custom("x {command}"))
        #expect(TerminalChoice(values: ["app": .string("Custom")]) == .custom(""))
    }

    @Test func customTerminalCommandRequiresCommandToken() {
        #expect(ShellCommand.customTerminalCommand(template: "", shell: "/bin/zsh", cwd: "/tmp", command: "echo hi") == nil)
        #expect(ShellCommand.customTerminalCommand(template: "   ", shell: "/bin/zsh", cwd: "/tmp", command: "echo hi") == nil)
        #expect(ShellCommand.customTerminalCommand(template: "open -a Foo", shell: "/bin/zsh", cwd: "/tmp", command: "echo hi") == nil)
    }

    @Test func customTerminalCommandSubstitutesInOnePass() {
        #expect(ShellCommand.customTerminalCommand(template: "run {cwd} {shell} {command} {other}", shell: "/bin/zsh", cwd: "/tmp/a b", command: "echo {cwd}") == "run '/tmp/a b' '/bin/zsh' 'echo {cwd}' {other}")
    }

    @Test func customTerminalCommandRunsVerbatim() throws {
        let command = try #require(ShellCommand.customTerminalCommand(template: "printf '%s|%s' {cwd} {command}", shell: "/bin/sh", cwd: "/tmp/it's here", command: "echo \"$HOME\" it's"))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", command]
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        #expect(out == "/tmp/it's here|echo \"$HOME\" it's")
    }
}