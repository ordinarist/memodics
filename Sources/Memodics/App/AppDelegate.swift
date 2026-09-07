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
    private let logger: Logging = FileLogger(
        fileURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Memodics/memodics.log"))
    private let notifier: Notifying = UserNotifier()

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
            logger.error("Database open failed: \(error)")
            presentError("Could not open the local database", detail: "\(error)")
        }

        let extractor = ClipboardExtractor(pasteboard: NSPasteboardAdapter())
        selectionManager = SelectionManager(
            accessibility: accessibility,
            clipboard: extractor,
            qualifier: TextQualifier(maxCharacters: settings.maxCharacters),
            logger: logger)

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
        logger.info("Lookup triggered")

        guard settings.detectionEnabled else {
            notifier.notify(title: "Detection is off",
                            body: "Enable Detection from the Memodics menu to translate.")
            logger.warning("Lookup skipped: detection disabled")
            return
        }
        guard let environment else {
            notifier.notify(title: "Not ready",
                            body: "The local database is unavailable.")
            logger.error("Lookup skipped: database unavailable")
            return
        }
        guard settings.isProviderConfigured else {
            notifier.notify(title: "Translation provider not configured",
                            body: "Add your API key in Settings to enable translation.")
            logger.warning("Lookup skipped: provider not configured")
            settingsWindow.show()
            return
        }

        guard let selection = selectionManager.captureCurrentSelection() else {
            notifier.notify(title: "No text selected",
                            body: "Select English text in another app, then try again.")
            logger.warning("Lookup skipped: no processable selection captured")
            return
        }

        menuBar.setBusy(true)
        logger.info("Lookup start (source: \(selection.sourceApplication ?? "unknown"))")
        Task { @MainActor in
            defer { self.menuBar.setBusy(false) }
            do {
                let outcome = try await environment.pipeline.lookup(
                    rawText: selection.text,
                    sourceApplication: selection.sourceApplication)
                self.popup.show(outcome: outcome)
                self.logger.info("Lookup success")
            } catch {
                self.notifier.notify(title: "Translation failed", body: "\(error)")
                self.logger.error("Lookup failed: \(error)")
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
            logger.error("Launch-at-login update failed: \(error)")
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
