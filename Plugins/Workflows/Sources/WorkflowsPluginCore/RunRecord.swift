import Foundation

public struct RunRecord: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case running, paused, finished, failed, cancelled, interrupted

        public var isActive: Bool { self == .running || self == .paused }
    }

    public struct Step: Codable, Sendable, Equatable {
        public enum State: String, Codable, Sendable { case pending, running, done, failed, cancelled }
        public var label: String
        public var kind: String
        public var state: State
        public var started: Date?
        public var ended: Date?
        public var exit: Int?
        public var error: String?
        public init(label: String, kind: String, state: State = .pending, started: Date? = nil, ended: Date? = nil,
                    exit: Int? = nil, error: String? = nil) {
            self.label = label; self.kind = kind; self.state = state; self.started = started; self.ended = ended
            self.exit = exit; self.error = error
        }
    }

    public var id: String
    public var workflowID: String
    public var workflowTitle: String
    public var state: State
    public var started: Date
    public var ended: Date?
    public var steps: [Step]
    public var error: String?

    public init(id: String, workflowID: String, workflowTitle: String, state: State, started: Date, ended: Date? = nil,
                steps: [Step], error: String? = nil) {
        self.id = id; self.workflowID = workflowID; self.workflowTitle = workflowTitle; self.state = state
        self.started = started; self.ended = ended; self.steps = steps; self.error = error
    }
}

public enum RunHistory {
    public static let limit = 30
    public static let fileName = "runs.json"

    public static func load(from file: URL) -> [RunRecord] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? decoder().decode([RunRecord].self, from: data)) ?? []
    }

    public static func save(_ runs: [RunRecord], to file: URL) throws {
        let data = try encoder().encode(trimmed(runs))
        let temporary = file.deletingLastPathComponent().appendingPathComponent(".\(fileName).\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temporary.path, contents: data,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(temporary.path, file.path) == 0 else {
            let code = errno
            try? FileManager.default.removeItem(at: temporary)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    public static func trimmed(_ runs: [RunRecord]) -> [RunRecord] {
        let sorted = runs.sorted { $0.started > $1.started }
        guard sorted.count > limit else { return sorted }
        let active = sorted.filter(\.state.isActive)
        let ended = sorted.filter { !$0.state.isActive }.prefix(max(0, limit - active.count))
        return (active + ended).sorted { $0.started > $1.started }
    }

    public static func interrupted(_ runs: [RunRecord], at now: Date) -> [RunRecord] {
        runs.map { run in
            guard run.state.isActive else { return run }
            var run = run
            run.state = .interrupted
            run.ended = run.ended ?? now
            run.steps = run.steps.map { step in
                guard step.state == .running else { return step }
                var step = step
                step.state = .cancelled
                step.ended = step.ended ?? now
                return step
            }
            return run
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
