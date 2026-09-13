import XCTest
@testable import MemodicsCore

final class VocabularyRankingTests: XCTestCase {
    func testConjunctionTypeExists() {
        XCTAssertEqual(VocabularyType(rawValue: "conjunction"), .conjunction)
    }
    func testRankOrdersWordsThenMultiWordThenConjunction() {
        XCTAssertLessThan(VocabularyType.word.displayRank, VocabularyType.idiom.displayRank)
        XCTAssertLessThan(VocabularyType.phrasalVerb.displayRank, VocabularyType.conjunction.displayRank)
    }
    func testRankedForDisplayIsStableWithinRank() {
        let input = [
            AnalyzedVocabulary(surfaceForm: "however", lemma: "however", meaning: "", type: .conjunction),
            AnalyzedVocabulary(surfaceForm: "phase out", lemma: "phase out", meaning: "", type: .phrasalVerb),
            AnalyzedVocabulary(surfaceForm: "cats", lemma: "cat", meaning: "", type: .word),
            AnalyzedVocabulary(surfaceForm: "dogs", lemma: "dog", meaning: "", type: .word),
        ]
        let ranked = input.rankedForDisplay().map(\.lemma)
        XCTAssertEqual(ranked, ["cat", "dog", "phase out", "however"])
    }
}
