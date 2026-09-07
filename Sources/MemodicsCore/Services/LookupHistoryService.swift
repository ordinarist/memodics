import Foundation

/// Persists every lookup and the vocabulary occurrences within it. SPEC §17, §18.
///
/// A lookup preserves enough information (selected text + context + source app)
/// to reconstruct what the user actually encountered — never just the word.
public final class LookupHistoryService {

    private let db: Database
    private let now: () -> Date

    public init(database: Database, now: @escaping () -> Date = { Date() }) {
        self.db = database
        self.now = now
    }

    @discardableResult
    public func record(selectedText: String, normalizedText: String, sourceApplication: String?,
                       context: String?, translation: String) throws -> Lookup {
        let ts = now()
        let id = try db.run("""
            INSERT INTO lookup (selected_text, normalized_text, source_application, context, translation, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            [.text(selectedText), .text(normalizedText), .text(sourceApplication),
             .text(context), .text(translation), .double(ts.timeIntervalSince1970)])
        return Lookup(id: id, selectedText: selectedText, normalizedText: normalizedText,
                      sourceApplication: sourceApplication, context: context,
                      translation: translation, createdAt: ts)
    }

    public func all() throws -> [Lookup] {
        try db.query("""
            SELECT id, selected_text, normalized_text, source_application, context, translation, created_at
            FROM lookup ORDER BY created_at DESC
            """, map: Self.mapLookup)
    }

    @discardableResult
    public func addOccurrence(vocabularyId: Int64, lookupId: Int64, surfaceForm: String,
                              context: String?) throws -> VocabularyOccurrence {
        let ts = now()
        let id = try db.run("""
            INSERT INTO vocabulary_occurrence (vocabulary_id, lookup_id, surface_form, context, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            [.int(vocabularyId), .int(lookupId), .text(surfaceForm), .text(context),
             .double(ts.timeIntervalSince1970)])
        return VocabularyOccurrence(id: id, vocabularyId: vocabularyId, lookupId: lookupId,
                                    surfaceForm: surfaceForm, context: context, createdAt: ts)
    }

    /// Historical contexts for a vocabulary item, newest first (dashboard, SPEC §19).
    public func occurrences(forVocabularyId vocabularyId: Int64) throws -> [VocabularyOccurrence] {
        try db.query("""
            SELECT id, vocabulary_id, lookup_id, surface_form, context, created_at
            FROM vocabulary_occurrence WHERE vocabulary_id = ? ORDER BY created_at DESC
            """, [.int(vocabularyId)], map: Self.mapOccurrence)
    }

    private static func mapLookup(_ r: Row) -> Lookup {
        Lookup(id: r.int(0), selectedText: r.string(1), normalizedText: r.string(2),
               sourceApplication: r.stringOptional(3), context: r.stringOptional(4),
               translation: r.string(5), createdAt: r.date(6))
    }

    private static func mapOccurrence(_ r: Row) -> VocabularyOccurrence {
        VocabularyOccurrence(id: r.int(0), vocabularyId: r.int(1), lookupId: r.int(2),
                             surfaceForm: r.string(3), context: r.stringOptional(4),
                             createdAt: r.date(5))
    }
}
