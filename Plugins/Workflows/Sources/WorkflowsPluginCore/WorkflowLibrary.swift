import Foundation

public struct WorkflowLibrary: Sendable, Equatable {
    public var workflows: [Workflow]
    public var errors: [WorkflowFileError]
    public init(workflows: [Workflow] = [], errors: [WorkflowFileError] = []) {
        self.workflows = workflows; self.errors = errors
    }

    public static func scan(folders: [URL]) -> WorkflowLibrary {
        WorkflowLibrary()
    }
}
