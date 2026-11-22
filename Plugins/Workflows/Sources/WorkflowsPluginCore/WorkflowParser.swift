import Foundation
import OddFrogPluginAPI

public enum WorkflowParser {
    public static func parse(_ text: String, file: URL) throws -> Workflow {
        throw RPCError("workflow", "The workflow parser is not built yet.")
    }
}
