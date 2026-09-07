import AppKit
import SwiftUI

/// Lazily-created window hosting the vocabulary dashboard. SPEC §19.
@MainActor
final class DashboardWindowController {
    private var window: NSWindow?
    private let model: DashboardViewModel

    init(environment: AppEnvironment) {
        self.model = DashboardViewModel(environment: environment)
    }

    func show() {
        model.reload()
        if window == nil {
            let hosting = NSHostingController(rootView: DashboardView(model: model))
            let win = NSWindow(contentViewController: hosting)
            win.title = "Memodics — Vocabulary"
            win.setContentSize(NSSize(width: 820, height: 520))
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.isReleasedWhenClosed = false
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Lazily-created settings window. SPEC §23.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: SettingsStore
    private let onProviderChanged: () -> Void
    private let accessibilityTrusted: () -> Bool
    private let onOpenAccessibility: () -> Void

    init(settings: SettingsStore,
         onProviderChanged: @escaping () -> Void,
         accessibilityTrusted: @escaping () -> Bool,
         onOpenAccessibility: @escaping () -> Void) {
        self.settings = settings
        self.onProviderChanged = onProviderChanged
        self.accessibilityTrusted = accessibilityTrusted
        self.onOpenAccessibility = onOpenAccessibility
    }

    func show() {
        if window == nil {
            let view = SettingsView(settings: settings,
                                    onProviderChanged: onProviderChanged,
                                    accessibilityTrusted: accessibilityTrusted(),
                                    onOpenAccessibility: onOpenAccessibility)
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: hosting)
            win.title = "Memodics — Settings"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
