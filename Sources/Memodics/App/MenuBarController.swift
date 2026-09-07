import AppKit

/// The menu-bar (status item) presence and menu. SPEC §4.
///
/// Lets the user translate the current selection, toggle detection, check/grant
/// Accessibility permission, open the dashboard and settings, and quit.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let settings: SettingsStore
    private let accessibility: AccessibilityManager

    var onTranslateSelection: (() -> Void)?
    var onOpenDashboard: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onToggleDetection: (() -> Void)?
    var onGrantAccessibility: (() -> Void)?

    init(settings: SettingsStore, accessibility: AccessibilityManager) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.settings = settings
        self.accessibility = accessibility
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "book.closed", accessibilityDescription: "Memodics")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // Rebuild the menu each time it opens so state (checkmarks, permission
    // status) is always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let translate = NSMenuItem(title: "Translate Selection",
                                   action: #selector(translateSelection), keyEquivalent: "l")
        translate.keyEquivalentModifierMask = [.command, .option]
        translate.target = self
        menu.addItem(translate)

        menu.addItem(.separator())

        let detection = NSMenuItem(title: "Enable Detection",
                                   action: #selector(toggleDetection), keyEquivalent: "")
        detection.target = self
        detection.state = settings.detectionEnabled ? .on : .off
        menu.addItem(detection)

        if accessibility.isTrusted() {
            let ok = NSMenuItem(title: "Accessibility: Granted", action: nil, keyEquivalent: "")
            ok.isEnabled = false
            menu.addItem(ok)
        } else {
            let warn = NSMenuItem(title: "Accessibility: Not Granted", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
            let grant = NSMenuItem(title: "Grant Accessibility Permission…",
                                   action: #selector(grantAccessibility), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
        }

        menu.addItem(.separator())

        let dashboard = NSMenuItem(title: "Vocabulary Dashboard…",
                                   action: #selector(openDashboard), keyEquivalent: "d")
        dashboard.target = self
        menu.addItem(dashboard)

        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Memodics", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func translateSelection() { onTranslateSelection?() }
    @objc private func toggleDetection() { onToggleDetection?() }
    @objc private func grantAccessibility() { onGrantAccessibility?() }
    @objc private func openDashboard() { onOpenDashboard?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
