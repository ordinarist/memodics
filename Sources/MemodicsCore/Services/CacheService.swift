import Foundation

/// Local sentence cache. SPEC §15, §20, §21.
///
/// The cache is keyed by the SHA-256 of the *normalized* selection so repeated
/// selections of the same text never trigger a translation API call.
public final class CacheService {

    private let db: Database
    private let now: () -> Date

    public init(database: Database, now: @escaping () -> Date = { Date() }) {
        self.db = database
        self.now = now
    }

    /// Return the cached entry for `rawText` if present, refreshing `lastUsedAt`.
    public func get(forRawText rawText: String) throws -> SentenceCacheEntry? {
        let hash = CacheKey.make(fromRawText: rawText)
        let rows = try db.query(
            "SELECT id, text_hash, normalized_text, translation, analysis_json, created_at, last_used_at FROM sentence_cache WHERE text_hash = ?",
            [.text(hash)], map: Self.mapRow)
        guard var entry = rows.first else { return nil }

        let ts = now()
        try db.run("UPDATE sentence_cache SET last_used_at = ? WHERE id = ?",
                   [.double(ts.timeIntervalSince1970), .int(entry.id)])
        entry.lastUsedAt = ts
        return entry
    }

    /// Insert (or replace) a cache entry for `rawText`.
    @discardableResult
    public func store(rawText: String, translation: String, analysisJSON: String) throws -> SentenceCacheEntry {
        let normalized = TextNormalizer.normalize(rawText)
        let hash = CacheKey.hash(ofNormalizedText: normalized)
        let ts = now()
        try db.run("""
            INSERT INTO sentence_cache (text_hash, normalized_text, translation, analysis_json, created_at, last_used_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(text_hash) DO UPDATE SET
                translation = excluded.translation,
                analysis_json = excluded.analysis_json,
                last_used_at = excluded.last_used_at
            """,
            [.text(hash), .text(normalized), .text(translation), .text(analysisJSON),
             .double(ts.timeIntervalSince1970), .double(ts.timeIntervalSince1970)])

        // Read back to get the canonical row (id, created_at may predate an upsert).
        let rows = try db.query(
            "SELECT id, text_hash, normalized_text, translation, analysis_json, created_at, last_used_at FROM sentence_cache WHERE text_hash = ?",
            [.text(hash)], map: Self.mapRow)
        return rows[0]
    }

    private static func mapRow(_ r: Row) -> SentenceCacheEntry {
        SentenceCacheEntry(
            id: r.int(0), textHash: r.string(1), normalizedText: r.string(2),
            translation: r.string(3), analysisJSON: r.string(4),
            createdAt: r.date(5), lastUsedAt: r.date(6))
    }
}
