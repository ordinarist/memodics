import XCTest
@testable import MemodicsCore

/// A controllable clock so timestamp behavior is deterministic in tests.
final class TestClock {
    var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) { current = start }
    func now() -> Date { current }
    func advance(_ seconds: TimeInterval) { current.addTimeInterval(seconds) }
}

final class CacheServiceTests: XCTestCase {

    private func makeService() throws -> (CacheService, TestClock) {
        let clock = TestClock()
        let db = try Database.inMemory()
        return (CacheService(database: db, now: clock.now), clock)
    }

    func testMissReturnsNil() throws {
        let (cache, _) = try makeService()
        XCTAssertNil(try cache.get(forRawText: "never stored"))
    }

    func testStoreThenGetHits() throws {
        let (cache, _) = try makeService()
        let stored = try cache.store(rawText: "The company withdrew its offer.",
                                     translation: "Công ty đã rút lại đề nghị.",
                                     analysisJSON: "{}")
        let hit = try cache.get(forRawText: "The company withdrew its offer.")
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.id, stored.id)
        XCTAssertEqual(hit?.translation, "Công ty đã rút lại đề nghị.")
    }

    func testNormalizedEquivalentTextHitsSameEntry() throws {
        let (cache, _) = try makeService()
        _ = try cache.store(rawText: "The company withdrew its offer.",
                            translation: "t", analysisJSON: "{}")
        // Trailing whitespace variant must resolve to the same cache row (SPEC §15).
        let hit = try cache.get(forRawText: "The company withdrew its offer.   ")
        XCTAssertNotNil(hit)
    }

    func testGetUpdatesLastUsedAt() throws {
        let (cache, clock) = try makeService()
        let stored = try cache.store(rawText: "hello", translation: "t", analysisJSON: "{}")
        clock.advance(60)
        let hit = try cache.get(forRawText: "hello")
        XCTAssertEqual(hit?.lastUsedAt, clock.current)
        XCTAssertNotEqual(hit?.lastUsedAt, stored.lastUsedAt)
    }
}

final class VocabularyServiceTests: XCTestCase {

    private func makeService() throws -> (VocabularyService, TestClock) {
        let clock = TestClock()
        let db = try Database.inMemory()
        return (VocabularyService(database: db, now: clock.now), clock)
    }

    func testUpsertNewItemStartsLearningWithZeroCount() throws {
        let (vocab, clock) = try makeService()
        let item = try vocab.upsert(lemma: "withdraw", type: .word,
                                    meaning: "rút lại", translation: "rút lại")
        XCTAssertEqual(item.status, .learning)
        XCTAssertEqual(item.lookupCount, 0)
        XCTAssertEqual(item.lemma, "withdraw")
        XCTAssertEqual(item.firstSeenAt, clock.current)
    }

    func testUpsertExistingReturnsSameCanonicalRow() throws {
        let (vocab, _) = try makeService()
        let a = try vocab.upsert(lemma: "withdraw", type: .word, meaning: "m", translation: "t")
        let b = try vocab.upsert(lemma: "Withdraw", type: .word, meaning: "m2", translation: "t2")
        XCTAssertEqual(a.id, b.id, "case-insensitive lemma should map to one canonical row")
    }

    func testIncrementLookupCount() throws {
        let (vocab, clock) = try makeService()
        let item = try vocab.upsert(lemma: "issue", type: .word, meaning: "m", translation: "t")
        clock.advance(30)
        try vocab.incrementLookupCount(id: item.id)
        try vocab.incrementLookupCount(id: item.id)
        let reloaded = try vocab.get(id: item.id)
        XCTAssertEqual(reloaded?.lookupCount, 2)
        XCTAssertEqual(reloaded?.lastSeenAt, clock.current)
    }

    func testMarkUnderstoodPersists() throws {
        let (vocab, _) = try makeService()
        let item = try vocab.upsert(lemma: "facilitate", type: .word, meaning: "m", translation: "t")
        try vocab.markUnderstood(id: item.id)
        XCTAssertEqual(try vocab.get(id: item.id)?.status, .understood)
    }

    func testUpsertDoesNotResetCountOrStatus() throws {
        let (vocab, _) = try makeService()
        let item = try vocab.upsert(lemma: "phase out", type: .phrasalVerb, meaning: "m", translation: "t")
        try vocab.incrementLookupCount(id: item.id)
        try vocab.markUnderstood(id: item.id)
        let again = try vocab.upsert(lemma: "phase out", type: .phrasalVerb, meaning: "m", translation: "t")
        XCTAssertEqual(again.lookupCount, 1)
        XCTAssertEqual(again.status, .understood)
    }

    func testAllReturnsInsertedItems() throws {
        let (vocab, _) = try makeService()
        _ = try vocab.upsert(lemma: "alpha", type: .word, meaning: "m", translation: "t")
        _ = try vocab.upsert(lemma: "beta", type: .word, meaning: "m", translation: "t")
        XCTAssertEqual(try vocab.all().count, 2)
    }

