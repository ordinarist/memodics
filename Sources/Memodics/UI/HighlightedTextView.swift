import AppKit
import SwiftUI
import MemodicsCore

/// Builds attributed text with vocabulary highlighted by intensity level.
/// SPEC §13, §14. Used for both the original selection (matching surface forms)
/// and the translation (matching each vocabulary item's meaning).
enum AttributedHighlighter {

    struct Match {
        let pattern: String
        let level: Int
    }

    static func attributed(text: String, matches: [Match], font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: NSColor.labelColor])

        let ns = text as NSString
        for match in matches where match.level > 0 && !match.pattern.isEmpty {
            let color = HighlightPalette.color(forLevel: match.level)
            var start = 0
            while start < ns.length {
                let range = ns.range(of: match.pattern,
                                     options: [.caseInsensitive],
                                     range: NSRange(location: start, length: ns.length - start))
                if range.location == NSNotFound { break }
                result.addAttribute(.backgroundColor, value: color, range: range)
                start = range.location + max(range.length, 1)
            }
        }
        return result
    }

    /// Highlight the surface forms as they appear in the original text.
    static func originalMatches(_ vocabulary: [LookupVocabulary]) -> [Match] {
        vocabulary.map { Match(pattern: $0.surfaceForm, level: $0.highlightLevel) }
    }

    /// Best-effort highlight of each item's meaning within the translation.
    static func translationMatches(_ vocabulary: [LookupVocabulary]) -> [Match] {
        vocabulary.map { Match(pattern: $0.meaning, level: $0.highlightLevel) }
    }
}

/// Links the vertical scrolling of two scroll views so they move together
/// proportionally — lets the user compare original and translation line-for-line.
final class ScrollSyncController {

    private weak var first: NSScrollView?
    private weak var second: NSScrollView?
    private var tokens: [NSObjectProtocol] = []
    private var isSyncing = false

    func register(_ scrollView: NSScrollView) {
        if first == nil {
            first = scrollView
        } else if second == nil && scrollView !== first {
            second = scrollView
        } else {
            return
        }
        scrollView.contentView.postsBoundsChangedNotifications = true
        let token = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self, weak scrollView] _ in
            guard let self, let scrollView else { return }
            self.sync(from: scrollView)
        }
        tokens.append(token)
    }

    private func sync(from source: NSScrollView) {
        guard !isSyncing, let first, let second else { return }
        let target = (source === first) ? second : first
        isSyncing = true
        defer { isSyncing = false }
        setFraction(fraction(of: source), on: target)
    }

    private func fraction(of scrollView: NSScrollView) -> CGFloat {
        guard let doc = scrollView.documentView else { return 0 }
        let maxScroll = max(doc.frame.height - scrollView.contentView.bounds.height, 0)
        guard maxScroll > 0 else { return 0 }
        return scrollView.contentView.bounds.origin.y / maxScroll
    }

    private func setFraction(_ fraction: CGFloat, on scrollView: NSScrollView) {
        guard let doc = scrollView.documentView else { return }
        let maxScroll = max(doc.frame.height - scrollView.contentView.bounds.height, 0)
        let y = maxScroll * fraction
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    deinit { tokens.forEach { NotificationCenter.default.removeObserver($0) } }
}

/// A bounded, scrollable, highlighted read-only text area. Registers itself with
/// a `ScrollSyncController` so paired instances scroll together (SPEC §14 —
/// keep the popup lightweight even for long selections).
struct SyncableTextView: NSViewRepresentable {
    let text: String
    let matches: [AttributedHighlighter.Match]
    var controller: ScrollSyncController?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        controller?.register(scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textStorage?.setAttributedString(
            AttributedHighlighter.attributed(text: text, matches: matches, font: font))
    }
}
