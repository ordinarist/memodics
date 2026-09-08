import AppKit

/// Entry point for the Memodics menu-bar application.
///
/// Runs as an accessory (menu-bar, no Dock icon) background utility — SPEC §4.
@main
struct Bootstrap {
    @MainActor
    static func main() {
        // Initialize the application object FIRST. Touching AppKit (e.g.
        // NSRunningApplication) before NSApplication.shared bootstraps the app
        // in the wrong order and leaves the status item without a menu-bar slot.
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        // Refuse to start a second copy. A duplicate instance (e.g. the login
        // item plus a manual launch) would trigger its own Keychain prompt and
        // fight over the single global hotkey / status item. Activate the
        // existing one and exit.
        let bundleID = Bundle.main.bundleIdentifier ?? "com.memodics.app"
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != mine }
        if let existing = others.first {
            existing.activate(options: [])
            return
        }

        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
