import XCTest
@testable import MemodicsCore

final class LookupPipelineTests: XCTestCase {

    private func makeHarness(result: TranslationResult) throws
        -> (LookupPipeline, MockTranslationProvider, VocabularyService, TestClock) {
        let clock = TestClock()
        let db = try Database.inMemory()
        let provider = MockTranslationProvider(result: result)
        let pipeline = LookupPipeline(
            provider: provider,
            cache: CacheService(database: db, now: clock.now),
            vocabulary: VocabularyService(database: db, now: clock.now),
            history: LookupHistoryService(database: db, now: clock.now))
        let vocab = VocabularyService(database: db, now: clock.now)
        return (pipeline, provider, vocab, clock)
    }

    private let sample = TranslationResult(
        translation: "Công ty đã rút lại đề nghị sau khi cuộc đàm phán thất bại.",
        vocabulary: [
            AnalyzedVocabulary(surfaceForm: "withdrew", lemma: "withdraw", meaning: "rút lại", type: .word),
            AnalyzedVocabulary(surfaceForm: "negotiations", lemma: "negotiation", meaning: "đàm phán", type: .word),
        ])

    func testFirstLookupCallsProviderAndPersists() async throws {
        let (pipeline, provider, vocab, _) = try makeHarness(result: sample)
        let outcome = try await pipeline.lookup(rawText: "The company withdrew its offer after negotiations failed.",
                                                sourceApplication: "Safari")
        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(outcome.translation, sample.translation)
        XCTAssertFalse(outcome.servedFromCache)
        XCTAssertEqual(outcome.vocabulary.count, 2)
        XCTAssertEqual(try vocab.all().count, 2)
        XCTAssertEqual(try vocab.find(lemma: "withdraw", type: .word)?.lookupCount, 1)
    }

    func testRepeatLookupUsesCacheWithoutCallingProvider() async throws {
        let (pipeline, provider, _, _) = try makeHarness(result: sample)
        let text = "The company withdrew its offer after negotiations failed."
        _ = try await pipeline.lookup(rawText: text, sourceApplication: "Safari")
        let second = try await pipeline.lookup(rawText: text + "   ", sourceApplication: "Safari")

        XCTAssertEqual(provider.callCount, 1, "cache hit must not call the API (SPEC §21)")
        XCTAssertTrue(second.servedFromCache)
        XCTAssertEqual(second.translation, sample.translation)
    }

    func testLookupCountIncrementsEvenOnCacheHit() async throws {
        let (pipeline, _, vocab, _) = try makeHarness(result: sample)
        let text = "The company withdrew its offer after negotiations failed."
        _ = try await pipeline.lookup(rawText: text, sourceApplication: nil)
        _ = try await pipeline.lookup(rawText: text, sourceApplication: nil)
        XCTAssertEqual(try vocab.find(lemma: "withdraw", type: .word)?.lookupCount, 2)
    }

    func testUnderstoodVocabularyIsNotHighlightedButStillCounts() async throws {
        let (pipeline, _, vocab, _) = try makeHarness(result: sample)
        let text = "The company withdrew its offer after negotiations failed."
        _ = try await pipeline.lookup(rawText: text, sourceApplication: nil)

        let withdraw = try vocab.find(lemma: "withdraw", type: .word)!
        try vocab.markUnderstood(id: withdraw.id)

        let outcome = try await pipeline.lookup(rawText: text, sourceApplication: nil)
        let entry = outcome.vocabulary.first { $0.item.lemma == "withdraw" }!
        XCTAssertEqual(entry.highlightLevel, 0, "understood vocab must not highlight")
        XCTAssertEqual(entry.item.lookupCount, 2, "count still increments")
    }

    func testOccurrencesRecordedWithContext() async throws {
        let clock = TestClock()
        let db = try Database.inMemory()
        let provider = MockTranslationProvider(result: sample)
        let history = LookupHistoryService(database: db, now: clock.now)
        let vocab = VocabularyService(database: db, now: clock.now)
        let pipeline = LookupPipeline(
            provider: provider,
            cache: CacheService(database: db, now: clock.now),
            vocabulary: vocab, history: history)

        let text = "The company withdrew its offer after negotiations failed."
        _ = try await pipeline.lookup(rawText: text, sourceApplication: "Safari")

        let item = try vocab.find(lemma: "withdraw", type: .word)!
        let occ = try history.occurrences(forVocabularyId: item.id)
        XCTAssertEqual(occ.count, 1)
        XCTAssertEqual(occ.first?.surfaceForm, "withdrew")
        XCTAssertEqual(occ.first?.context, text)
    }
}
