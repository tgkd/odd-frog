import Foundation
import OddFrogCore

// Metadata is the only package list. Optional fourth argument selects a standalone package ID.
do {
    let args = CommandLine.arguments
    guard args.count >= 4 else { throw PluginError.message("Usage: OddFrogPackage <packages-root> <built-products> <destination> [plugin-id]") }
    let root = URL(fileURLWithPath: args[1]), products = URL(fileURLWithPath: args[2]), destination = URL(fileURLWithPath: args[3])
    let discovery = PluginDiscovery.scan(bundled: root, user: root.appendingPathComponent(".absent"))
    guard discovery.errors.isEmpty else { throw PluginError.message(discovery.errors.joined(separator: "\n")) }
    let selected = discovery.packages.filter { args.count < 5 || $0.manifest.id == args[4] }
    guard !selected.isEmpty else { throw PluginError.message("No matching packages.") }
    for package in selected {
        let target = destination.appendingPathComponent(package.manifest.id)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: package.directory.appendingPathComponent("plugin.toml"), to: target.appendingPathComponent("plugin.toml"))
        let assets = package.directory.appendingPathComponent("assets")
        if FileManager.default.fileExists(atPath: assets.path) { try FileManager.default.copyItem(at: assets, to: target.appendingPathComponent("assets")) }
        if let executable = package.manifest.executable {
            let source = products.appendingPathComponent(executable)
            guard FileManager.default.isExecutableFile(atPath: source.path) else { throw PluginError.message("Build \(executable) before packaging \(package.manifest.id).") }
            let output = target.appendingPathComponent(executable)
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: output)
        }
        print("Packaged \(package.manifest.id) \(package.manifest.version)")
    }
} catch { try? FileHandle.standardError.write(contentsOf: Data("\(error)\n".utf8)); exit(1) }
