import Foundation
import OddFrogPluginAPI

public enum ChatBackendError {
    public static func connection(_ error: URLError, baseURL: URL?) -> RPCError {
        let server = name(of: baseURL)
        let text: String
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost:
            text = "Could not connect to \(server). Start the server, or check the API base URL in Chat settings."
        case .timedOut:
            text = "\(server) did not answer in time."
        case .notConnectedToInternet:
            text = "No internet connection."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            text = "The secure connection to \(server) failed."
        case .badURL, .unsupportedURL:
            text = "The API base URL in Chat settings is not valid."
        default:
            text = "Could not reach \(server): \(error.localizedDescription)"
        }
        return RPCError("chat", sentence(text))
    }

    public static func status(_ code: Int, baseURL: URL?, body: String) -> RPCError {
        let server = name(of: baseURL)
        switch code {
        case 401, 403:
            return RPCError("chat", sentence("\(server) rejected the API key (HTTP \(code)). Check the API key in Chat settings."))
        case 404:
            return RPCError("chat", sentence("\(server) has no chat endpoint at this address (HTTP 404)." + pathHint(baseURL)))
        default:
            let detail = message(inBody: body) ?? String(body.prefix(300))
            return RPCError("chat", sentence("\(server) answered HTTP \(code)" + (detail.isEmpty ? "." : ": \(detail)")))
        }
    }

    public static func server(_ message: String, baseURL: URL?) -> RPCError {
        let hint = message.localizedCaseInsensitiveContains("endpoint") ? pathHint(baseURL) : ""
        return RPCError("chat", sentence("\(name(of: baseURL)) says: \(message)" + hint))
    }

    public static func message(inBody body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let value = try? PluginProtocol.decoder().decode(JSONValue.self, from: data) else {
            return nil
        }
        let candidates = [value["error"]["message"].string, value["error"].string, value["message"].string]
        return candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }

    private static func pathHint(_ baseURL: URL?) -> String {
        guard let baseURL, !baseURL.path.hasSuffix("/v1"), !baseURL.path.hasSuffix("/v1/") else {
            return ""
        }
        return " Check that the API base URL ends with /v1."
    }

    private static func sentence(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    private static func name(of url: URL?) -> String {
        guard let host = url?.host, !host.isEmpty else {
            return "the server"
        }
        return "the server at " + (url?.port.map { "\(host):\($0)" } ?? host)
    }
}
