import XCTest
@testable import MemodicsCore

final class TranslationParsingTests: XCTestCase {

    func testParsesSpecExample() throws {
        // Verbatim shape from SPEC §9.
        let json = """
        {
          "translation": "The translated text",
          "vocabulary": [
            {
              "surfaceForm": "withdrew",
              "lemma": "withdraw",
              "meaning": "rút lại",
              "partOfSpeech": "verb"
            }
          ]
        }
        """
        let result = try TranslationResponseParser.parse(Data(json.utf8))
        XCTAssertEqual(result.translation, "The translated text")
        XCTAssertEqual(result.vocabulary.count, 1)
        let v = result.vocabulary[0]
        XCTAssertEqual(v.surfaceForm, "withdrew")
        XCTAssertEqual(v.lemma, "withdraw")
        XCTAssertEqual(v.meaning, "rút lại")
        XCTAssertEqual(v.partOfSpeech, "verb")
    }

    func testParsesExplicitVocabularyType() throws {
        let json = """
        { "translation": "t", "vocabulary": [
            { "surfaceForm": "phased out", "lemma": "phase out", "meaning": "loại bỏ dần", "type": "phrasal_verb" }
        ]}
        """
        let result = try TranslationResponseParser.parse(Data(json.utf8))
        XCTAssertEqual(result.vocabulary[0].type, .phrasalVerb)
    }

    func testMissingVocabularyArrayYieldsEmpty() throws {
        let json = #"{ "translation": "only translation" }"#
        let result = try TranslationResponseParser.parse(Data(json.utf8))
        XCTAssertEqual(result.translation, "only translation")
        XCTAssertTrue(result.vocabulary.isEmpty)
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try TranslationResponseParser.parse(Data("not json".utf8)))
    }

    func testMissingTranslationFieldThrows() {
        // A response with no translation is unusable (SPEC §24 malformed response).
        XCTAssertThrowsError(try TranslationResponseParser.parse(Data(#"{"vocabulary": []}"#.utf8)))
    }

    func testExtractsJSONEmbeddedInMarkdownFence() throws {
        // LLMs frequently wrap JSON in ```json fences; the parser must recover it.
        let text = """
        Here you go:
        ```json
        { "translation": "hi", "vocabulary": [] }
        ```
        """
        let result = try TranslationResponseParser.parse(fromText: text)
        XCTAssertEqual(result.translation, "hi")
    }

    func testAnalyzedVocabularyDecodesWithoutCEFRAsNil() throws {
        let json = #"[{"surfaceForm":"cats","lemma":"cat","meaning":"mèo","type":"word","partOfSpeech":"noun"}]"#
        let decoded = try JSONDecoder().decode([AnalyzedVocabulary].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.first?.cefr, nil)
    }
    func testAnalyzedVocabularyRoundTripsCEFR() throws {
        let v = AnalyzedVocabulary(surfaceForm: "cats", lemma: "cat", meaning: "mèo",
                                   type: .word, partOfSpeech: "noun", cefr: .a1)
        let data = try JSONEncoder().encode([v])
        let back = try JSONDecoder().decode([AnalyzedVocabulary].self, from: data)
        XCTAssertEqual(back.first?.cefr, .a1)
    }
}

final class MockTranslationProviderTests: XCTestCase {

    func testReturnsConfiguredResultAndRecordsCalls() async throws {
        let canned = TranslationResult(translation: "xin chào", vocabulary: [
            AnalyzedVocabulary(surfaceForm: "hello", lemma: "hello", meaning: "xin chào",
                               type: .word, partOfSpeech: "interjection")
        ])
        let mock = MockTranslationProvider(result: canned)
        let out = try await mock.analyze(text: "hello", knownVocabulary: [])
        XCTAssertEqual(out.translation, "xin chào")
        XCTAssertEqual(mock.callCount, 1)
        XCTAssertEqual(mock.lastText, "hello")
    }

    func testCanBeConfiguredToThrow() async {
        let mock = MockTranslationProvider(error: TranslationProviderError.requestFailed("boom"))
        do {
            _ = try await mock.analyze(text: "x", knownVocabulary: [])
            XCTFail("expected throw")
        } catch {
            // expected
        }
    }
}
