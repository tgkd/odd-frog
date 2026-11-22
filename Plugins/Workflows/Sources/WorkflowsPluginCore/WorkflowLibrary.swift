import Foundation
import OddFrogPluginAPI

public struct WorkflowLibrary: Sendable, Equatable {
    public var workflows: [Workflow]
    public var errors: [WorkflowFileError]
    public init(workflows: [Workflow] = [], errors: [WorkflowFileError] = []) {
        self.workflows = workflows; self.errors = errors
    }

    public static func scan(folders: [URL]) -> WorkflowLibrary {
        var library = WorkflowLibrary()
        var seenFiles: Set<String> = []
        for folder in folders {
            let files: [URL]
            do {
                files = try workflowFiles(in: folder)
            } catch {
                library.errors.append(WorkflowFileError(file: folder, message: message(for: error)))
                continue
            }
            for file in files {
                guard seenFiles.insert(file.resolvingSymlinksInPath().path).inserted else { continue }
                library.add(file)
            }
        }
        return library
    }

    private mutating func add(_ file: URL) {
        let workflow: Workflow
        do {
            workflow = try WorkflowParser.parse(String(contentsOf: file, encoding: .utf8), file: file)
        } catch {
            errors.append(WorkflowFileError(file: file, message: Self.message(for: error)))
            return
        }
        if let earlier = workflows.first(where: { $0.id == workflow.id }) {
            errors.append(WorkflowFileError(file: file, message: "The id \"\(workflow.id)\" is already used by \(earlier.file.lastPathComponent)."))
        } else if let earlier = workflows.first(where: { $0.keyword == workflow.keyword }) {
            errors.append(WorkflowFileError(file: file, message: "The keyword \"\(workflow.keyword)\" is already used by \(earlier.file.lastPathComponent)."))
        } else {
            workflows.append(workflow)
        }
    }

    private static func workflowFiles(in folder: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RPCError("workflow", "Folder not found.")
        }
        let entries = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                 options: [.skipsHiddenFiles])
        return entries
            .filter { $0.pathExtension.lowercased() == "toml" && isRegularFile($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private static func message(for error: Error) -> String {
        (error as? RPCError)?.message ?? error.localizedDescription
    }
}
