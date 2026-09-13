import Foundation

/// A single vocabulary unit identified within a translation. SPEC §9, §10.
public struct AnalyzedVocabulary: Equatable, Sendable, Codable {
    /// The exact form as it appeared in the source text (e.g. "withdrew").
    public var surfaceForm: String
    /// Canonical lemma the surface form maps to (e.g. "withdraw"). SPEC §12.
    public var lemma: String
    /// Contextual meaning (typically the target-language gloss). SPEC §10.
    public var meaning: String
    /// Vocabulary category. SPEC §16.
    public var type: VocabularyType
    /// Optional part-of-speech tag from the provider (SPEC §9 example).
    public var partOfSpeech: String?

    public init(surfaceForm: String, lemma: String, meaning: String,
                type: VocabularyType = .word, partOfSpeech: String? = nil) {
        self.surfaceForm = surfaceForm
        self.lemma = lemma
        self.meaning = meaning
        self.type = type
        self.partOfSpeech = partOfSpeech
    }
}

public extension Array where Element == AnalyzedVocabulary {
    /// Stable sort by `type.displayRank`; provider order breaks ties.
    func rankedForDisplay() -> [AnalyzedVocabulary] {
        enumerated()
            .sorted { ($0.element.type.displayRank, $0.offset) < ($1.element.type.displayRank, $1.offset) }
            .map(\.element)
    }
}

/// Structured result of a translation/analysis. SPEC §9 — the provider must
/// return structured data, never an unstructured blob.
public struct TranslationResult: Equatable, Sendable {
    public var translation: String
    public var vocabulary: [AnalyzedVocabulary]

    public init(translation: String, vocabulary: [AnalyzedVocabulary]) {
        self.translation = translation
        self.vocabulary = vocabulary
    }
}
