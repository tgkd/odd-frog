import Foundation
import OddFrogPluginAPI

public enum ClipboardStorage {
    public static let memory = "Memory"
    public static let file = "File"

    public static func directory(settings: [String: JSONValue], defaultPath: String) throws -> URL? {
        guard settings["storage"]?.string == file else {
            return nil
        }
        let typed = settings["storage_path"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let path = typed.isEmpty ? defaultPath : NSString(string: typed).expandingTildeInPath
        guard path.hasPrefix("/") else {
            throw RPCError("clipboard", "The clipboard history folder must start with / or ~: \(typed)")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
