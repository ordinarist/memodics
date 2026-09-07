import AppKit

/// Entry point for the Memodics menu-bar application.
///
/// Runs as an accessory (menu-bar, no Dock icon) background utility — SPEC §4.
@main
struct Bootstrap {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
