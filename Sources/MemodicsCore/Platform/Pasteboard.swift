import Foundation

/// Well-known pasteboard type identifiers (avoids importing AppKit into Core).
public enum PasteboardType {
    public static let utf8PlainText = "public.utf8-plain-text"
}

/// A captured snapshot of the entire pasteboard, as an ordered list of items,
/// each mapping a type identifier to its raw data. Enough to restore the
/// clipboard *exactly*, including non-text content (SPEC §6).
public struct PasteboardSnapshot: Equatable, Sendable {
    public let items: [[String: Data]]
    public init(items: [[String: Data]]) { self.items = items }
}

/// Abstraction over the system pasteboard so the clipboard-fallback logic is
/// unit-testable with a fake (SPEC §26). The real `NSPasteboard` adapter lives
/// in the app target.
public protocol PasteboardProviding: AnyObject, Sendable {
    /// Monotonic counter that increases whenever the pasteboard content changes.
    var changeCount: Int { get }
    /// Capture the current full contents for later restoration.
    func capture() -> PasteboardSnapshot
    /// Replace the pasteboard contents with a previously captured snapshot.
    func restore(_ snapshot: PasteboardSnapshot)
    /// Read plain text if present.
    func readString() -> String?
}
