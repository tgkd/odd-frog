import AppKit

func dropInheritedAgentEnvironment() {
    for key in ProcessInfo.processInfo.environment.keys where key.hasPrefix("CLAUDE") {
        unsetenv(key)
    }
}

dropInheritedAgentEnvironment()
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
