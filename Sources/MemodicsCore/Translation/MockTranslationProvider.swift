import Foundation

/// A configurable in-memory provider for tests and offline development.
///
/// Records how it was called so tests can assert the cache prevents API calls
/// (SPEC §21). Marked `@unchecked Sendable` because its mutable bookkeeping is
/// only ever touched from test code (single-threaded).
public final class MockTranslationProvider: TranslationProvider, @unchecked Sendable {

    private let result: TranslationResult?
    private let error: Error?

    public private(set) var callCount = 0
    public private(set) var lastText: String?
    public private(set) var lastKnownVocabulary: [VocabularyItem] = []

    public init(result: TranslationResult) {
        self.result = result
        self.error = nil
    }

    public init(error: Error) {
        self.result = nil
        self.error = error
    }

    public func analyze(text: String, knownVocabulary: [VocabularyItem]) async throws -> TranslationResult {
        callCount += 1
        lastText = text
        lastKnownVocabulary = knownVocabulary
        if let error { throw error }
        return result ?? TranslationResult(translation: "", vocabulary: [])
    }
}
