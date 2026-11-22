import Foundation
import OddFrogPluginAPI

public enum WorkflowRows {
    public static func rows(runs: [RunRecord], details: [String: String] = [:], errors: [WorkflowFileError],
                            hasFolders: Bool, keywords: [String], query: String, maxResults: Int) -> [PluginItem] {
        let filter = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = runs.filter { run in
            filter.isEmpty || run.workflowTitle.localizedCaseInsensitiveContains(filter)
                || run.workflowID.localizedCaseInsensitiveContains(filter)
        }
        let active = matching.filter(\.state.isActive).sorted { $0.started > $1.started }
        let ended = matching.filter { !$0.state.isActive }
            .sorted { ($0.ended ?? $0.started) > ($1.ended ?? $1.started) }
        let fileErrors = errors.filter { filter.isEmpty || $0.file.path.localizedCaseInsensitiveContains(filter) }
        var items = (active + ended).map { row($0, detail: details[$0.id]) } + fileErrors.map { row($0) }
        if !hasFolders {
            items.append(PluginItem(id: "setup", title: "Choose a workflow folder",
                                    subtitle: "Settings › Plugins › Workflows", kind: "Workflow", symbol: "folder.badge.plus"))
        } else if runs.isEmpty && errors.isEmpty {
            let subtitle = keywords.isEmpty
                ? "No workflows in the chosen folders."
                : "Type a workflow keyword: " + keywords.joined(separator: ", ")
            items.append(PluginItem(id: "empty", title: "No workflow runs yet", subtitle: subtitle, kind: "Workflow",
                                    symbol: "flowchart"))
        }
        return Array(items.prefix(max(0, maxResults)))
    }

    static func row(_ run: RunRecord, detail: String?) -> PluginItem {
        switch run.state {
        case .paused:
            let payload: JSONValue = .object(["run": .string(run.id)])
            return PluginItem(id: run.id, title: run.workflowTitle,
                              subtitle: stepList(run) + " · Return continues the review",
                              kind: "Workflow", symbol: "pause.circle",
                              primary: PluginAction(.callback, "continue", payload: payload),
                              secondary: PluginAction(.callback, "cancel", payload: payload), multiline: true)
        case .running:
            return PluginItem(id: run.id, title: run.workflowTitle, subtitle: stepList(run) + " · Return cancels",
                              kind: "Workflow", symbol: "arrow.triangle.2.circlepath",
                              primary: PluginAction(.callback, "cancel", payload: .object(["run": .string(run.id)])),
                              multiline: true)
        case .finished:
            let duration = durationText((run.ended ?? run.started).timeIntervalSince(run.started))
            return PluginItem(id: run.id, title: run.workflowTitle,
                              subtitle: "Finished · " + stepList(run) + " · " + duration,
                              kind: "Workflow", symbol: "checkmark.circle")
        case .failed:
            let label = run.steps.last(where: { $0.state == .failed })?.label ?? "A step"
            let summary = run.error ?? "Unknown error."
            let subtitle = StepFailure.joined(summary, detail: detail)
            return PluginItem(id: run.id, title: "\(run.workflowTitle): \(label) failed", subtitle: subtitle,
                              kind: "Workflow", symbol: "exclamationmark.triangle",
                              primary: PluginAction(.copy, subtitle), multiline: true)
        case .cancelled:
            return PluginItem(id: run.id, title: run.workflowTitle, subtitle: "Cancelled at " + stoppedLabel(run),
                              kind: "Workflow", symbol: "xmark.circle")
        case .interrupted:
            return PluginItem(id: run.id, title: run.workflowTitle,
                              subtitle: "Stopped at " + stoppedLabel(run) + " by a plugin reload or quit",
                              kind: "Workflow", symbol: "xmark.circle")
        }
    }

    static func row(_ error: WorkflowFileError) -> PluginItem {
        PluginItem(id: "error:" + error.file.path, title: "Cannot load " + error.file.lastPathComponent,
                   subtitle: error.message, kind: "Workflow", symbol: "exclamationmark.triangle",
                   primary: PluginAction(.reveal, error.file.path), multiline: true)
    }

    static func stepList(_ run: RunRecord) -> String {
        run.steps.map { "\($0.label) \(word($0.state, paused: run.state == .paused))" }.joined(separator: " · ")
    }

    static func durationText(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        guard total >= 60 else { return "\(total) s" }
        return "\(total / 60) min \(total % 60) s"
    }

    private static func word(_ state: RunRecord.Step.State, paused: Bool) -> String {
        switch state {
        case .pending: "waiting"
        case .running: paused ? "review" : "running"
        case .done: "done"
        case .failed: "failed"
        case .cancelled: "cancelled"
        }
    }

    private static func stoppedLabel(_ run: RunRecord) -> String {
        let step = run.steps.first { $0.state == .cancelled || $0.state == .running }
            ?? run.steps.first { $0.state == .pending }
            ?? run.steps.last
        return step?.label ?? "the start"
    }
}
