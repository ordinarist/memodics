import Foundation

/// Persistence and lifecycle for vocabulary items. SPEC §10–13, §16.
///
/// Canonicalization strategy (SPEC §12): the caller supplies the lemma (from the
/// translation provider); we match it case-insensitively and store a trimmed,
/// lowercased canonical form so surface forms (withdraw/withdrew/withdrawn) all
/// map to a single row. We deliberately avoid full morphological analysis.
public final class VocabularyService {

    private let db: Database
    private let now: () -> Date

    public init(database: Database, now: @escaping () -> Date = { Date() }) {
        self.db = database
        self.now = now
    }

    /// Canonical form used for identity/matching.
    static func canonicalLemma(_ lemma: String) -> String {
        lemma.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Find-or-create the canonical item for `(lemma, type)`. An existing item's
    /// `lookupCount` and `status` are preserved (SPEC §11 — understood is sticky).
    @discardableResult
    public func upsert(lemma: String, type: VocabularyType, meaning: String, translation: String) throws -> VocabularyItem {
        let canonical = Self.canonicalLemma(lemma)
        if let existing = try find(lemma: canonical, type: type) {
            return existing
        }
        let ts = now().timeIntervalSince1970
        try db.run("""
            INSERT INTO vocabulary (lemma, type, meaning, translation, lookup_count, status, first_seen_at, last_seen_at)
            VALUES (?, ?, ?, ?, 0, 'learning', ?, ?)
            """,
            [.text(canonical), .text(type.rawValue), .text(meaning), .text(translation),
             .double(ts), .double(ts)])
        return try find(lemma: canonical, type: type)!
    }

    public func find(lemma: String, type: VocabularyType) throws -> VocabularyItem? {
        let canonical = Self.canonicalLemma(lemma)
        return try db.query(
            "SELECT \(Self.columns) FROM vocabulary WHERE lemma = ? AND type = ?",
            [.text(canonical), .text(type.rawValue)], map: Self.mapRow).first
    }

    public func get(id: Int64) throws -> VocabularyItem? {
        try db.query("SELECT \(Self.columns) FROM vocabulary WHERE id = ?",
                     [.int(id)], map: Self.mapRow).first
    }

    /// SPEC §12: lookupCount += 1, refreshing lastSeenAt.
    public func incrementLookupCount(id: Int64) throws {
        try db.run("UPDATE vocabulary SET lookup_count = lookup_count + 1, last_seen_at = ? WHERE id = ?",
                   [.double(now().timeIntervalSince1970), .int(id)])
    }

    /// SPEC §11: mark understood. The row and its history are never deleted.
    public func markUnderstood(id: Int64) throws {
        try db.run("UPDATE vocabulary SET status = 'understood' WHERE id = ?", [.int(id)])
    }

    /// Reset an item to the learning state (lets the user undo a mistaken mark).
    public func markLearning(id: Int64) throws {
        try db.run("UPDATE vocabulary SET status = 'learning' WHERE id = ?", [.int(id)])
    }

    /// All items, most-looked-up first (dashboard ordering, SPEC §19).
    public func all() throws -> [VocabularyItem] {
        try db.query("SELECT \(Self.columns) FROM vocabulary ORDER BY lookup_count DESC, last_seen_at DESC",
                     map: Self.mapRow)
    }

    /// Filtered, paginated search for the dashboard (SPEC §19). Matches `query`
    /// as a case-insensitive substring of the lemma or meaning; optional status
    /// filter; optional limit/offset for pagination. Empty query matches all.
    public func search(_ query: String, status: VocabularyStatus? = nil,
                       limit: Int? = nil, offset: Int = 0) throws -> [VocabularyItem] {
        var sql = "SELECT \(Self.columns) FROM vocabulary WHERE \(Self.matchClause)"
        var params = Self.matchParams(query)
        if let status {
            sql += " AND status = ?"
            params.append(.text(status.rawValue))
        }
        sql += " ORDER BY lookup_count DESC, last_seen_at DESC"
        if let limit {
            sql += " LIMIT ? OFFSET ?"
            params.append(.int(limit))
            params.append(.int(offset))
        }
        return try db.query(sql, params, map: Self.mapRow)
    }

    /// Total number of items matching `query` (for pagination totals).
    public func count(matching query: String, status: VocabularyStatus? = nil) throws -> Int {
        var sql = "SELECT COUNT(*) FROM vocabulary WHERE \(Self.matchClause)"
        var params = Self.matchParams(query)
        if let status {
            sql += " AND status = ?"
            params.append(.text(status.rawValue))
        }
        return try db.query(sql, params) { $0.intValue(0) }.first ?? 0
    }

    // LIKE-based substring match on lemma OR meaning, with escaped wildcards.
    private static let matchClause =
        "(lemma LIKE ? ESCAPE '\\' OR meaning LIKE ? ESCAPE '\\')"

    private static func matchParams(_ query: String) -> [SQLValue] {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = "%\(escaped)%"
        return [.text(pattern), .text(pattern)]
    }

    // MARK: - Row mapping

    private static let columns = "id, lemma, type, meaning, translation, lookup_count, status, first_seen_at, last_seen_at"

    private static func mapRow(_ r: Row) -> VocabularyItem {
        VocabularyItem(
            id: r.int(0),
            lemma: r.string(1),
            type: VocabularyType(rawValue: r.string(2)) ?? .word,
            meaning: r.string(3),
            translation: r.string(4),
            lookupCount: r.intValue(5),
            status: VocabularyStatus(rawValue: r.string(6)) ?? .learning,
            firstSeenAt: r.date(7),
            lastSeenAt: r.date(8))
    }
}
