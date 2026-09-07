import AppKit
import ServiceManagement
import MemodicsCore

/// Assembles and coordinates the whole application. SPEC §4, §24.
///
/// All lookup work is wrapped so that any single failure (permission, clipboard,
/// API, malformed response, DB) is surfaced calmly and never crashes the
/// background app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let settings = SettingsStore()
    private let accessibility = AccessibilityManager()

    private var environment: AppEnvironment?
    private var selectionManager: SelectionManager!
    private var popup: PopupController!
    private var menuBar: MenuBarController!
    private var dashboard: DashboardWindowController?
    private var settingsWindow: SettingsWindowController!
    private let hotKey = HotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Database / services. If this fails the app still runs (menu bar only).
        do {
            environment = try AppEnvironment(settings: settings)
        } catch {
            presentError("Could not open the local database", detail: "\(error)")
        }

        let extractor = ClipboardExtractor(pasteboard: NSPasteboardAdapter())
        selectionManager = SelectionManager(
            accessibility: accessibility,
            clipboard: extractor,
            qualifier: TextQualifier(maxCharacters: settings.maxCharacters))

        popup = PopupController(onMarkUnderstood: { [weak self] item in
            self?.markUnderstood(item)
        })

        settingsWindow = SettingsWindowController(
            settings: settings,
            onProviderChanged: { [weak self] in self?.environment?.reloadProvider() },
            accessibilityTrusted: { [weak self] in self?.accessibility.isTrusted() ?? false },
            onOpenAccessibility: { [weak self] in self?.accessibility.openAccessibilitySettings() })

        menuBar = MenuBarController(settings: settings, accessibility: accessibility)
        menuBar.onTranslateSelection = { [weak self] in self?.triggerLookup() }
        menuBar.onToggleDetection = { [weak self] in self?.toggleDetection() }
        menuBar.onGrantAccessibility = { [weak self] in self?.accessibility.promptForPermission() }
        menuBar.onOpenDashboard = { [weak self] in self?.openDashboard() }
        menuBar.onOpenSettings = { [weak self] in self?.settingsWindow.show() }

        hotKey.onTrigger = { [weak self] in self?.triggerLookup() }
        hotKey.register()

        applyLaunchAtLogin(settings.launchAtLogin)

        // Prompt (non-blocking) so the app appears in the Accessibility list.
        if !accessibility.isTrusted() {
            accessibility.promptForPermission()
        }
    }

    // MARK: - Lookup flow

    private func triggerLookup() {
        guard settings.detectionEnabled else {
            NSSound.beep()
            return
        }
        guard let environment else {
            presentError("Not ready", detail: "The database is unavailable.")
            return
        }
        guard settings.isProviderConfigured else {
            presentError("Translation provider not configured",
                         detail: "Add your API key in Settings to enable translation.")
            settingsWindow.show()
            return
        }

        // Capture the selection on the main actor (AppKit + clipboard are
        // main-thread bound; the fallback poll is brief). The network call then
        // runs asynchronously without blocking.
        guard let selection = selectionManager.captureCurrentSelection() else {
            NSSound.beep()
            return
        }
        Task { @MainActor in
            do {
                let outcome = try await environment.pipeline.lookup(
                    rawText: selection.text,
                    sourceApplication: selection.sourceApplication)
                self.popup.show(outcome: outcome)
            } catch {
                self.presentError("Translation failed", detail: "\(error)")
            }
        }
    }

    private func markUnderstood(_ item: VocabularyItem) {
        try? environment?.vocabulary.markUnderstood(id: item.id)
    }

    // MARK: - Actions

    private func toggleDetection() {
        settings.detectionEnabled.toggle()
    }

    private func openDashboard() {
        guard let environment else { return }
        if dashboard == nil {
            dashboard = DashboardWindowController(environment: environment)
        }
        dashboard?.show()
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            // Non-fatal: launch-at-login is best-effort (SPEC §4 "if practical").
            NSLog("Memodics: launch-at-login update failed: \(error)")
        }
    }

    private func presentError(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }
}
