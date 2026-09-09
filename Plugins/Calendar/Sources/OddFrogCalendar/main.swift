import Foundation
import CalendarPluginCore
import OddFrogPluginAPI

do {
    var data = Data()
    while data.count <= PluginProtocol.maxBytes {
        let chunk = try FileHandle.standardInput.read(upToCount: min(65536, PluginProtocol.maxBytes + 1 - data.count)) ?? Data()
        if chunk.isEmpty { break }
        data.append(chunk)
    }
    guard data.count <= PluginProtocol.maxBytes else { throw ProviderError.invalidRequest }
    let request = try PluginProtocol.decoder().decode(PluginRequest.self, from: data)
    guard request.apiVersion == PluginProtocol.version else { throw ProviderError.invalidRequest }
    let response = CalendarProvider.respond(to: request)
    try FileHandle.standardOutput.write(contentsOf: PluginProtocol.encoder().encode(response))
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("Calendar provider: \(error)\n".utf8))
    exit(1)
}

enum ProviderError: Error { case invalidRequest }
