import Foundation
import Testing
@testable import OddFrogCore

struct ScriptTests {
    let killPort = """
    #!/bin/bash

    # Required parameters:
    # @raycast.schemaVersion 1
    # @raycast.title Kill Port
    # @raycast.mode silent

    # Optional parameters:
    # @raycast.icon 🔪
    # @raycast.packageName Kill Port
    # @raycast.argument1 { "type": "text", "placeholder": "Port number" }

    lsof -ti :$1 | xargs kill
    """

    @Test func parsesRaycastHeader() {
        let item = ScriptScanner.parse(header: killPort, url: URL(fileURLWithPath: "/s/kill-port.sh"), executable: true)!
        #expect(item.title == "Kill Port")
        #expect(item.mode == .silent)
        #expect(item.icon == "🔪")
        #expect(item.package == "Kill Port")
        #expect(item.argument == ScriptArgument(placeholder: "Port number", optional: false))
    }

    @Test func optionalArgumentAndFullOutput() {
        let header = "#!/bin/bash\n# @raycast.title Transcribe\n# @raycast.mode fullOutput\n# @raycast.argument1 { \"type\": \"text\", \"placeholder\": \"Path\", \"optional\": true }\n"
        let item = ScriptScanner.parse(header: header, url: URL(fileURLWithPath: "/s/t.sh"), executable: true)!
        #expect(item.mode == .fullOutput)
        #expect(item.argument?.optional == true)
    }

    @Test func executableWithoutHeaderUsesFilename() {
        let item = ScriptScanner.parse(header: "#!/bin/zsh\necho hi\n", url: URL(fileURLWithPath: "/s/say-hi.sh"), executable: true)!
        #expect(item.title == "say-hi")
        #expect(item.icon == nil)
        #expect(item.argument == nil)
    }

    @Test func nonExecutableOrNoShebangIsSkipped() {
        #expect(ScriptScanner.parse(header: "#!/bin/zsh\necho hi\n", url: URL(fileURLWithPath: "/s/x.sh"), executable: false) == nil)
        #expect(ScriptScanner.parse(header: "import Foundation\n", url: URL(fileURLWithPath: "/s/x.swift"), executable: false) == nil)
        #expect(ScriptScanner.parse(header: killPort, url: URL(fileURLWithPath: "/s/x.sh"), executable: false) == nil)
        #expect(ScriptScanner.parse(header: "# CLAUDE.md\n\n```\n# @raycast.title <Command Name>\n```\n", url: URL(fileURLWithPath: "/s/CLAUDE.md"), executable: true) == nil)
    }

