import Foundation

/// Clipboard-based selection extraction — the fallback when the Accessibility
/// API cannot provide the selected text. SPEC §6.
///
/// The user's original clipboard is captured up front and restored via `defer`
/// so it is put back **exactly**, no matter how extraction ends (success,
/// failure, thrown error). This class contains no AppKit code so the
/// save→copy→read→restore contract can be verified with a fake pasteboard.
public final class ClipboardExtractor {

    private let pasteboard: PasteboardProviding
    private let sleep: (TimeInterval) -> Void
    private let maxPollAttempts: Int
    private let pollInterval: TimeInterval

    public init(pasteboard: PasteboardProviding,
                sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
                maxPollAttempts: Int = 20,
                pollInterval: TimeInterval = 0.02) {
        self.pasteboard = pasteboard
        self.sleep = sleep
        self.maxPollAttempts = maxPollAttempts
        self.pollInterval = pollInterval
    }

    /// Preserve the clipboard, trigger a copy of the current selection, read the
    /// result, and always restore the original clipboard.
    ///
    /// - Parameter performCopy: platform action that copies the current
    ///   selection (e.g. synthesizing ⌘C). Abstracted for testability.
    /// - Returns: usable extracted text, or `nil` if nothing usable was copied.
    public func extract(performCopy: () throws -> Void) throws -> String? {
        let snapshot = pasteboard.capture()
        // Guaranteed, error-safe restoration (SPEC §6).
        defer { pasteboard.restore(snapshot) }

        let changeCountBefore = pasteboard.changeCount
        try performCopy()

        // Wait for the copy to land: the pasteboard's changeCount must advance.
        var attempts = 0
        while pasteboard.changeCount == changeCountBefore && attempts < maxPollAttempts {
            sleep(pollInterval)
            attempts += 1
        }
        guard pasteboard.changeCount != changeCountBefore else {
            return nil // nothing was copied (likely no selection / unsupported app)
        }

        guard let text = pasteboard.readString(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }
}
