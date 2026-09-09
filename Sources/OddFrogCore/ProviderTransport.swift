import Foundation
import OddFrogPluginAPI

public protocol ProviderTransport: Actor {
    func request(_ method: String, params: JSONValue, timeout: Duration?, service: @escaping PluginProcess.Service) async throws -> JSONValue
    func stop()
}

extension PluginProcess: ProviderTransport {}
