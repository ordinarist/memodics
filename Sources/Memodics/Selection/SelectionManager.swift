import AppKit
import MemodicsCore

/// A captured selection plus the app it came from.
struct CapturedSelection {
    let text: String
    let sourceApplication: String?
}

/// Orchestrates selection capture: Accessibility API first, clipboard fallback
/// second, then qualification. SPEC §5, §6, §7.
///
/// Keeps macOS-specific extraction separate from translation logic (SPEC §26).
final class SelectionManager {

    private let accessibility: AccessibilityManager
    private let clipboard: ClipboardExtractor
    private let qualifier: TextQualifier

    init(accessibility: AccessibilityManager,
         clipboard: ClipboardExtractor,
         qualifier: TextQualifier) {
        self.accessibility = accessibility
        self.clipboard = clipboard
        self.qualifier = qualifier
    }

    /// Capture the current selection, or nil if none is usable.
    ///
    /// Should be called off the main thread: the clipboard fallback briefly
    /// polls the pasteboard after synthesizing ⌘C.
    func captureCurrentSelection() -> CapturedSelection? {
        let sourceApp = accessibility.frontmostApplicationName()

        // 1. Primary: Accessibility API.
        if let axText = accessibility.selectedText(), qualifier.isProcessable(axText) {
            return CapturedSelection(text: axText, sourceApplication: sourceApp)
        }

        // 2. Fallback: clipboard extraction with guaranteed restoration.
        do {
            if let copied = try clipboard.extract(performCopy: { CopyCommand.perform() }),
               qualifier.isProcessable(copied) {
                return CapturedSelection(text: copied, sourceApplication: sourceApp)
            }
        } catch {
            // Extraction failed; clipboard was still restored by the extractor.
            NSLog("Memodics: clipboard extraction failed: \(error)")
        }

        return nil
    }
}
