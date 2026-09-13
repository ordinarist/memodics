import Foundation

/// A vocabulary entry as presented in a lookup outcome: the canonical item
/// (with its current count/status) plus the surface form seen and the computed
/// highlight level.
public struct LookupVocabulary: Equatable, Sendable {
    public let item: VocabularyItem
    public let surfaceForm: String
    public let meaning: String
    public let highlightLevel: Int

    public init(item: VocabularyItem, surfaceForm: String, meaning: String, highlightLevel: Int) {
        self.item = item
        self.surfaceForm = surfaceForm
        self.meaning = meaning
        self.highlightLevel = highlightLevel
    }
}

/// The result of a completed lookup, ready to render in the popup. SPEC §14.
public struct LookupOutcome: Equatable, Sendable {
    public let originalText: String
    public let normalizedText: String
    public let translation: String
    public let vocabulary: [LookupVocabulary]
    public let servedFromCache: Bool
}

/// Orchestrates the end-to-end lookup pipeline. SPEC §8, §21.
///
/// Order (cost-controlled): normalize → sentence-cache check → (API only on
/// miss) → store cache → persist lookup → upsert vocabulary + increment counts
/// (always, even on a cache hit) → record occurrences → build display outcome.
public final class LookupPipeline: @unchecked Sendable {

    private let provider: TranslationProvider
    private let cache: CacheService
    private let vocabulary: VocabularyService
    private let history: LookupHistoryService

    public init(provider: TranslationProvider, cache: CacheService,
                vocabulary: VocabularyService, history: LookupHistoryService) {
        self.provider = provider
        self.cache = cache
        self.vocabulary = vocabulary
        self.history = history
    }

    public func lookup(rawText: String, sourceApplication: String?) async throws -> LookupOutcome {
        let normalized = TextNormalizer.normalize(rawText)

        // 1–2. Cache check.
        let translation: String
        let analyzed: [AnalyzedVocabulary]
        let servedFromCache: Bool

        if let cached = try cache.get(forRawText: rawText) {
            translation = cached.translation
            analyzed = AnalysisCodec.decode(cached.analysisJSON)
            servedFromCache = true
        } else {
            // 3–4. Miss → call provider, passing understood vocabulary as "known"
            // so it need not be re-analyzed (SPEC §21).
            let known = try vocabulary.all().filter { $0.status == .understood }
            let result = try await provider.analyze(text: rawText, knownVocabulary: known)
            translation = result.translation
            analyzed = result.vocabulary
            // 5. Store cache.
            try cache.store(rawText: rawText, translation: translation,
                            analysisJSON: AnalysisCodec.encode(analyzed))
            servedFromCache = false
        }

        // 6. Persist the lookup (full context preserved — SPEC §17).
        let lookupRecord = try history.record(
            selectedText: rawText, normalizedText: normalized,
            sourceApplication: sourceApplication, context: rawText, translation: translation)

        // 7–8. Upsert vocab, bump counts (always), record occurrences.
        var displayVocab: [LookupVocabulary] = []
        for v in analyzed.rankedForDisplay() {
            let item = try vocabulary.upsert(lemma: v.lemma, type: v.type,
                                             meaning: v.meaning, translation: v.meaning,
                                             cefr: v.cefr)
            try vocabulary.incrementLookupCount(id: item.id)
            try history.addOccurrence(vocabularyId: item.id, lookupId: lookupRecord.id,
                                      surfaceForm: v.surfaceForm, context: rawText)
            // Reload for fresh count/status before computing the highlight.
            let refreshed = try vocabulary.get(id: item.id) ?? item
            displayVocab.append(LookupVocabulary(
                item: refreshed, surfaceForm: v.surfaceForm, meaning: v.meaning,
                highlightLevel: HighlightLevel.level(for: refreshed)))
        }

        return LookupOutcome(originalText: rawText, normalizedText: normalized,
                             translation: translation, vocabulary: displayVocab,
                             servedFromCache: servedFromCache)
    }
}
