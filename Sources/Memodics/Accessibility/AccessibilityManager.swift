import AppKit
import ApplicationServices

/// Primary selection mechanism: the macOS Accessibility API. SPEC §5.
///
/// Correctly reports permission state and never pretends to work when
/// permission has not been granted.
final class AccessibilityManager {

    /// Whether this process is trusted for Accessibility (permission granted).
    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Trigger the system permission prompt (adds the app to the Accessibility
    /// list with a checkbox the user can enable).
    @discardableResult
    func promptForPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Attempt to read the currently selected text from the focused UI element
    /// of the frontmost application. Returns nil if unavailable/unsupported —
    /// the caller falls back to the clipboard (SPEC §6).
    func selectedText() -> String? {
        guard isTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide,
                                            kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success,
              let focusedElement = focused else {
            return nil
        }
        // Force-cast is safe: the focused-UI-element attribute is an AXUIElement.
        let element = focusedElement as! AXUIElement

        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element,
                                                   kAXSelectedTextAttribute as CFString,
                                                   &value)
        guard status == .success, let text = value as? String, !text.isEmpty else {
            return nil
        }
        return text
    }

    /// Open the Accessibility pane of System Settings so the user can grant
    /// permission. SPEC §5.
    func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Localized name of the frontmost application (recorded as the lookup's
    /// source application, SPEC §17).
    func frontmostApplicationName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }
}
