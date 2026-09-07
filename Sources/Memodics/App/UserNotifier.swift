// Sources/Memodics/App/UserNotifier.swift
import AppKit
import UserNotifications

/// Presents short user-facing status/error messages. Mockable so AppDelegate
/// routing can be tested without the real notification center.
protocol Notifying {
    func notify(title: String, body: String)
}

/// Posts native macOS banners via UNUserNotificationCenter. When the process is
/// not a bundled `.app` (e.g. `swift run`), the notification center is unusable,
/// so it falls back to NSLog. Never throws to the caller (SPEC §24).
final class UserNotifier: Notifying {

    /// UNUserNotificationCenter.current() traps unless the process is a proper
    /// app bundle. Detect that up front and route around it when unbundled.
    private let isBundledApp = Bundle.main.bundleURL.pathExtension == "app"

    init() {
        guard isBundledApp else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(title: String, body: String) {
        guard isBundledApp else {
            NSLog("Memodics notify: \(title) — \(body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: "\(title)-\(body.hashValue)",
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("Memodics notify failed: \(error)") }
        }
    }
}
