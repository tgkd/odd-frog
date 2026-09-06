import AppKit
import OddFrogCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let icons = IconCache()
    private let notifier = Notifier()
    private let hotkeys = HotKeyManager()
    private let indexer = AppIndexer()
    private let frecency = FrecencyStore(url: FrecencyStore.defaultURL)
    private let status = StatusMenu()
    private lazy var controller = LauncherViewController(icons: icons)
    lazy var panel = LauncherPanel(contentViewController: controller)
    private lazy var executor = ActionExecutor(config: config, frecency: frecency, notifier: notifier)
    lazy var settingsWindow = SettingsWindowController(icons: icons)
    private let configWatcher = ConfigWatcher(path: ConfigLoader.defaultPath)
    private let settingsWatcher = ConfigWatcher(path: SettingsLoader.defaultPath)
    private let scriptWatcher = DirectoryWatcher()
    private let appWatcher = DirectoryWatcher()

    private var config = Config.empty
    private var settings = Settings.empty
    private var apps: [AppItem] = []
    private var scripts: [ScriptItem] = []
    private var allItems: [LauncherItem] = []
    private var lastScriptScan: Date?
    private var lastWeightsRefresh: Date?
    private var toggleSignal: DispatchSourceSignal?
    private var snapshotSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        TerminalLauncher.cleanupStaleFiles()
        notifier.requestAuthorizationIfNeeded()
        loadInitialConfig()
        loadInitialSettings()
        wirePanel()
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
        rewatchScripts()
        Task {
            await refreshApps()
            rearmAppWatcher()
        }
        Task { await refreshScripts(force: true) }
        Task { await refreshWeights() }
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
        controller.searchTemplate = settings.search.url
        controller.onSubmit = { [weak self] item, argument, secondary in
            guard let self else { return }
            hidePanel()
            executor.run(item, argument: argument, secondary: secondary)
        }
        controller.onDismiss = { [weak self] in self?.hidePanel() }
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
        status.onRescan = { [weak self] in
            Task {
                await self?.refreshApps()
                self?.rearmAppWatcher()
                await self?.refreshScripts(force: true)
            }
        }
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
        rebuildItems()
        Log.write("config applied (\(source)): \(candidate.commands.count) commands, hotkey \(candidate.general.hotkey.description)")
    }

    func reloadSettings(from data: Data) {
        do {
            let parsed = try Settings.parse(String(decoding: data, as: UTF8.self))
            applySettings(parsed, persist: false)
            Log.write("settings applied (file changed): \(parsed.scripts.folders.count) folders, \(parsed.items.count) overrides")
        } catch {
            report("Settings not applied: \(error)")
        }
    }

    private func applySettings(_ updated: Settings, persist: Bool) {
        let foldersChanged = updated.scripts.folders != settings.scripts.folders || updated.scripts.watch != settings.scripts.watch
        settings = updated
        if persist {
            do {
                let data = try SettingsLoader.save(settings, to: SettingsLoader.defaultPath)
                settingsWatcher.markApplied(data)
            } catch {
                report("Could not save settings: \(error.localizedDescription)")
            }
        }
        if foldersChanged {
            rewatchScripts()
            Task { await refreshScripts(force: true) }
        }
        rebuildItems()
        controller.searchTemplate = settings.search.url
    }

    private func rewatchScripts() {
        guard settings.scripts.watch, !settings.scriptFolders.isEmpty else {
            scriptWatcher.watch([]) {}
            return
        }
        scriptWatcher.watch(settings.scriptFolders) {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { _ = Task { await delegate.refreshScripts(force: true) } }
            }
        }
    }

    private func rearmAppWatcher() {
        appWatcher.watch(AppScanner.watchedDirectories(roots: AppScanner.defaultRoots)) {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { _ = Task { await delegate.refreshApps() } }
            }
        }
    }

    private func refreshApps() async {
        let result = await indexer.refresh()
        guard result != apps else { return }
        apps = result
        icons.prewarm(apps)
        rebuildItems()
    }

    func refreshScripts(force: Bool = false) async {
        if !force, let lastScriptScan, Date().timeIntervalSince(lastScriptScan) < 60 { return }
        let folders = settings.scriptFolders
        scripts = await Task.detached(priority: .utility) { ScriptScanner.scan(folders: folders) }.value
        lastScriptScan = Date()
        Log.write("scripts scanned: \(scripts.count) in \(folders.count) folders")
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
        allItems = apps.map(LauncherItem.app) + config.commands.map(LauncherItem.command) + scripts.map(LauncherItem.script)
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
        // Renames keep the item's visibility and extra aliases; deletion removes stale overrides.
        if let original, let old = settings.override(for: original.id) {
            var updated = settings
            updated.setOverride(ItemOverride(id: original.id))
            if let replacement = try draft?.command() {
                updated.setOverride(ItemOverride(id: replacement.id, enabled: old.enabled, aliases: old.aliases))
            }
            applySettings(updated, persist: true)
        }
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
        if !settings.scripts.watch {
            Task { await refreshScripts() }
        }
        refreshWeightsIfStale()
    }

    private func hidePanel() {
        panel.dismiss()
    }

    private func snapshotPanel() {
        let logs = Log.url.deletingLastPathComponent()
        let command = (try? String(contentsOf: logs.appendingPathComponent("odd-frog-query.txt"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if command == "@settings" {
            showSettings()
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
