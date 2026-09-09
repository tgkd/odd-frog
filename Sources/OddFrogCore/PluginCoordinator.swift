import Foundation
import OddFrogPluginAPI

@MainActor
public final class PluginCoordinator {
    public typealias CalendarReader = @Sendable (CalendarRange) async throws -> CalendarSnapshot
    public typealias RemindersReader = @Sendable (RemindersScope) async throws -> RemindersSnapshot
    public typealias Exchange = @Sendable (URL, PluginRequest) async throws -> PluginResponse
    public private(set) var packages: [PluginPackage] = []
    public private(set) var discoveryErrors: [String] = []
    public private(set) var failures: [String: String] = [:]
    public private(set) var settings: [PluginSetting] = []
    public var onChange: (() -> Void)?
    private let readCalendar: CalendarReader
    private let readReminders: RemindersReader
    private let exchange: Exchange
    private var task: Task<Void, Never>?
    private var generation = 0
    private var currentQuery: String?
    private var currentLimit = 0
    private var results: [PluginResult]?
    private var refreshQuery: String?
    private var refreshResults: [PluginResult]?

    public init(readCalendar: @escaping CalendarReader,
                readReminders: @escaping RemindersReader,
                exchange: @escaping Exchange) {
        self.readCalendar = readCalendar
        self.readReminders = readReminders
        self.exchange = exchange
    }

    public func reload(discovery: PluginDiscovery, settings: [PluginSetting]) {
        cancel()
        packages = discovery.packages
        discoveryErrors = discovery.errors
        self.settings = settings
        failures = [:]
        let enabled = packages.filter { $0.isEnabled(settings: settings) }
        let groups = Dictionary(grouping: enabled, by: { $0.manifest.keyword })
        for (keyword, values) in groups where values.count > 1 {
            for package in values { failures[package.manifest.id] = "Keyword '\(keyword)' is used by multiple enabled plugins." }
        }
        onChange?()
    }

    public func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        currentQuery = nil
        results = nil
        refreshQuery = nil
        refreshResults = nil
    }

    public func invalidate() {
        let previousQuery = currentQuery
        let previousResults = results
        cancel()
        refreshQuery = previousQuery
        refreshResults = previousResults
        onChange?()
    }

    public func query(_ fullQuery: String, maxResults: Int) -> [PluginResult]? {
        if currentQuery == fullQuery, currentLimit == maxResults { return results }
        let retained = refreshQuery == fullQuery ? refreshResults : nil
        cancel()
        currentQuery = fullQuery
        currentLimit = maxResults
        guard let package = packages.first(where: { $0.isEnabled(settings: settings) && $0.query(from: fullQuery) != nil }),
              let query = package.query(from: fullQuery) else { return nil }
        let id = package.manifest.id
        if let failure = failures[id] {
            results = status(package, title: "\(package.manifest.name) unavailable", subtitle: failure)
            return results
        }
        results = retained ?? status(package, title: "Loading \(package.manifest.name)…", subtitle: nil)
        let token = generation
        let request = PluginRequest(query: query, fullQuery: fullQuery, maxResults: maxResults)
        let exchange = self.exchange
        let readCalendar = self.readCalendar
        let readReminders = self.readReminders
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(75))
                let preparation = try await exchange(package.executable, request)
                try Task.checkCancellation()
                guard preparation.items.isEmpty else { throw PluginError.message("Prepare must return service requests, not items.") }
                var next = request
                next.operation = .query
                if let range = preparation.calendarRequest {
                    guard package.manifest.services.contains(PluginProtocol.calendarService), range.isValid(relativeTo: request.now) else {
                        throw PluginError.message("Plugin requested an undeclared service or an invalid calendar range.")
                    }
                    next.calendar = try await readCalendar(range)
                }
                if let scope = preparation.remindersRequest {
                    guard package.manifest.services.contains(PluginProtocol.remindersService), scope.isValid() else {
                        throw PluginError.message("Plugin requested an undeclared service or an invalid reminders scope.")
                    }
                    next.reminders = try await readReminders(scope)
                }
                try Task.checkCancellation()
                let response = try await exchange(package.executable, next)
                try Task.checkCancellation()
                guard response.calendarRequest == nil, response.remindersRequest == nil else {
                    throw PluginError.message("Query cannot request more services.")
                }
                for item in response.items {
                    for action in [item.primary, item.secondary].compactMap({ $0 }) {
                        try Self.validate(action, package: package)
                    }
                }
                guard let self, token == generation else { return }
                results = response.items.prefix(maxResults).map { PluginResult(pluginID: id, item: $0) }
                task = nil
                onChange?()
            } catch is CancellationError {
                // Superseded requests must never replace the new query's results or status.
            } catch {
                guard let self, token == generation else { return }
                failures[id] = String(describing: error)
                results = status(package, title: "\(package.manifest.name) unavailable", subtitle: String(describing: error))
                task = nil
                onChange?()
            }
        }
        return results
    }

    public func authorize(_ action: PluginAction, pluginID: String) throws {
        guard let package = packages.first(where: { $0.manifest.id == pluginID && $0.isEnabled(settings: settings) }) else {
            throw PluginError.message("Plugin is no longer enabled.")
        }
        try Self.validate(action, package: package)
    }

    private static func validate(_ action: PluginAction, package: PluginPackage) throws {
        switch action.kind {
        case .requestCalendarAccess:
            guard package.manifest.services.contains(PluginProtocol.calendarService) else {
                throw PluginError.message("Plugin did not declare calendar access.")
            }
        case .requestRemindersAccess:
            guard package.manifest.services.contains(PluginProtocol.remindersService) else {
                throw PluginError.message("Plugin did not declare reminders access.")
            }
        case .completeReminder:
            guard package.manifest.services.contains(PluginProtocol.remindersService) else {
                throw PluginError.message("Plugin did not declare reminders access.")
            }
            guard !action.value.isEmpty else { throw PluginError.message("Plugin returned an empty reminder ID.") }
        case .createReminder:
            guard package.manifest.services.contains(PluginProtocol.remindersService) else {
                throw PluginError.message("Plugin did not declare reminders access.")
            }
            let title = action.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...500).contains(title.count) else { throw PluginError.message("Plugin returned an invalid reminder title.") }
        case .openURL:
            guard let url = URL(string: action.value), let scheme = url.scheme?.lowercased(),
                  ["https", "http", "x-apple.systempreferences"].contains(scheme) else {
                throw PluginError.message("Plugin returned an unsupported URL.")
            }
        case .openApplication:
            guard !action.value.isEmpty else { throw PluginError.message("Plugin returned an empty application ID.") }
        case .copy: break
        }
    }

    private func status(_ package: PluginPackage, title: String, subtitle: String?) -> [PluginResult] {
        [PluginResult(pluginID: package.manifest.id,
                      item: PluginItem(id: "host-status", title: title, subtitle: subtitle, symbol: "puzzlepiece.extension"))]
    }
}
