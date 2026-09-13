// Sources/Memodics/App/UserNotifier.swift
import AppKit
import UserNotifications

/// Presents short user-facing status/error messages. Mockable so AppDelegate
/// routing can be tested without the real notification center. Main-actor
/// isolated: presenting feedback always touches AppKit on the main thread.
@MainActor
protocol Notifying {
    func notify(title: String, body: String)
}

/// Posts native macOS banners via UNUserNotificationCenter when they're actually
/// available, and otherwise routes to a visible fallback.
///
/// Native User Notifications require a properly-signed app: ad-hoc-signed local
/// builds (what `build-app.sh` produces) are forbidden by macOS from posting
/// them, and `requestAuthorization` fails silently. Unbundled runs (`swift run`)
/// can't use the notification center at all. In both cases we fall back so the
/// user always sees feedback (SPEC §24). Never throws to the caller.
@MainActor
final class UserNotifier: Notifying {

    /// UNUserNotificationCenter.current() traps unless the process is a proper
    /// app bundle. Detect that up front and route around it when unbundled.
    private let isBundledApp = Bundle.main.bundleURL.pathExtension == "app"

    /// Set true only if the system actually grants notification authorization.
    /// Stays false for ad-hoc builds, so the fallback is used.
    private var authorized = false

    /// Visible surface used whenever native banners aren't available.
    private let fallback: Notifying

    init(fallback: Notifying) {
        self.fallback = fallback
        guard isBundledApp else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
                Task { @MainActor in self?.authorized = granted }
            }
    }

    func notify(title: String, body: String) {
        guard isBundledApp, authorized else {
            fallback.notify(title: title, body: body)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            guard error != nil else { return }
            // Delivery failed after all — still show something visible.
            Task { @MainActor in self?.fallback.notify(title: title, body: body) }
        }
    }
}
