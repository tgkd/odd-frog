import Foundation
import OddFrogPluginAPI

public actor TranslateHandler: ProviderHandler {
    private struct OfflineKey: Hashable {
        var text: String
        var source: String
        var target: String
    }
    private struct OnlineKey: Hashable {
        var text: String
        var target: String
        var key: String
    }
    private struct Stored {
        var outcome: TranslationOutcome
        var date: Date
    }
    private let offline: any OfflineTranslator
    private let online: any OnlineTranslator
    private let offlineWait: Duration
    private let onlineDelay: Duration
    private let retryAfter: TimeInterval
    private var emit: (@Sendable (String) async -> Void)?
    private var offlineResults: [OfflineKey: Stored] = [:]
    private var offlineJobs: [OfflineKey: Task<Void, Never>] = [:]
    private var latestOffline: OfflineKey?
    private var waiters: [OfflineKey: [UUID: CheckedContinuation<TranslationOutcome?, Never>]] = [:]
    private var onlineResults: [OnlineKey: Stored] = [:]
    private var onlineJob: (key: OnlineKey, task: Task<Void, Never>)?

    public init(offline: any OfflineTranslator = AppleTranslator(), online: any OnlineTranslator = DeepLClient(),
                offlineWait: Duration = .milliseconds(600), onlineDelay: Duration = .milliseconds(350),
                retryAfter: TimeInterval = 10) {
        self.offline = offline
        self.online = online
        self.offlineWait = offlineWait
        self.onlineDelay = onlineDelay
        self.retryAfter = retryAfter
    }

    public func start(emit: @escaping @Sendable (String) async -> Void) async {
        self.emit = emit
    }

    public func handle(_ method: String, params: JSONValue, operation: ProviderOperation) async throws -> JSONValue {
        switch method {
        case "initialize":
            return .object(["apiVersion": .number(2)])
        case "settings":
            return .object([:])
        case "query":
            let query = try params["input"].decode(PluginQuery.self)
            let settings = try params["context"].decode(PluginContext.self).settings
            return try .encode(await respond(to: query, settings: settings))
        default:
            throw RPCError("method", "Unsupported method: \(method)")
        }
    }

    public func shutdown() async {
        onlineJob?.task.cancel()
        onlineJob = nil
    }

    private func respond(to query: PluginQuery, settings: [String: JSONValue]) async -> [PluginItem] {
        let trimmed = query.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = String(trimmed.prefix(TranslateProvider.limit))
        let languages = TranslateDirection.languages(settings)
        let key = (settings["deepl_key"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return TranslateProvider.hint(primary: languages.primary, secondary: languages.secondary, deepL: !key.isEmpty)
        }
        let direction = TranslateDirection.resolve(text, primary: languages.primary, secondary: languages.secondary)
        guard direction.source != direction.target else {
            return TranslateProvider.sameLanguages()
        }
        let onlineState = key.isEmpty ? TranslateProvider.Online.off : onlineOutcome(text, direction: direction, key: key)
        let offlineState = await offlineOutcome(text, direction: direction)
        return TranslateProvider.respond(direction: direction, offline: offlineState, online: onlineState,
                                         truncated: text.count < trimmed.count)
    }

    private func offlineOutcome(_ text: String, direction: TranslateDirection) async -> TranslationOutcome? {
        let key = OfflineKey(text: text, source: direction.source.code, target: direction.target.code)
        latestOffline = key
        if let stored = fresh(offlineResults[key]) {
            return stored
        }
        if offlineJobs[key] == nil {
            let translator = offline
            offlineJobs[key] = Task {
                await self.finishOffline(key, outcome: await translator.translate(text, from: direction.source, to: direction.target))
            }
        }
        let id = UUID(), wait = offlineWait
        return await withCheckedContinuation { continuation in
            waiters[key, default: [:]][id] = continuation
            Task {
                try? await Task.sleep(for: wait)
                self.expire(key, id: id)
            }
        }
    }

    private func expire(_ key: OfflineKey, id: UUID) {
        waiters[key]?.removeValue(forKey: id)?.resume(returning: nil)
        if waiters[key]?.isEmpty == true {
            waiters[key] = nil
        }
    }

    private func finishOffline(_ key: OfflineKey, outcome: TranslationOutcome) async {
        let outcome = Self.checked(outcome)
        offlineJobs[key] = nil
        store(&offlineResults, key, outcome)
        let pending = waiters.removeValue(forKey: key) ?? [:]
        for continuation in pending.values {
            continuation.resume(returning: outcome)
        }
        if pending.isEmpty && key == latestOffline {
            await emit?("queryInvalidated")
        }
    }

    private func onlineOutcome(_ text: String, direction: TranslateDirection, key: String) -> TranslateProvider.Online {
        let onlineKey = OnlineKey(text: text, target: direction.target.code, key: key)
        if let stored = fresh(onlineResults[onlineKey]) {
            return .done(stored)
        }
        if onlineJob?.key != onlineKey {
            onlineJob?.task.cancel()
            let translator = online, delay = onlineDelay
            let task = Task {
                guard (try? await Task.sleep(for: delay)) != nil else {
                    return
                }
                let outcome = await translator.translate(text, to: direction.target, key: key)
                guard !Task.isCancelled else {
                    return
                }
                await self.finishOnline(onlineKey, outcome: outcome)
            }
            onlineJob = (onlineKey, task)
        }
        return .pending
    }

    private func finishOnline(_ key: OnlineKey, outcome: TranslationOutcome) async {
        if onlineJob?.key == key {
            onlineJob = nil
        }
        store(&onlineResults, key, Self.checked(outcome))
        await emit?("queryInvalidated")
    }

    private static func checked(_ outcome: TranslationOutcome) -> TranslationOutcome {
        guard case .text(let text) = outcome, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return outcome
        }
        return .failed("The translation came back empty.")
    }

    private func fresh(_ stored: Stored?) -> TranslationOutcome? {
        guard let stored else {
            return nil
        }
        if case .text = stored.outcome {
            return stored.outcome
        }
        // Failures expire so that a downloaded language pack or a fixed key takes effect without a restart.
        return Date().timeIntervalSince(stored.date) < retryAfter ? stored.outcome : nil
    }

    private func store<Key: Hashable>(_ results: inout [Key: Stored], _ key: Key, _ outcome: TranslationOutcome) {
        if results.count >= 256 {
            results.removeAll()
        }
        results[key] = Stored(outcome: outcome, date: Date())
    }
}
