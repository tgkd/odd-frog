import AppKit
import OddFrogCore
import OddFrogBuiltins
import OddFrogPluginAPI
import OddFrogHostServicesAPI
import EventKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let calendarService = CalendarService()
    private let remindersService = RemindersService()
    private lazy var plugins = makePluginCoordinator()

    private func makePluginCoordinator() -> PluginCoordinator {
        let registry = HostServiceRegistry()
        registerHostServices(registry)
        let coordinator = PluginCoordinator(services: registry)
        coordinator.builtins = BuiltinProviders.factories
        return coordinator
    }

    private var pluginTimer: Timer?
    private var calendarObserver: (any NSObjectProtocol)?
    private let icons = IconCache()
    private let notifier = Notifier()
    private let hotkeys = HotKeyManager()
    private lazy var frecency = FrecencyStore(url: FrecencyStore.defaultURL)
    private let status = StatusMenu()
    private lazy var controller = LauncherViewController(icons: icons)
    lazy var panel = LauncherPanel(contentViewController: controller)
    private lazy var executor = ActionExecutor(config: config, frecency: frecency, notifier: notifier)
    lazy var settingsWindow = SettingsWindowController(icons: icons)
    private lazy var documents = DocumentWindowController()
    private lazy var chats = ChatWindowController()
    private lazy var months = MonthWindowController()
    private let configWatcher = ConfigWatcher(path: ConfigLoader.defaultPath)
    private let settingsWatcher = ConfigWatcher(path: SettingsLoader.defaultPath)
    private let packageWatcher = DirectoryWatcher()
    private var migrationReady = false

    private var config = Config.empty
    private var settings = Settings.empty
    private var allItems: [LauncherItem] = []
    private var lastWeightsRefresh: Date?
    private var toggleSignal: DispatchSourceSignal?
    private var snapshotSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        TerminalLauncher.cleanupStaleFiles()
        installMainMenu()
        notifier.requestAuthorizationIfNeeded()
        guard migrateIfNeeded() else { return }
        loadInitialConfig()
        loadInitialSettings()
        wirePanel()
        wirePlugins()
        wireStatusMenu()
        wireHotkey()
        wireSignals()
        configWatcher.start(lastContents: try? Data(contentsOf: ConfigLoader.defaultPath)) { data in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { delegate.reloadConfig(from: data, source: "config changed") }
            }
        }
        settingsWatcher.start(lastContents: try? Data(contentsOf: SettingsLoader.defaultPath)) { data in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { delegate.reloadSettings(from: data) }
            }
        }
        Task { await refreshWeights() }

    }

    private func installMainMenu() {
        let file = NSMenu(title: "File")
        file.addItem(NSMenuItem(title: "Save", action: #selector(DocumentWindowController.saveDocument(_:)), keyEquivalent: "s"))
        file.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let fileItem = NSMenuItem()
        fileItem.submenu = file
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editItem = NSMenuItem()
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(NSMenuItem())
        main.addItem(fileItem)
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func report(_ message: String) {
        status.lastFailure = message
        notifier.failure(message)
    }

    private func loadInitialConfig() {
        let template = Bundle.main.resourceURL?.appendingPathComponent("config.example.toml")
        do {
            try ConfigLoader.ensureExists(at: ConfigLoader.defaultPath, template: template)
            config = try ConfigLoader.load(from: ConfigLoader.defaultPath).config
        } catch {
            report("Config error: \(error). Using defaults.")
            config = .empty
        }
    }

    private func loadInitialSettings() {
        guard FileManager.default.fileExists(atPath: SettingsLoader.defaultPath.path) else { return }
        do {
            settings = try SettingsLoader.load(from: SettingsLoader.defaultPath).settings
        } catch {
            report("Settings error: \(error). Ignoring settings.toml.")
        }
    }

    private func wirePanel() {
        controller.maxResults = config.general.maxResults
        controller.onSubmit = { [weak self] item, argument, secondary in
            guard let self else { return }
            hidePanel()
            executor.run(item, argument: argument, secondary: secondary)
        }
        controller.onDismiss = { [weak self] in self?.hidePanel() }
        controller.onReveal = { [weak self] item in
            guard let self else { return }
            hidePanel()
            settingsWindow.links = config.commands.filter { if case .url = $0.action { true } else { false } }
        settingsWindow.present(settings: settings, items: allItems, hotkey: hotkeys.current ?? config.general.hotkey, focusing: item.id)
        }
        controller.onSettings = { [weak self] in
            guard let self else { return }
            hidePanel()
            showSettings()
        }
        panel.onKeyEquivalent = { [weak self] event in self?.controller.handleKeyEquivalent(event) ?? false }
        controller.onHeightChange = { [weak self] height in
            guard let self, panel.isVisible else { return }
            panel.resize(height: height)
        }
        panel.onResignKey = { [weak self] in self?.hidePanel() }
        executor.onFailure = { [weak self] message in
            self?.status.lastFailure = message
        }
        executor.onRecorded = { [weak self] in Task { await self?.refreshWeights() } }
        settingsWindow.onChange = { [weak self] updated in self?.applySettings(updated, persist: true) }
        settingsWindow.onApplyLink = { [weak self] original, draft in
            guard let self else { throw LinkEditError.message("Settings is no longer available.") }
            return try applyLink(original: original, draft: draft)
        }
        settingsWindow.onHotkey = { [weak self] hotkey in self?.setHotkey(hotkey) }
    }

    private func wirePlugins() {
        controller.pluginQuery = { [weak self] query, items, weights, limit in
            guard let self else { return [] }
            guard panel.isVisible else { return SearchEngine.search(query: query, items: items, weights: weights, maxResults: limit) }
            return plugins.search(query, items: items, weights: weights, maxResults: limit)
        }
        plugins.onChange = { [weak self] in
            guard let self else { return }
            rebuildItems()
            updatePluginsPane()
            if panel.isVisible { controller.refresh(keepSelection: true) }
        }
        executor.onPluginAction = { [weak self] result, argument, secondary in self?.runPluginAction(result, argument: argument, secondary: secondary) }
        documents.performSave = { [weak self] session, revision, text, completion in
            _ = self?.plugins.activate(session.result, action: session.save, argument: nil, text: text, completion: completion)
        }
        chats.performSend = { [weak self] session, text, completion in
            self?.plugins.activate(session.result, action: session.send, argument: nil, text: text, completion: completion)
        }
        chats.cancelSend = { [weak self] token in
            self?.plugins.cancelAction(token)
        }
        plugins.onMessageDelta = { [weak self] pluginID, delta in
            self?.chats.apply(delta, pluginID: pluginID)
        }
        settingsWindow.pluginsPane.onReload = { [weak self] in self?.reloadPlugins() }
        settingsWindow.pluginsPane.onToggle = { [weak self] id, enabled in
            guard let self else { return }
            var updated = settings
            updated.plugins.removeAll { $0.id == id }
            guard let package = plugins.packages.first(where: { $0.manifest.id == id }) else { return }
            let previous = package.setting(in: settings.plugins)
            updated.plugins.append(PluginSetting(id: id, enabled: enabled, source: package.source, values: previous?.values, trigger: previous?.trigger))
            applySettings(updated, persist: true)
        }
        settingsWindow.pluginsPane.onSetting = { [weak self] id, key, value in
            guard let self, let package = plugins.packages.first(where: { $0.manifest.id == id }) else { return }
            var updated = settings
            var setting = package.setting(in: updated.plugins)
                ?? PluginSetting(id: id, enabled: package.isEnabled(settings: settings.plugins), source: package.source)
            var values = setting.values ?? [:]; values[key] = value; setting.values = values
            updated.plugins.removeAll { $0.id == id }; updated.plugins.append(setting)
            applySettings(updated, persist: true)
        }
        settingsWindow.pluginsPane.onTrigger = { [weak self] id, trigger in
            guard let self, let package = plugins.packages.first(where: { $0.manifest.id == id }) else {
                return
            }
            var updated = settings
            var setting = package.setting(in: updated.plugins)
                ?? PluginSetting(id: id, enabled: package.isEnabled(settings: settings.plugins), source: package.source)
            setting.trigger = trigger
            updated.plugins.removeAll { $0.id == id }
            updated.plugins.append(setting)
            applySettings(updated, persist: true)
        }
        settingsWindow.pluginsPane.onManageLinks = { [weak self] in
            guard let self else { return }
            settingsWindow.links = config.commands.filter { if case .url = $0.action { true } else { false } }; settingsWindow.manageLinks()
        }
        status.onReloadPlugins = { [weak self] in self?.reloadPlugins() }
        calendarObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.storeDidChange() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(storeDidChange), name: NSApplication.didBecomeActiveNotification, object: nil)
        reloadPlugins()
    }

    private func reloadPlugins() {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Plugins", isDirectory: true)
        let user = ConfigLoader.defaultDirectory.appendingPathComponent("plugins", isDirectory: true)
        let discovery = PluginDiscovery.scan(bundled: bundled, user: user)
        plugins.reload(discovery: discovery, settings: settings.plugins)
        documents.pluginsDidReload()
        chats.pluginsDidReload()
        var watched = discovery.packages.map(\.directory) + [user, user.deletingLastPathComponent()]
        for package in discovery.packages {
            if let enumerator = FileManager.default.enumerator(at: package.directory, includingPropertiesForKeys: [.isDirectoryKey]) {
                for case let url as URL in enumerator { watched.append(url) }
            }
        }
        packageWatcher.watch(watched) { [weak self] in Task { @MainActor in self?.reloadPlugins() } }
    }

    private func updatePluginsPane() {
        settingsWindow.update(pluginSettings: settings.plugins)
        settingsWindow.pluginsPane.update(packages: plugins.packages, settings: settings.plugins,
                                          failures: plugins.failures, errors: plugins.discoveryErrors)
    }

    @objc private func storeDidChange() {
        Task {
            await calendarService.invalidate()
            await remindersService.invalidate()
            plugins.services.invalidate("calendar.changes@1")
            plugins.services.invalidate("reminders.changes@1")
        }
    }

    private func runPluginAction(_ result: PluginResult, argument: String?, secondary: Bool) {
        guard let action = secondary ? (result.item.secondary ?? result.item.primary) : result.item.primary else { return }
        let package: PluginPackage
        do { package = try plugins.authorize(result, action: action) }
        catch { report(String(describing: error)); return }
        if action.kind == .callback || action.kind == .service {
            _ = plugins.activate(result, action: action, argument: argument) { [weak self] response in
                guard let self else { return }
                switch response {
                case .success(let effects):
                    if let text = effects.notification { notifier.post(title: result.item.title, body: text, log: false) }
                    executor.recordPlugin(result)
                    if let view = effects.view {
                        switch view.kind {
                        case .editor:
                            if let save = view.save {
                                documents.present(view, save: save, result: result, pluginName: package.manifest.name)
                            }
                        case .chat:
                            if let send = view.send {
                                chats.present(view, send: send, result: result, pluginName: package.manifest.name)
                            }
                        case .month:
                            months.present(view)
                        }
                    }
                case .failure(let error):
                    if error is CancellationError { return }
                    report(String(describing: error))
                }
            }
            status.onCancelAction = { [weak self] in self?.plugins.cancelActions() }
        } else { executor.runHost(action, result: result, argument: argument) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if documents.prepareToTerminate({ ok in NSApp.reply(toApplicationShouldTerminate: ok) }) {
            return .terminateLater
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        plugins.stop()
        packageWatcher.stop()
        pluginTimer?.invalidate()
        if let calendarObserver { NotificationCenter.default.removeObserver(calendarObserver) }
    }

    private func wireStatusMenu() {
        status.hotkeyDescription = config.general.hotkey.description
        status.onShow = { [weak self] in self?.togglePanel() }
        status.onSettings = { [weak self] in self?.showSettings() }
        status.onReloadConfig = { [weak self] in
            guard let self, let data = try? Data(contentsOf: ConfigLoader.defaultPath) else { return }
            configWatcher.markApplied(data)
            reloadConfig(from: data, source: "manual reload")
        }
        status.onOpenConfig = {
            let template = Bundle.main.resourceURL?.appendingPathComponent("config.example.toml")
            _ = try? ConfigLoader.ensureExists(at: ConfigLoader.defaultPath, template: template)
            NSWorkspace.shared.open(ConfigLoader.defaultPath)
        }
        status.onOpenLog = { NSWorkspace.shared.open(Log.url) }
        status.onRescan = { [weak self] in self?.plugins.refreshCatalogs() }
        status.onToggleLogin = { [weak self] in
            do { try LoginItem.toggle() } catch { self?.report("Launch at Login: \(error.localizedDescription)") }
        }
    }

    private func wireHotkey() {
        hotkeys.onPress = { [weak self] in self?.togglePanel() }
        do {
            try hotkeys.apply(config.general.hotkey)
            Log.write("hotkey \(config.general.hotkey.description) registered")
        } catch {
            report("Hotkey: \(error)")
            if config.general.hotkey != .default {
                try? hotkeys.apply(.default)
                status.hotkeyDescription = Hotkey.default.description
            }
        }
    }

    private func wireSignals() {
        signal(SIGUSR1, SIG_IGN)
        let toggle = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        toggle.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.togglePanel() } }
        toggle.resume()
        toggleSignal = toggle
        signal(SIGUSR2, SIG_IGN)
        let snapshot = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
        snapshot.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.snapshotPanel() } }
        snapshot.resume()
        snapshotSignal = snapshot
    }

    func reloadConfig(from data: Data, source: String) {
        let text = String(decoding: data, as: UTF8.self)
        let candidate: Config
        do {
            candidate = try ConfigParser.parse(text)
        } catch {
            report("Config not applied (\(source)): \(error)")
            return
        }
        if candidate.general.hotkey != hotkeys.current {
            do {
                try hotkeys.apply(candidate.general.hotkey)
            } catch {
                report("Config not applied (\(source)): hotkey \(error)")
                return
            }
        }
        config = candidate
        executor.config = candidate
        status.hotkeyDescription = candidate.general.hotkey.description
        controller.maxResults = candidate.general.maxResults
        plugins.refreshCatalogs()
        rebuildItems()
        Log.write("config applied (\(source)): \(candidate.commands.count) commands, hotkey \(candidate.general.hotkey.description)")
    }

    func reloadSettings(from data: Data) {
        do {
            let parsed = try Settings.parse(String(decoding: data, as: UTF8.self))
            applySettings(parsed, persist: false)
            Log.write("settings applied (file changed): \(parsed.plugins.count) packages, \(parsed.items.count) overrides")
        } catch {
            report("Settings not applied: \(error)")
        }
    }

    private func applySettings(_ updated: Settings, persist: Bool) {
        do { try plugins.validateSettings(updated.plugins) }
        catch { report("Settings not applied: \(error)"); return }
        let changed = plugins.packages.contains {
            $0.isEnabled(settings: updated.plugins) != $0.isEnabled(settings: settings.plugins)
                || (try? $0.trigger(in: updated.plugins)) != (try? $0.trigger(in: settings.plugins))
        }
        if persist {
            do { settingsWatcher.markApplied(try SettingsLoader.save(updated, to: SettingsLoader.defaultPath)) }
            catch { report("Could not save settings: \(error.localizedDescription)"); return }
        }
        settings = updated
        if changed { reloadPlugins() }
        else { do { try plugins.updateSettings(updated.plugins) } catch { report("Settings update failed: \(error)") } }
        rebuildItems()
    }

    private func refreshWeights() async {
        controller.weights = await frecency.decayedWeights()
        lastWeightsRefresh = Date()
    }

    private func refreshWeightsIfStale() {
        if let lastWeightsRefresh, Date().timeIntervalSince(lastWeightsRefresh) < 600 { return }
        Task { await refreshWeights() }
    }

    private func rebuildItems() {
        allItems = plugins.catalogItems
        let items = settings.apply(to: allItems)
        if items != controller.items {
            controller.items = items
        }
        if settingsWindow.window?.isVisible == true {
            settingsWindow.update(items: allItems)
        }
    }

    private func showSettings() {
        settingsWindow.present(settings: settings, items: allItems, hotkey: hotkeys.current ?? config.general.hotkey)
    }

    private func applyLink(original: CommandItem?, draft: LinkDraft?) throws -> [CommandItem] {
        let saved = try LinkEditor.save(to: ConfigLoader.defaultPath, original: original, draft: draft)
        configWatcher.markApplied(saved.contents)
        reloadConfig(from: saved.contents, source: "links settings")
        if let original, draft == nil {
            var updated = settings
            updated.setOverride(ItemOverride(id: "plugin:commands:" + original.stableID))
            applySettings(updated, persist: true)
        }
        settingsWindow.links = saved.config.commands.filter { if case .url = $0.action { true } else { false } }
        return saved.config.commands.filter { if case .url = $0.action { true } else { false } }
    }

    private func setHotkey(_ hotkey: Hotkey) {
        do {
            try hotkeys.apply(hotkey)
        } catch {
            settingsWindow.showHotkey(hotkeys.current ?? config.general.hotkey, note: "\(error)")
            return
        }
        config.general.hotkey = hotkey
        status.hotkeyDescription = hotkey.description
        settingsWindow.showHotkey(hotkey)
        do {
            let path = ConfigLoader.defaultPath
            let text = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
            let data = Data(ConfigLoader.replacingHotkey(in: text, with: hotkey.serialized).utf8)
            try data.write(to: path, options: .atomic)
            configWatcher.markApplied(data)
            Log.write("hotkey \(hotkey.description) set from settings and written to config")
        } catch {
            report("Hotkey applied but config.toml could not be updated: \(error.localizedDescription)")
        }
    }

    private func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }

    private func showPanel() {
        controller.prepareForShow()
        panel.present(height: controller.preferredHeight)
        let focused = controller.focusField()
        Log.write("panel shown key=\(panel.isKeyWindow) focus=\(focused) results=\(controller.results.count)")
        refreshWeightsIfStale()
    }

    private func hidePanel() {
        plugins.cancel()
        controller.clearTransientResults()
        panel.dismiss()
    }

    private func snapshotPanel() {
        let logs = Log.url.deletingLastPathComponent()
        let command = (try? String(contentsOf: logs.appendingPathComponent("odd-frog-query.txt"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if command.hasPrefix("@settings") {
            showSettings()
            let name = command.dropFirst(9).trimmingCharacters(in: .whitespaces)
            if let pane = SettingsPane.allCases.first(where: { $0.title.lowercased() == name }) { settingsWindow.select(pane) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated {
                    delegate.render(delegate.settingsWindow.window?.contentView, to: logs.appendingPathComponent("odd-frog-settings.png"))
                }
            }
            return
        }
        guard panel.isVisible else {
            Log.write("snapshot skipped: panel not visible")
            return
        }
        if command.hasPrefix("@run ") {
            controller.searchField.stringValue = String(command.dropFirst(5))
            controller.refresh()
            if let first = controller.results.first {
                Log.write("debug run: \(first.item.title) argument=\(first.argument ?? "-")")
                hidePanel()
                executor.run(first.item, argument: first.argument)
            }
            return
        }
        if !command.isEmpty {
            controller.searchField.stringValue = command
            controller.refresh()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            MainActor.assumeIsolated {
                delegate.render(delegate.panel.contentView, to: logs.appendingPathComponent("odd-frog-panel.png"))
            }
        }
    }

    func render(_ view: NSView?, to url: URL) {
        guard let view, let window = view.window else {
            Log.write("snapshot skipped: nothing to render")
            return
        }
        window.displayIfNeeded()
        let windowID = CGWindowID(window.windowNumber)
        guard let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .bestResolution]) else {
            Log.write("snapshot failed: CGWindowListCreateImage returned nil")
            return
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        do {
            try rep.representation(using: .png, properties: [:])?.write(to: url)
            Log.write("snapshot written to \(url.path)")
        } catch {
            Log.write("snapshot failed: \(error)")
        }
    }
}

extension AppDelegate {
    private func migrateIfNeeded() -> Bool {
        do {
            let bundled = Bundle.main.resourceURL?.appendingPathComponent("Plugins")
            let discovery = PluginDiscovery.scan(bundled: bundled, user: ConfigLoader.legacyDirectory.appendingPathComponent("plugins"))
            try V2Migration.migrate(packages: discovery.packages)
            migrationReady = true
            status.onRetryMigration = nil
            return true
        } catch {
            status.lastFailure = "Migration failed: \(error). Fix the original file and select Retry Migration."
            status.onRetryMigration = { [weak self] in self?.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification)) }
            notifier.failure(status.lastFailure!)
            return false
        }
    }

    private func registerHostServices(_ registry: HostServiceRegistry) {
        let calendar = calendarService, reminders = remindersService
        registry.register("calendar.read@1") { [weak registry] params, context in
            registry?.subscribe(context, to: "calendar.changes@1")
            return try .encode(await calendar.snapshot(for: params.decode(CalendarRange.self)))
        }
        registry.register("calendar.access@1", activationRequired: true) { _, _ in
            _ = try await calendar.requestAccess()
            return try .encode(PluginEffects(refreshQuery: true))
        }
        registry.register("reminders.read@1") { [weak registry] params, context in
            registry?.subscribe(context, to: "reminders.changes@1")
            return try .encode(await reminders.snapshot(for: params.decode(RemindersScope.self)))
        }
        registry.register("reminders.access@1", activationRequired: true) { _, _ in
            _ = try await reminders.requestAccess()
            return try .encode(PluginEffects(refreshQuery: true))
        }
        registry.register("reminders.complete@1", activationRequired: true) { params, _ in
            guard let id = params["id"].string, !id.isEmpty else { throw RPCError("params", "A reminder ID is required.") }
            let title = try await reminders.complete(id: id)
            return try .encode(PluginEffects(notification: "Completed: \(title)", refreshQuery: true))
        }
        registry.register("reminders.create@1", activationRequired: true) { params, _ in
            guard let title = params["title"].string?.trimmingCharacters(in: .whitespacesAndNewlines), (1...500).contains(title.count) else {
                throw RPCError("params", "Reminder title must contain 1–500 characters.")
            }
            let list = try await reminders.create(title: title)
            return try .encode(PluginEffects(notification: "Added to \(list): \(title)", refreshQuery: true))
        }
        registry.register("windows.perform@1", activationRequired: true) { [weak self] params, context in
            guard let self, let id = params["action"].string,
                  let action = WindowAction.serviceAction(id) else { throw RPCError("params", "Unknown window operation.") }
            let step = settings.plugins.first { $0.id == context.pluginID }?.values?["cascade_step"]?.number ?? 32
            switch executor.windows.perform(action, cascadeStep: CGFloat(step)) {
            case .done: return try .encode(PluginEffects())
            case .failed(let message): throw RPCError("window", message)
            case .needsAccessibility: throw RPCError("permission", "Allow Odd Frog in System Settings › Privacy & Security › Accessibility, then retry.")
            }
        }
        registry.register("links.manage@1", activationRequired: true) { [weak self] _, _ in
            guard let self else { throw CancellationError() }
            showSettings(); settingsWindow.manageLinks()
            return try .encode(PluginEffects())
        }
        registry.register("links.read@1") { _, _ in try LinkService.read(from: ConfigLoader.defaultPath) }
        registry.register("links.write@1", activationRequired: true) { [weak self] params, _ in
            let result = try LinkService.write(params, to: ConfigLoader.defaultPath)
            if let self { reloadConfig(from: try Data(contentsOf: ConfigLoader.defaultPath), source: "links service") }
            return result
        }
    }
}
