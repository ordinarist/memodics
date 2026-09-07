import CoreGraphics

/// Synthesizes a ⌘C keystroke to copy the current selection in the frontmost
/// application, used by the clipboard fallback (SPEC §6).
enum CopyCommand {

    /// Virtual key code for the "c" key on a US keyboard.
    private static let keyC: CGKeyCode = 0x08

    static func perform() {
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false)
        keyUp?.flags = .maskCommand

        let tap = CGEventTapLocation.cghidEventTap
        keyDown?.post(tap: tap)
        keyUp?.post(tap: tap)
    }
}
