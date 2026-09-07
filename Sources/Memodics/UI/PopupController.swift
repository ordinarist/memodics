import AppKit
import SwiftUI
import MemodicsCore

/// Presents the translation result in a lightweight floating panel positioned
/// near the mouse, without stealing keyboard focus. SPEC §14.
@MainActor
final class PopupController {

    private var panel: NSPanel?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    private let onMarkUnderstood: (VocabularyItem) -> Void

    init(onMarkUnderstood: @escaping (VocabularyItem) -> Void) {
        self.onMarkUnderstood = onMarkUnderstood
    }

    func show(outcome: LookupOutcome) {
        dismiss()

        let model = PopupViewModel(outcome: outcome, onMarkUnderstood: onMarkUnderstood)
        let root = PopupView(model: model, onClose: { [weak self] in self?.dismiss() })
        let hosting = NSHostingView(rootView: root)
        hosting.setFrameSize(hosting.fittingSize)

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = wrap(hosting)
        panel.setContentSize(hosting.fittingSize)

        positionNearMouse(panel)
        // orderFrontRegardless keeps the user's current app active (no focus steal).
        panel.orderFrontRegardless()
        self.panel = panel

        installDismissMonitors()
    }

    func dismiss() {
        if let g = globalClickMonitor { NSEvent.removeMonitor(g); globalClickMonitor = nil }
        if let l = localClickMonitor { NSEvent.removeMonitor(l); localClickMonitor = nil }
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Helpers

    private func wrap(_ hosting: NSHostingView<PopupView>) -> NSView {
        let container = NSVisualEffectView()
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        container.frame = hosting.frame
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        return container
    }

    private func positionNearMouse(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x + 12, y: mouse.y - size.height - 12)

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        panel.setFrameOrigin(origin)
    }

    private func installDismissMonitors() {
        // Click outside the popup dismisses it.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { self?.dismiss(); return nil } // Esc
            return event
        }
    }
}
