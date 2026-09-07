import XCTest
@testable import MemodicsCore

final class HighlightLevelTests: XCTestCase {

    func testBucketedScaleFromSpec() {
        // SPEC §13 suggested levels.
        XCTAssertEqual(HighlightLevel.level(forLookupCount: 1), 1)
        XCTAssertEqual(HighlightLevel.level(forLookupCount: 2), 2)
        XCTAssertEqual(HighlightLevel.level(forLookupCount: 3), 2)
        XCTAssertEqual(HighlightLevel.level(forLookupCount: 4), 3)
        XCTAssertEqual(HighlightLevel.level(forLookupCount: 7), 3)
        XCTAssertEqual(HighlightLevel.level(forLookupCount: 8), 4)
        XCTAssertEqual(HighlightLevel.level(forLookupCount: 15), 4)
        XCTAssertEqual(HighlightLevel.level(forLookupCount: 16), 5)
        XCTAssertEqual(HighlightLevel.level(forLookupCount: 31), 5)
        XCTAssertEqual(HighlightLevel.level(forLookupCount: 32), 6)
        XCTAssertEqual(HighlightLevel.level(forLookupCount: 1000), 6)
    }

    func testZeroLookupsHasNoHighlight() {
        XCTAssertEqual(HighlightLevel.level(forLookupCount: 0), 0)
    }

    func testUnderstoodItemNeverHighlighted() {
        // SPEC §11, §13 — understood vocabulary must not be highlighted.
        let item = VocabularyItem(id: 1, lemma: "x", type: .word, meaning: "m", translation: "t",
                                  lookupCount: 50, status: .understood,
                                  firstSeenAt: Date(), lastSeenAt: Date())
        XCTAssertEqual(HighlightLevel.level(for: item), 0)
    }

    func testLearningItemUsesCount() {
        let item = VocabularyItem(id: 1, lemma: "x", type: .word, meaning: "m", translation: "t",
                                  lookupCount: 9, status: .learning,
                                  firstSeenAt: Date(), lastSeenAt: Date())
        XCTAssertEqual(HighlightLevel.level(for: item), 4)
    }
}
