import Foundation
import OddFrogBuiltins
import OddFrogCore
import OddFrogPluginAPI

do {
    let manifestURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("plugin.toml")
    let manifest = try PluginManifest.parse(String(contentsOf: manifestURL, encoding: .utf8))
    guard let factory = BuiltinProviders.factories[manifest.id] else {
        throw PluginError.message("No bundled core for \(manifest.id).")
    }
    try await ProviderServer(oneShot: manifest.mode == .oneShot, provider: factory()).run()
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("\(error)\n".utf8))
    exit(1)
}