    @Test func scanSkipsBinariesAndSources() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("odd-frog-scripts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try killPort.write(to: dir.appendingPathComponent("kill-port.sh"), atomically: true, encoding: .utf8)
        try Data([0xCF, 0xFA, 0xED, 0xFE, 0, 0, 0, 0]).write(to: dir.appendingPathComponent("helper"))
        try "import Foundation\n".write(to: dir.appendingPathComponent("helper.swift"), atomically: true, encoding: .utf8)
        for name in ["kill-port.sh", "helper"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.appendingPathComponent(name).path)
        }
        let items = ScriptScanner.scan(folders: [dir])
        #expect(items.map { $0.title } == ["Kill Port"])
    }

    @Test func argumentIsSplitFromQuery() {
        let script = LauncherItem.script(ScriptScanner.parse(header: killPort, url: URL(fileURLWithPath: "/s/kill-port.sh"), executable: true)!)
        let app = LauncherItem.app(AppItem(url: URL(fileURLWithPath: "/Applications/Kill Ring.app"), name: "Kill Ring", bundleID: nil))
        let results = SearchEngine.search(query: "kill 3000", items: [app, script], weights: [:], maxResults: 8)
        #expect(results.count == 1)
        #expect(results.first?.item.id == script.id)
        #expect(results.first?.argument == "3000")
        let plain = SearchEngine.search(query: "kill port", items: [app, script], weights: [:], maxResults: 8)
        #expect(plain.first { $0.item.id == script.id }?.argument == nil)
        let two = SearchEngine.search(query: "kill port 80 81", items: [script], weights: [:], maxResults: 8)
        #expect(two.first?.argument == "80 81")
    }

    @Test func settingsRoundTripAndApply() throws {
        var settings = Settings(scripts: .init(folders: ["~/Projects/raycast-scripts"], watch: true))
        settings.setOverride(ItemOverride(id: "/Applications/Xcode.app", enabled: false))
        settings.setOverride(ItemOverride(id: "command:Build", aliases: ["bb"]))
        settings.setOverride(ItemOverride(id: "command:Noop"))
        settings.search.url = "https://www.google.com/search?q={query}"
        let text = try settings.serialized()
        let parsed = try Settings.parse(text)
        #expect(parsed == settings)
        #expect(parsed.items.count == 2)
        #expect(parsed.scriptFolders.first?.path == NSHomeDirectory() + "/Projects/raycast-scripts")
        #expect(parsed.search.url == "https://www.google.com/search?q={query}")

        let xcode = LauncherItem.app(AppItem(url: URL(fileURLWithPath: "/Applications/Xcode.app"), name: "Xcode", bundleID: nil))
        let build = LauncherItem.command(CommandItem(name: "Build", aliases: ["b"], action: .shell("make"), cwd: nil, terminal: false))
        let applied = parsed.apply(to: [xcode, build])
        #expect(applied.map { $0.id } == ["command:Build"])
        #expect(applied.first?.aliases == ["b", "bb"])
    }

    @Test func subtitlesOnlyForCollisionsAndInformativeMetadata() {
        let xcode = LauncherItem.app(AppItem(url: URL(fileURLWithPath: "/Applications/Xcode.app"), name: "Xcode", bundleID: nil))
        let xcodeHome = LauncherItem.app(AppItem(url: URL(fileURLWithPath: NSHomeDirectory() + "/Applications/Xcode.app"), name: "Xcode", bundleID: nil))
        let safari = LauncherItem.app(AppItem(url: URL(fileURLWithPath: "/Applications/Safari.app"), name: "Safari", bundleID: nil))
        let ssh = LauncherItem.script(ScriptItem(url: URL(fileURLWithPath: "/s/ssh.sh"), title: "SSH Connections", mode: .fullOutput, icon: nil, package: "SSH Connections", argument: nil))
        let ip = LauncherItem.script(ScriptItem(url: URL(fileURLWithPath: "/s/ip.sh"), title: "Public IP", mode: .silent, icon: nil, package: "Network", argument: nil))
        let build = LauncherItem.command(CommandItem(name: "Build", aliases: [], action: .shell("make"), cwd: nil, terminal: false))
        let docs = LauncherItem.command(CommandItem(name: "Docs", aliases: [], action: .url(URL(string: "https://developer.apple.com/documentation/")!), cwd: nil, terminal: false))
        let subtitles = LauncherItem.subtitles(for: [xcode, xcodeHome, safari, ssh, ip, build, docs])
        #expect(subtitles[xcode.id] == "/Applications")
        #expect(subtitles[xcodeHome.id] == "~/Applications")
        #expect(subtitles[safari.id] == nil)
        #expect(subtitles[ssh.id] == nil)
        #expect(subtitles[ip.id] == "Network")
        #expect(subtitles[build.id] == nil)
        #expect(subtitles[docs.id] == "developer.apple.com/documentation")
        #expect(safari.kindLabel == nil)
        #expect(ip.kindLabel == "Script")
    }

    @Test func appScanSkipsBrokenSymlinksAndDedupesAliases() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("odd-frog-apps-\(UUID().uuidString)")
        let real = dir.appendingPathComponent("Real.app")
        try FileManager.default.createDirectory(at: real.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("Alias.app"), withDestinationURL: real)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("Broken.app"), withDestinationURL: dir.appendingPathComponent("Gone.app"))
        let items = AppScanner.scan(roots: [dir])
        #expect(items.map { $0.name } == ["Real"])
    }

    @Test func emptySettingsParse() throws {
        let s = try Settings.parse("")
        #expect(s == .empty)
    }
}
