import AppKit

/// Shows a brief, self-dismissing on-screen message panel near the menu bar.
///
/// Used as the visible fallback when native notifications are unavailable —
/// notably ad-hoc-signed local builds, which macOS forbids from posting User
/// Notifications, so `UNUserNotificationCenter` silently drops every banner.
/// This guarantees the user always sees lookup feedback (SPEC §24: detect the
/// missing capability and surface status instead of faking it).
@MainActor
final class HUDNotifier: Notifying {

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    func notify(title: String, body: String) {
        dismissWorkItem?.cancel()
        panel?.orderOut(nil)
        panel = nil

        let panel = Self.makePanel(title: title, body: body)
        position(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
        self.panel = panel
        scheduleDismiss(panel)
    }

    // MARK: - Building

    private static func makePanel(title: String, body: String) -> NSPanel {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.textColor = .white

        let bodyLabel = NSTextField(wrappingLabelWithString: body)
        bodyLabel.font = .systemFont(ofSize: 12)
        bodyLabel.textColor = .white
        bodyLabel.preferredMaxLayoutWidth = 300

        let stack = NSStackView(views: [titleLabel, bodyLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let visual = NSVisualEffectView()
        visual.material = .hudWindow
        visual.state = .active
        visual.blendingMode = .behindWindow
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 10
        visual.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: visual.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: visual.trailingAnchor),
            stack.topAnchor.constraint(equalTo: visual.topAnchor),
            stack.bottomAnchor.constraint(equalTo: visual.bottomAnchor),
        ])

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = visual
        panel.layoutIfNeeded()
        panel.setContentSize(visual.fittingSize)
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: vf.maxX - size.width - 16,
                                     y: vf.maxY - size.height - 16))
    }

    private func scheduleDismiss(_ panel: NSPanel) {
        let work = DispatchWorkItem { [weak self, weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                if self?.panel === panel { self?.panel = nil }
            })
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }
}
