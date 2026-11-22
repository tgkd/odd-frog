import Foundation
import Darwin
import Testing
import OddFrogPluginAPI
import WorkflowsPluginCore

struct ExecRunnerTests {
    private func request(_ argv: [String], cwd: String = "/tmp") -> ExecRequest {
        ExecRequest(executable: argv[0], argv: argv, cwd: cwd, environment: ProcessInfo.processInfo.environment)
    }

    @Test func argvReachesTheProgramWithoutAShell() async throws {
        let literal = "a b; $HOME `x`"
        let result = try await ProcessGroupRunner().run(request(["/bin/echo", literal]))
        #expect(result.exit == 0)
        #expect(result.stdout == literal + "\n")
    }

    @Test func aBareNameIsFoundThroughThePathSetting() async throws {
        let folder = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let tool = folder.appendingPathComponent("odd-frog-probe")
        try "#!/bin/sh\necho \"found $1\"\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let runner = WorkflowRunner(exec: ProcessGroupRunner(), history: nil, environment: ["PATH": "/usr/bin:/bin"])
        let flow = workflow([exec("probe", 0, [text("odd-frog-probe"), text("it")]),
                             show(1, ref("probe", "output"))])
        let outcome = try await runner.start(flow, input: "", settings: ["path": .string(folder.path)])
        #expect(outcome == .finished(notification: "found it"))
    }

    @Test func aNonZeroExitKeepsStderr() async throws {
        let result = try await ProcessGroupRunner().run(request(["/bin/sh", "-c", "echo out; echo err >&2; exit 4"]))
        #expect(result.exit == 4)
        #expect(result.stdout == "out\n")
        #expect(result.stderr == "err\n")
    }

    @Test func theWorkingFolderIsApplied() async throws {
        let result = try await ProcessGroupRunner().run(request(["/bin/pwd"], cwd: "/usr"))
        #expect(result.stdout == "/usr\n")
    }

    @Test func aMissingExecutableThrows() async throws {
        await #expect(throws: RPCError.self) {
            try await ProcessGroupRunner().run(request(["/no/such/program"]))
        }
    }

    @Test func cancelKillsTheWholeProcessGroup() async throws {
        let folder = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let pidFile = folder.appendingPathComponent("pid")
        let script = "sleep 30 & echo $! > '\(pidFile.path)'; wait"
        let running = Task { try await ProcessGroupRunner().run(request(["/bin/sh", "-c", script])) }
        var child: pid_t = 0
        #expect(await eventually {
            guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
                  let value = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
            child = value
            return true
        })
        try #require(child > 0)
        running.cancel()
        await #expect(throws: CancellationError.self) { try await running.value }
        #expect(await eventually { kill(child, 0) != 0 && errno == ESRCH })
    }
}
