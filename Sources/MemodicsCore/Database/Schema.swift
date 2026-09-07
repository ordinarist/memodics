import Foundation

/// SQL DDL for each schema version. Applied by `Database.migrate()`.
///
/// Tables mirror the conceptual schemas in SPEC §15–18. Timestamps are stored
/// as Unix epoch seconds (REAL) for simple, locale-independent comparison.
enum Schema {

    /// Version 1 — the full MVP schema.
    static let v1 = """
    CREATE TABLE sentence_cache (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        text_hash       TEXT NOT NULL UNIQUE,
        normalized_text TEXT NOT NULL,
        translation     TEXT NOT NULL,
        analysis_json   TEXT NOT NULL,
        created_at      REAL NOT NULL,
        last_used_at    REAL NOT NULL
    );

    CREATE TABLE vocabulary (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        lemma         TEXT NOT NULL,
        type          TEXT NOT NULL,
        meaning       TEXT NOT NULL,
        translation   TEXT NOT NULL,
        lookup_count  INTEGER NOT NULL DEFAULT 0,
        status        TEXT NOT NULL DEFAULT 'learning',
        first_seen_at REAL NOT NULL,
        last_seen_at  REAL NOT NULL
    );

    -- One canonical vocabulary row per (lemma, type). Surface forms map here.
    CREATE UNIQUE INDEX idx_vocabulary_lemma_type ON vocabulary(lemma, type);

    CREATE TABLE lookup (
        id                 INTEGER PRIMARY KEY AUTOINCREMENT,
        selected_text      TEXT NOT NULL,
        normalized_text    TEXT NOT NULL,
        source_application TEXT,
        context            TEXT,
        translation        TEXT NOT NULL,
        created_at         REAL NOT NULL
    );

    CREATE TABLE vocabulary_occurrence (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        vocabulary_id INTEGER NOT NULL REFERENCES vocabulary(id) ON DELETE CASCADE,
        lookup_id     INTEGER NOT NULL REFERENCES lookup(id) ON DELETE CASCADE,
        surface_form  TEXT NOT NULL,
        context       TEXT,
        created_at    REAL NOT NULL
    );

    CREATE INDEX idx_occurrence_vocabulary ON vocabulary_occurrence(vocabulary_id);
    CREATE INDEX idx_occurrence_lookup ON vocabulary_occurrence(lookup_id);
    """
}
