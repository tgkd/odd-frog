import Foundation
import Testing
import OddFrogPluginAPI
@testable import OddFrogCore

struct PluginTests {
    private func manifest(id: String = "fixture", keyword: String = "fixture", service: String? = nil) -> String {
        """
        id = "\(id)"
        name = "Fixture"
        version = "1.0.0"
        api_version = 1
        executable = "provider"
        keyword = "\(keyword)"
        services = \(service.map { "[\"\($0)\"]" } ?? "[]")
        """
    }

    private func temp() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("odd-frog-plugin-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func fixture(in root: URL, source: String) throws -> URL {
        let url = root.appendingPathComponent("provider")
        try ("#!/usr/bin/python3\n" + source + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test func discoveryOverridesBundledDefaultsAndRejectsDuplicates() throws {
        let root = try temp()
        defer { try? FileManager.default.removeItem(at: root) }
        let shipped = root.appendingPathComponent("bundled")
        let user = root.appendingPathComponent("user")
        for parent in [shipped, user] {
            let folder = parent.appendingPathComponent("one")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try manifest().write(to: folder.appendingPathComponent("plugin.toml"), atomically: true, encoding: .utf8)
            _ = try fixture(in: folder, source: "pass")
        }
        let bundled = PluginDiscovery.scan(bundled: shipped, user: root.appendingPathComponent("missing"))
        #expect(bundled.packages[0].isEnabled(settings: []))
        let override = PluginDiscovery.scan(bundled: shipped, user: user)
        #expect(override.packages.count == 1)
        #expect(!override.packages[0].bundled)
        #expect(!override.packages[0].isEnabled(settings: []))
        #expect(override.packages[0].isEnabled(settings: [PluginSetting(id: "fixture", enabled: true)]))
        try FileManager.default.copyItem(at: user.appendingPathComponent("one"), to: user.appendingPathComponent("two"))
        let ambiguous = PluginDiscovery.scan(bundled: nil, user: user)
        #expect(ambiguous.packages.isEmpty)
        #expect(ambiguous.errors.count == 1)
    }

    @Test func manifestValidationAndKeywordBoundaries() throws {
        #expect(throws: (any Error).self) { try PluginManifest.parse(manifest().replacingOccurrences(of: "api_version = 1", with: "api_version = 99")) }
        #expect(throws: (any Error).self) { try PluginManifest.parse(manifest().replacingOccurrences(of: "\"provider\"", with: "\"../provider\"")) }
        let package = PluginPackage(manifest: try PluginManifest.parse(manifest(keyword: "cal")), directory: URL(fileURLWithPath: "/tmp"), bundled: true)
        #expect(package.query(from: " CAL tomorrow ") == "tomorrow")
        #expect(package.query(from: "calendar") == nil)
        #expect(package.query(from: "calculate") == nil)
        #expect(package.query(from: "> cal") == nil)
        let settings = Settings(plugins: [PluginSetting(id: "fixture", enabled: false)])
        #expect(try Settings.parse(settings.serialized()) == settings)
        #expect(try Settings.parse("").plugins.isEmpty)
    }

    @Test func realProcessExchangesJSONAndRejectsInvalidResponses() async throws {
        let root = try temp()
        defer { try? FileManager.default.removeItem(at: root) }
        let request = PluginRequest(query: "hello", fullQuery: "fixture hello")
        let valid = "import json, sys\nr = json.load(sys.stdin)\njson.dump({'apiVersion': 1, 'id': r['id'], 'items': [{'id': 'one', 'title': r['query']}]}, sys.stdout)"
        let executable = try fixture(in: root, source: valid)
        let response = try await PluginProcess.exchange(executable: executable, request: request)
        #expect(response.items.first?.title == "hello")
        for source in ["print('not json')", "import sys; sys.exit(7)", valid.replacingOccurrences(of: "'apiVersion': 1", with: "'apiVersion': 2"), valid.replacingOccurrences(of: "r['id']", with: "'wrong'")] {
            _ = try fixture(in: root, source: source)
            await #expect(throws: (any Error).self) { try await PluginProcess.exchange(executable: executable, request: request) }
        }
    }

    @Test func timeoutOversizedOutputAndCancellationStopRealProcesses() async throws {
        let root = try temp()
        defer { try? FileManager.default.removeItem(at: root) }
        let request = PluginRequest(query: "", fullQuery: "fixture")
        let executable = try fixture(in: root, source: "import time; time.sleep(30)")
        await #expect(throws: (any Error).self) { try await PluginProcess.exchange(executable: executable, request: request, timeout: .milliseconds(100)) }
        let task = Task { try await PluginProcess.exchange(executable: executable, request: request) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        _ = try fixture(in: root, source: "import sys; sys.stdout.write('x' * (4 * 1024 * 1024 + 1))")
        await #expect(throws: (any Error).self) { try await PluginProcess.exchange(executable: executable, request: request) }
    }

    @Test @MainActor func coordinatorRejectsUndeclaredServicesAndReloadClearsFailure() async throws {
        let package = PluginPackage(manifest: try PluginManifest.parse(manifest()), directory: URL(fileURLWithPath: "/tmp"), bundled: true)
        let coordinator = PluginCoordinator(readCalendar: { _ in
            Issue.record("Undeclared calendar service must not be called")
            return CalendarSnapshot(access: .fullAccess)
        }, readReminders: { _ in
            Issue.record("Undeclared reminders service must not be called")
            return RemindersSnapshot(access: .fullAccess)
        }, exchange: { _, request in
            PluginResponse(id: request.id, calendarRequest: CalendarRange(start: request.now, end: request.now.addingTimeInterval(3600)))
        })
        let discovery = PluginDiscovery(packages: [package], errors: [])
        coordinator.reload(discovery: discovery, settings: [])
        #expect(coordinator.query("fixture", maxResults: 8)?.first?.item.primary == nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(coordinator.failures["fixture"]?.contains("undeclared") == true)
        coordinator.reload(discovery: discovery, settings: [PluginSetting(id: "fixture", enabled: false)])
        #expect(coordinator.failures.isEmpty)
        #expect(coordinator.query("fixture", maxResults: 8) == nil)
    }

    @Test @MainActor func staleQueriesCannotReplaceCurrentResultsAndCloseClearsRows() async throws {
        let package = PluginPackage(manifest: try PluginManifest.parse(manifest()), directory: URL(fileURLWithPath: "/tmp"), bundled: true)
        let coordinator = PluginCoordinator(readCalendar: { _ in CalendarSnapshot(access: .fullAccess) },
                                            readReminders: { _ in RemindersSnapshot(access: .fullAccess) }, exchange: { _, request in
            if request.operation == .prepare { return PluginResponse(id: request.id) }
            if request.query == "old" { try? await Task.sleep(for: .seconds(1)) }
            return PluginResponse(id: request.id, items: [PluginItem(id: request.query, title: request.query)])
        })
        coordinator.reload(discovery: PluginDiscovery(packages: [package], errors: []), settings: [])
        _ = coordinator.query("fixture old", maxResults: 8)
        try await Task.sleep(for: .milliseconds(150))
        _ = coordinator.query("fixture new", maxResults: 8)
        try await Task.sleep(for: .milliseconds(200))
        #expect(coordinator.query("fixture new", maxResults: 8)?.first?.item.title == "new")
        #expect(coordinator.failures.isEmpty)
        coordinator.invalidate()
        #expect(coordinator.query("fixture new", maxResults: 8)?.first?.item.title == "new")
        coordinator.cancel()
        #expect(coordinator.query("", maxResults: 8) == nil)
    }

    @Test @MainActor func hostServiceRangeActionAndKeywordValidation() throws {
        let now = Date()
        #expect(!CalendarRange(start: now, end: now).isValid(relativeTo: now))
        #expect(!CalendarRange(start: now, end: now.addingTimeInterval(40 * 86400)).isValid(relativeTo: now))
        #expect(!CalendarRange(start: now.addingTimeInterval(-3 * 86400), end: now).isValid(relativeTo: now))
        #expect(!RemindersScope(limit: 0).isValid())
        #expect(!RemindersScope(limit: 2001).isValid())
        #expect(RemindersScope(limit: 2000).isValid())
        let plain = PluginPackage(manifest: try PluginManifest.parse(manifest()), directory: URL(fileURLWithPath: "/tmp"), bundled: true)
        let calendar = PluginPackage(manifest: try PluginManifest.parse(manifest(id: "calendar", service: "calendar.events")), directory: URL(fileURLWithPath: "/tmp"), bundled: true)
        let reminders = PluginPackage(manifest: try PluginManifest.parse(manifest(id: "reminders", keyword: "rem", service: "reminders.items")), directory: URL(fileURLWithPath: "/tmp"), bundled: true)
        #expect(throws: (any Error).self) { try PluginManifest.parse(manifest(service: "nope")) }
        let coordinator = PluginCoordinator(readCalendar: { _ in CalendarSnapshot(access: .fullAccess) },
                                            readReminders: { _ in RemindersSnapshot(access: .fullAccess) },
                                            exchange: { _, request in PluginResponse(id: request.id) })
        coordinator.reload(discovery: PluginDiscovery(packages: [plain, calendar], errors: []), settings: [])
        #expect(coordinator.failures.count == 2)
        coordinator.reload(discovery: PluginDiscovery(packages: [calendar, reminders], errors: []), settings: [])
        try coordinator.authorize(PluginAction(.requestCalendarAccess), pluginID: "calendar")
        try coordinator.authorize(PluginAction(.requestRemindersAccess), pluginID: "reminders")
        try coordinator.authorize(PluginAction(.completeReminder, "item-id"), pluginID: "reminders")
        try coordinator.authorize(PluginAction(.createReminder, "Buy milk"), pluginID: "reminders")
        #expect(throws: (any Error).self) { try coordinator.authorize(PluginAction(.completeReminder), pluginID: "reminders") }
        #expect(throws: (any Error).self) { try coordinator.authorize(PluginAction(.createReminder, "   "), pluginID: "reminders") }
        #expect(throws: (any Error).self) { try coordinator.authorize(PluginAction(.createReminder, String(repeating: "x", count: 501)), pluginID: "reminders") }
        #expect(throws: (any Error).self) { try coordinator.authorize(PluginAction(.completeReminder, "item-id"), pluginID: "calendar") }
        #expect(throws: (any Error).self) { try coordinator.authorize(PluginAction(.createReminder, "Buy milk"), pluginID: "calendar") }
        #expect(throws: (any Error).self) { try coordinator.authorize(PluginAction(.requestRemindersAccess), pluginID: "calendar") }
        #expect(throws: (any Error).self) { try coordinator.authorize(PluginAction(.requestCalendarAccess), pluginID: "reminders") }
        #expect(throws: (any Error).self) { try coordinator.authorize(PluginAction(.openURL, "file:///etc/passwd"), pluginID: "calendar") }
        #expect(throws: (any Error).self) { try coordinator.authorize(PluginAction(.openURL, "javascript:alert(1)"), pluginID: "calendar") }
        coordinator.reload(discovery: PluginDiscovery(packages: [plain], errors: []), settings: [])
        #expect(throws: (any Error).self) { try coordinator.authorize(PluginAction(.requestCalendarAccess), pluginID: "fixture") }
    }

    @Test @MainActor func remindersServiceIsReadOnlyForDeclaringPackages() async throws {
        let reminders = PluginPackage(manifest: try PluginManifest.parse(manifest(id: "reminders", keyword: "rem", service: "reminders.items")),
                                      directory: URL(fileURLWithPath: "/tmp"), bundled: true)
        let scopes = Locked<[RemindersScope]>([])
        func coordinator(limit: Int) -> PluginCoordinator {
            PluginCoordinator(readCalendar: { _ in CalendarSnapshot(access: .fullAccess) }, readReminders: { scope in
                scopes.mutate { $0.append(scope) }
                return RemindersSnapshot(access: .fullAccess, reminders: [ReminderItem(id: "one", title: "Buy milk")])
            }, exchange: { _, request in
                if request.operation == .prepare { return PluginResponse(id: request.id, remindersRequest: RemindersScope(limit: limit)) }
                return PluginResponse(id: request.id, items: (request.reminders?.reminders ?? []).map { PluginItem(id: $0.id, title: $0.title) })
            })
        }
        let valid = coordinator(limit: 5)
        valid.reload(discovery: PluginDiscovery(packages: [reminders], errors: []), settings: [])
        _ = valid.query("rem", maxResults: 8)
        try await Task.sleep(for: .milliseconds(300))
        #expect(valid.query("rem", maxResults: 8)?.first?.item.title == "Buy milk")
        #expect(scopes.value == [RemindersScope(limit: 5)])
        #expect(valid.failures.isEmpty)
        let invalid = coordinator(limit: 0)
        invalid.reload(discovery: PluginDiscovery(packages: [reminders], errors: []), settings: [])
        _ = invalid.query("rem", maxResults: 8)
        try await Task.sleep(for: .milliseconds(300))
        #expect(invalid.failures["reminders"]?.contains("invalid reminders scope") == true)
        #expect(scopes.value == [RemindersScope(limit: 5)])
    }
}

private final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func mutate(_ change: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        change(&stored)
    }
}
