import AppKit
import Carbon.HIToolbox

/// Registers a single global hotkey that triggers an on-demand lookup of the
/// current selection.
///
/// macOS provides no reliable, battery-friendly, cross-application
/// "selection changed" event without per-app Accessibility observers, and the
/// spec forbids pretending capabilities exist (SPEC §5, §17). An on-demand
/// hotkey is the supported mechanism that preserves the product behavior:
/// select text anywhere → invoke → popup with translation.
final class HotKeyManager {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// Called (on the main thread) when the hotkey is pressed.
    var onTrigger: (() -> Void)?

    /// Default: ⌥⌘L.
    func register(keyCode: UInt32 = UInt32(kVK_ANSI_L),
                  modifiers: UInt32 = UInt32(cmdKey | optionKey)) {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onTrigger?() }
            return noErr
        }, 1, &eventType, selfPointer, &eventHandler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D454D4F), id: 1) // 'MEMO'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
    }

    deinit { unregister() }
}