    func testUpsertStoresCEFROnInsert() throws {
        let db = try Database.inMemory()
        let vocab = VocabularyService(database: db)
        let item = try vocab.upsert(lemma: "ubiquitous", type: .word, meaning: "phổ biến",
                                    translation: "phổ biến", cefr: .c1)
        XCTAssertEqual(item.cefr, .c1)
        XCTAssertEqual(try vocab.get(id: item.id)?.cefr, .c1)
    }

    func testUpsertBackfillsCEFRWhenPreviouslyNil() throws {
        let db = try Database.inMemory()
        let vocab = VocabularyService(database: db)
        let first = try vocab.upsert(lemma: "issue", type: .word, meaning: "m", translation: "t", cefr: nil)
        XCTAssertNil(first.cefr)
        let second = try vocab.upsert(lemma: "issue", type: .word, meaning: "m", translation: "t", cefr: .b1)
        XCTAssertEqual(second.cefr, .b1)
    }

    func testUpsertDoesNotClobberExistingCEFRWithNil() throws {
        let db = try Database.inMemory()
        let vocab = VocabularyService(database: db)
        _ = try vocab.upsert(lemma: "issue", type: .word, meaning: "m", translation: "t", cefr: .b1)
        let again = try vocab.upsert(lemma: "issue", type: .word, meaning: "m", translation: "t", cefr: nil)
        XCTAssertEqual(again.cefr, .b1)
    }

    func testUpsertDoesNotClobberExistingCEFRWithDifferentLevel() throws {
        let db = try Database.inMemory()
        let vocab = VocabularyService(database: db)
        _ = try vocab.upsert(lemma: "issue", type: .word, meaning: "m", translation: "t", cefr: .b1)
        // The first recognized level is sticky — a later differing level is ignored.
        let again = try vocab.upsert(lemma: "issue", type: .word, meaning: "m", translation: "t", cefr: .c1)
        XCTAssertEqual(again.cefr, .b1)
        XCTAssertEqual(try vocab.get(id: again.id)?.cefr, .b1)
    }

    func testCountsByCEFRGroupsUnderstoodAndLearning() throws {
        let db = try Database.inMemory()
        let vocab = VocabularyService(database: db)
        let a = try vocab.upsert(lemma: "cat", type: .word, meaning: "m", translation: "t", cefr: .a1)
        _ = try vocab.upsert(lemma: "dog", type: .word, meaning: "m", translation: "t", cefr: .a1)
        _ = try vocab.upsert(lemma: "no-level", type: .word, meaning: "m", translation: "t", cefr: nil)
        try vocab.markUnderstood(id: a.id)
        let counts = try vocab.vocabularyCountsByCEFR()
        XCTAssertEqual(counts[.a1]?.understood, 1)
        XCTAssertEqual(counts[.a1]?.learning, 1)
        XCTAssertNil(counts[.b1])
    }
}

final class LookupHistoryServiceTests: XCTestCase {

    private func makeServices() throws -> (LookupHistoryService, VocabularyService, TestClock) {
        let clock = TestClock()
        let db = try Database.inMemory()
        return (LookupHistoryService(database: db, now: clock.now),
                VocabularyService(database: db, now: clock.now),
                clock)
    }

    func testRecordPreservesContextAndText() throws {
        let (history, _, _) = try makeServices()
        let lookup = try history.record(selectedText: "withdrew",
                                        normalizedText: "withdrew",
                                        sourceApplication: "Safari",
                                        context: "The company withdrew its offer.",
                                        translation: "rút lại")
        let all = try history.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.context, "The company withdrew its offer.")
        XCTAssertEqual(all.first?.sourceApplication, "Safari")
        XCTAssertEqual(lookup.selectedText, "withdrew")
    }

    func testOccurrencesLinkVocabularyToLookups() throws {
        let (history, vocab, _) = try makeServices()
        let item = try vocab.upsert(lemma: "ubiquitous", type: .word, meaning: "everywhere", translation: "phổ biến")
        let l1 = try history.record(selectedText: "ubiquitous", normalizedText: "ubiquitous",
                                    sourceApplication: nil, context: "Smartphones are ubiquitous.",
                                    translation: "t")
        let l2 = try history.record(selectedText: "Ubiquitous computing", normalizedText: "ubiquitous computing",
                                    sourceApplication: nil, context: "Ubiquitous computing is here.",
                                    translation: "t")
        _ = try history.addOccurrence(vocabularyId: item.id, lookupId: l1.id,
                                      surfaceForm: "ubiquitous", context: "Smartphones are ubiquitous.")
        _ = try history.addOccurrence(vocabularyId: item.id, lookupId: l2.id,
                                      surfaceForm: "Ubiquitous", context: "Ubiquitous computing is here.")
        let occ = try history.occurrences(forVocabularyId: item.id)
        XCTAssertEqual(occ.count, 2)
        XCTAssertEqual(Set(occ.map { $0.surfaceForm }), ["ubiquitous", "Ubiquitous"])
    }
}
