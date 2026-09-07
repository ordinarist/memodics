import XCTest
@testable import MemodicsCore

/// In-memory pasteboard used to verify the save/copy/read/restore contract
/// (SPEC §6) without touching the real system clipboard.
final class FakePasteboard: PasteboardProviding, @unchecked Sendable {
    private(set) var changeCount = 0
    private var items: [[String: Data]] = []

    /// Simulate copying `text` on the next `performCopy` (nil = copy produces nothing).
    var copyProduces: String? = "COPIED"

    func capture() -> PasteboardSnapshot { PasteboardSnapshot(items: items) }

    func restore(_ snapshot: PasteboardSnapshot) {
        items = snapshot.items
        changeCount += 1
    }

    func readString() -> String? {
        guard let data = items.first?[PasteboardType.utf8PlainText] else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // Test helpers -----------------------------------------------------------

    func seed(_ text: String) {
        items = [[PasteboardType.utf8PlainText: Data(text.utf8)]]
        changeCount += 1
    }

    func simulateCopy() {
        guard let produced = copyProduces else { return } // nothing selected → no change
        items = [[PasteboardType.utf8PlainText: Data(produced.utf8)]]
        changeCount += 1
    }
}

final class ClipboardExtractorTests: XCTestCase {

    func testExtractsCopiedText() throws {
        let pb = FakePasteboard()
        pb.seed("USER ORIGINAL")
        pb.copyProduces = "selected sentence"
        let extractor = ClipboardExtractor(pasteboard: pb, sleep: { _ in })

        let text = try extractor.extract(performCopy: { pb.simulateCopy() })
        XCTAssertEqual(text, "selected sentence")
    }

    func testRestoresOriginalClipboardAfterSuccess() throws {
        let pb = FakePasteboard()
        pb.seed("USER ORIGINAL")
        pb.copyProduces = "selected sentence"
        let extractor = ClipboardExtractor(pasteboard: pb, sleep: { _ in })

        _ = try extractor.extract(performCopy: { pb.simulateCopy() })
        XCTAssertEqual(pb.readString(), "USER ORIGINAL", "clipboard must be restored exactly (SPEC §6)")
    }

    func testRestoresClipboardEvenWhenCopyThrows() {
        let pb = FakePasteboard()
        pb.seed("USER ORIGINAL")
        let extractor = ClipboardExtractor(pasteboard: pb, sleep: { _ in })

        struct CopyError: Error {}
        XCTAssertThrowsError(try extractor.extract(performCopy: { throw CopyError() }))
        XCTAssertEqual(pb.readString(), "USER ORIGINAL", "clipboard restored even on error (SPEC §6)")
    }

    func testRestoresClipboardWhenNothingWasCopied() throws {
        let pb = FakePasteboard()
        pb.seed("USER ORIGINAL")
        pb.copyProduces = nil // simulate: no selection, copy changes nothing
        let extractor = ClipboardExtractor(pasteboard: pb, sleep: { _ in }, maxPollAttempts: 3)

        let text = try extractor.extract(performCopy: { pb.simulateCopy() })
        XCTAssertNil(text, "no change in pasteboard → no usable text")
        XCTAssertEqual(pb.readString(), "USER ORIGINAL")
    }

    func testWhitespaceOnlyCopyIsRejectedAndRestores() throws {
        let pb = FakePasteboard()
        pb.seed("USER ORIGINAL")
        pb.copyProduces = "   \n  "
        let extractor = ClipboardExtractor(pasteboard: pb, sleep: { _ in })

        let text = try extractor.extract(performCopy: { pb.simulateCopy() })
        XCTAssertNil(text)
        XCTAssertEqual(pb.readString(), "USER ORIGINAL")
    }

    func testRestoresEmptyClipboardWhenOriginallyEmpty() throws {
        let pb = FakePasteboard() // nothing seeded → empty
        pb.copyProduces = "hello"
        let extractor = ClipboardExtractor(pasteboard: pb, sleep: { _ in })

        _ = try extractor.extract(performCopy: { pb.simulateCopy() })
        XCTAssertNil(pb.readString(), "empty clipboard restored to empty")
    }
}
