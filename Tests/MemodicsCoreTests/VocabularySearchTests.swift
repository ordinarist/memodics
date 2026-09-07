import XCTest
@testable import MemodicsCore

final class VocabularySearchTests: XCTestCase {

    private func makeService() throws -> VocabularyService {
        let db = try Database.inMemory()
        let vocab = VocabularyService(database: db)
        _ = try vocab.upsert(lemma: "withdraw", type: .word, meaning: "rút lại", translation: "rút lại")
        _ = try vocab.upsert(lemma: "negotiation", type: .word, meaning: "đàm phán", translation: "đàm phán")
        _ = try vocab.upsert(lemma: "phase out", type: .phrasalVerb, meaning: "loại bỏ dần", translation: "loại bỏ dần")
        return vocab
    }

    func testEmptyQueryReturnsAll() throws {
        let vocab = try makeService()
        XCTAssertEqual(try vocab.search("").count, 3)
    }

    func testMatchesLemmaSubstringCaseInsensitively() throws {
        let vocab = try makeService()
        let results = try vocab.search("WITH")
        XCTAssertEqual(results.map { $0.lemma }, ["withdraw"])
    }

    func testMatchesMeaningSubstring() throws {
        let vocab = try makeService()
        let results = try vocab.search("đàm")
        XCTAssertEqual(results.map { $0.lemma }, ["negotiation"])
    }

    func testStatusFilter() throws {
        let vocab = try makeService()
        let withdraw = try vocab.find(lemma: "withdraw", type: .word)!
        try vocab.markUnderstood(id: withdraw.id)

        XCTAssertEqual(try vocab.search("", status: .understood).map { $0.lemma }, ["withdraw"])
        XCTAssertEqual(Set(try vocab.search("", status: .learning).map { $0.lemma }),
                       ["negotiation", "phase out"])
    }

    func testLimitAndOffsetPaginate() throws {
        let vocab = try makeService()
        // Give deterministic ordering by lookup count.
        let n = try vocab.find(lemma: "negotiation", type: .word)!
        try vocab.incrementLookupCount(id: n.id) // count 1 → sorts first
        let page1 = try vocab.search("", limit: 2, offset: 0)
        let page2 = try vocab.search("", limit: 2, offset: 2)
        XCTAssertEqual(page1.count, 2)
        XCTAssertEqual(page2.count, 1)
        // No overlap between pages.
        XCTAssertTrue(Set(page1.map { $0.id }).isDisjoint(with: Set(page2.map { $0.id })))
    }

    func testCountMatchingForPaginationTotals() throws {
        let vocab = try makeService()
        XCTAssertEqual(try vocab.count(matching: ""), 3)
        XCTAssertEqual(try vocab.count(matching: "with"), 1)
    }
}
