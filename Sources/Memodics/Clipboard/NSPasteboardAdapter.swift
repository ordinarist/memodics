import AppKit
import MemodicsCore

/// Real system-pasteboard implementation of `PasteboardProviding`. SPEC §6.
///
/// `capture`/`restore` round-trip *all* pasteboard items and types, so the
/// user's clipboard is restored exactly — including non-text content.
final class NSPasteboardAdapter: PasteboardProviding, @unchecked Sendable {

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    func capture() -> PasteboardSnapshot {
        var items: [[String: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var dict: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type.rawValue] = data
                }
            }
            if !dict.isEmpty { items.append(dict) }
        }
        return PasteboardSnapshot(items: items)
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }
        let items = snapshot.items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    func readString() -> String? {
        pasteboard.string(forType: .string)
    }
}
